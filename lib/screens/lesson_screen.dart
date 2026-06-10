// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/constants.dart';
import 'ai_tutor_tab.dart';

class LessonScreen extends StatefulWidget {
  final String lessonId;
  final String subject;
  const LessonScreen({super.key, required this.lessonId, required this.subject});
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _lesson;
  Map<String, dynamic>? _progress;
  bool _loading = true;
  String _studentId = '';
  String _token = '';
  final _tryItCtrl = TextEditingController();
  bool _submitted = false;
  bool _correct = false;
  bool _showAnswer = false;
  final _stopwatch = Stopwatch();
  String? _sessionId;
  DateTime? _sessionStart;
  String _currentSection = 'concept';
  Timer? _progressTimer;

  // â”€â”€ Tab state (0=Baca, 1=Dengar; Nova tab always navigates) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  int _tabIndex = 0;

  // â”€â”€ Dengar / TTS state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _ttsLoading = false;
  bool _ttsPlaying = false;
  html.AudioElement? _audioEl;
  String? _audioUrl;
  double _audioPosition = 0;
  double _audioDuration = 0;
  StreamSubscription? _timeSub;
  StreamSubscription? _endSub;
  late AnimationController _pulseCtrl;

  static const _kOrange = Color(0xFFF59E0B);
  static const _kPurple = Color(0xFF8B5CF6);
  static const _kGreen  = Color(0xFF10B981);
  static const _kBlue   = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _sessionStart = DateTime.now();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _load();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 30), (_) => _saveProgress());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _saveProgress();
    _tryItCtrl.dispose();
    _pulseCtrl.dispose();
    _disposeAudio();
    super.dispose();
  }

  // â”€â”€ Session tracking â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _openLesson() async {
    if (_studentId.isEmpty || _lesson == null) return;
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/progress/lesson-open'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'studentId': _studentId,
          'lessonId': widget.lessonId,
          'subject': widget.subject,
          'topic': _lesson!['topic'] as String? ?? '',
          'lessonTitle': _lesson!['lesson_title'] as String? ?? '',
        }),
      );
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        _sessionId = d['sessionId'] as String?;
      }
    } catch (_) {}
  }

  Future<void> _saveProgress() async {
    if (_studentId.isEmpty || widget.lessonId.isEmpty) return;
    final minutes = (_sessionStart != null)
        ? DateTime.now().difference(_sessionStart!).inMinutes
        : _stopwatch.elapsed.inMinutes;
    try {
      http.post(
        Uri.parse('$kApiUrl/api/progress/lesson-update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'studentId': _studentId,
          'lessonId': widget.lessonId,
          'subject': widget.subject,
          'topic': _lesson?['topic'] as String? ?? '',
          'sessionId': _sessionId,
          'lastSection': _currentSection,
          'scrollPosition': 0.0,
          'durationMinutes': minutes,
        }),
      ).ignore();
    } catch (_) {}
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token') ?? '';
    _studentId = prefs.getString('student_id') ?? '';

    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/lessons/lesson?lessonId=${widget.lessonId}&studentId=$_studentId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          _lesson   = d['lesson'] as Map<String, dynamic>?;
          _progress = d['progress'] as Map<String, dynamic>?;
          _submitted  = (_progress?['try_it_attempted'] as bool?) == true;
          _correct    = (_progress?['try_it_correct'] as bool?) == true;
          _showAnswer = _submitted;
          _loading = false;
        });
        await _openLesson();
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_tryItCtrl.text.trim().isEmpty) return;
    setState(() { _submitted = true; _showAnswer = true; _currentSection = 'try_it'; });
    final answer = (_lesson?['try_it_answer'] ?? '').toString().toLowerCase();
    final input  = _tryItCtrl.text.toLowerCase();
    final words  = answer.split(RegExp(r'\s+')).where((w) => w.length > 4).take(3).toList();
    final matchCount = words.where((w) => input.contains(w)).length;
    _correct = words.isNotEmpty && matchCount >= (words.length / 2).ceil();
  }

  Future<void> _complete() async {
    _stopwatch.stop();
    _progressTimer?.cancel();
    if (_studentId.isEmpty || widget.lessonId.isEmpty) return;
    setState(() => _currentSection = 'completed');
    final minutes = (_sessionStart != null)
        ? DateTime.now().difference(_sessionStart!).inMinutes
        : _stopwatch.elapsed.inMinutes;
    try {
      await Future.wait([
        http.post(
          Uri.parse('$kApiUrl/api/progress/lesson-complete'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'studentId': _studentId,
            'lessonId': widget.lessonId,
            'subject': widget.subject,
            'topic': _lesson?['topic'] as String? ?? '',
            'sessionId': _sessionId,
            'durationMinutes': minutes,
          }),
        ),
        http.post(
          Uri.parse('$kApiUrl/api/lessons/complete'),
          headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'lessonId': widget.lessonId,
            'studentId': _studentId,
            'tryItCorrect': _correct,
            'timeSpentSeconds': _stopwatch.elapsed.inSeconds,
          }),
        ),
      ]);
    } catch (_) {}
    if (mounted) Navigator.pop(context, true);
  }

  void _openNova() {
    final lesson = _lesson;
    if (lesson == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AITutorTab(
        selectedSubject: widget.subject,
        lessonContext: {
          'lesson_id':           lesson['id'],
          'lesson_title':        lesson['lesson_title'],
          'topic':               lesson['topic'],
          'concept_explanation': lesson['concept_explanation'],
          'worked_example':      lesson['worked_example'],
          'try_it_question':     lesson['try_it_question'],
        },
      ),
    ));
  }

  // â”€â”€ Tab switching â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _onTabTap(int i) {
    if (i == 2) {
      _openNova();
      return;
    }
    // Pause audio when switching away from Dengar
    if (_tabIndex == 1 && i == 0 && _ttsPlaying) {
      _audioEl?.pause();
      _pulseCtrl.stop();
      setState(() => _ttsPlaying = false);
    }
    // Auto-load when entering Dengar for first time
    if (i == 1 && _audioDuration == 0 && !_ttsLoading) {
      setState(() => _tabIndex = i);
      _loadAudio();
      return;
    }
    // Resume audio when returning to Dengar
    if (i == 1 && _audioDuration > 0 && !_ttsPlaying) {
      _audioEl?.play();
      _pulseCtrl.repeat(reverse: true);
      setState(() { _tabIndex = i; _ttsPlaying = true; });
      return;
    }
    setState(() => _tabIndex = i);
  }

  // â”€â”€ TTS / Dengar helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _buildListenText() {
    final l = _lesson!;
    final parts = <String>[];
    void add(String? v) { if (v != null && v.trim().isNotEmpty) parts.add(v.trim()); }
    add(l['hook_sentence'] as String?);
    add(l['concept_explanation'] as String?);
    add(l['worked_example'] as String?);
    add(l['try_it_question'] as String?);
    add(l['common_mistakes'] as String?);
    add(l['exam_technique'] as String?);
    final full = parts.join(' ');
    // Stay within OpenAI TTS 4096-char limit
    return full.length > 3800 ? full.substring(0, 3800) : full;
  }

  String _cleanForTts(String t) => t
    .replaceAll(RegExp(r'\*+'), '')
    .replaceAll(RegExp(r'#{1,6}\s', multiLine: true), '')
    .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}]', unicode: true), '')
    .replaceAll(RegExp(r'[\u{2600}-\u{27BF}]', unicode: true), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

  Future<void> _loadAudio() async {
    if (_ttsLoading || _lesson == null) return;
    setState(() { _ttsLoading = true; });

    try {
      // Use pre-generated audio from cPanel if available (free, instant)
      final pregenUrl = _lesson!['audio_url'] as String?;
      if (pregenUrl != null && pregenUrl.isNotEmpty) {
        _disposeAudio(keepState: true);
        _audioUrl = pregenUrl;
        _audioEl  = html.AudioElement(pregenUrl);
        _audioEl!.preload = 'auto';

        _timeSub = _audioEl!.onTimeUpdate.listen((_) {
          if (mounted) setState(() {
            _audioPosition = (_audioEl?.currentTime ?? 0).toDouble();
            final dur = _audioEl?.duration;
            _audioDuration = (dur != null && dur.isFinite ? dur : 0).toDouble();
          });
        });
        _endSub = _audioEl!.onEnded.listen((_) {
          _pulseCtrl.stop();
          if (mounted) setState(() { _ttsPlaying = false; _audioPosition = 0; });
        });

        await _audioEl!.play();
        _pulseCtrl.repeat(reverse: true);
        if (mounted) setState(() { _ttsLoading = false; _ttsPlaying = true; });
        return;
      }

      // Fall back to OpenAI TTS API
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final text = _cleanForTts(_buildListenText());

      final resp = await http.post(
        Uri.parse('$kApiUrl/api/tts'),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'text': text, 'voice': 'nova', 'language': 'bm'}),
      ).timeout(const Duration(seconds: 60));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final blob = html.Blob([resp.bodyBytes], 'audio/mpeg');
        final url  = html.Url.createObjectUrlFromBlob(blob);
        _disposeAudio(keepState: true);
        _audioUrl = url;
        _audioEl  = html.AudioElement(url);

        _timeSub = _audioEl!.onTimeUpdate.listen((_) {
          if (mounted) setState(() {
            _audioPosition = (_audioEl?.currentTime ?? 0).toDouble();
            final dur = _audioEl?.duration;
            _audioDuration = (dur != null && dur.isFinite ? dur : 0).toDouble();
          });
        });

        _endSub = _audioEl!.onEnded.listen((_) {
          if (_audioUrl != null) html.Url.revokeObjectUrl(_audioUrl!);
          _audioUrl = null;
          _pulseCtrl.stop();
          if (mounted) setState(() { _ttsPlaying = false; _audioPosition = 0; });
        });

        await _audioEl!.play();
        _pulseCtrl.repeat(reverse: true);
        if (mounted) setState(() { _ttsLoading = false; _ttsPlaying = true; });
      } else {
        if (mounted) setState(() { _ttsLoading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _ttsLoading = false; _ttsPlaying = false; });
    }
  }

  void _disposeAudio({bool keepState = false}) {
    _timeSub?.cancel();
    _endSub?.cancel();
    _timeSub = null;
    _endSub = null;
    try { _audioEl?.pause(); } catch (_) {}
    if (_audioUrl != null) {
      try { html.Url.revokeObjectUrl(_audioUrl!); } catch (_) {}
      _audioUrl = null;
    }
    _audioEl = null;
    if (!keepState) {
      _audioPosition = 0;
      _audioDuration = 0;
      _ttsPlaying = false;
      _ttsLoading = false;
    }
  }

  Future<void> _togglePlay() async {
    if (_ttsLoading) return;
    if (_audioDuration == 0) { await _loadAudio(); return; }
    if (_ttsPlaying) {
      _audioEl?.pause();
      _pulseCtrl.stop();
      setState(() => _ttsPlaying = false);
    } else {
      await _audioEl?.play();
      _pulseCtrl.repeat(reverse: true);
      setState(() => _ttsPlaying = true);
    }
  }

  void _restart() {
    if (_audioEl == null) return;
    _audioEl!.currentTime = 0;
    if (!_ttsPlaying) {
      _audioEl!.play();
      _pulseCtrl.repeat(reverse: true);
      setState(() => _ttsPlaying = true);
    }
  }

  void _skip30() {
    if (_audioEl == null || _audioDuration == 0) return;
    final next = (_audioPosition + 30).clamp(0.0, _audioDuration);
    _audioEl!.currentTime = next;
  }

  String _formatTime(int s) {
    final m = s ~/ 60;
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2)),
      );
    }
    if (_lesson == null) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(backgroundColor: kSurface, foregroundColor: kText, elevation: 0),
        body: const Center(child: Text('Pelajaran tidak dijumpai.', style: TextStyle(color: kMuted))),
      );
    }

    final l    = _lesson!;
    final diff = l['difficulty'] as String? ?? 'medium';
    final mins = (l['estimated_minutes'] as num?)?.toInt() ?? 15;

    return Scaffold(
      backgroundColor: kBg,
      body: Column(children: [
        // â”€â”€ Objective bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Container(
          width: double.infinity,
          color: kPrimary.withOpacity(0.1),
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 10, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_rounded, color: kMuted, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l['lesson_title'] as String? ?? '',
                  style: const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _diffBadge(diff),
              const SizedBox(width: 8),
              Text('~$mins min', style: const TextStyle(color: kMuted, fontSize: 11)),
            ]),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Text(
                'Objektif: ${l['objective'] ?? ''}',
                style: const TextStyle(color: kPrimary, fontSize: 12),
              ),
            ),
          ]),
        ),

        // â”€â”€ Mode tab bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        _buildTabBar(),

        // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Expanded(
          child: _tabIndex == 0 ? _buildBacaBody() : _buildDengarBody(),
        ),

        // â”€â”€ Bottom action row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
          decoration: const BoxDecoration(
            color: kSurface,
            border: Border(top: BorderSide(color: kBorder)),
          ),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openNova,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: const Text('Tanya Nova'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimary,
                  side: const BorderSide(color: kPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _complete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: const Text('Selesai →', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // â”€â”€ Tab bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildTabBar() {
    const tabs = [
      (Icons.menu_book_outlined, 'Baca'),
      (Icons.volume_up_outlined, 'Dengar'),
      (Icons.auto_awesome_outlined, 'Nova'),
    ];
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: List.generate(3, (i) {
          final active = i == _tabIndex;
          final (icon, label) = tabs[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => _onTabTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? kPrimary.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? kPrimary.withOpacity(0.4) : kBorder,
                  ),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: active ? kPrimary : kMuted, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? kPrimary : kMuted,
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  // â”€â”€ Baca mode â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildBacaBody() {
    final l = _lesson!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // 0. Hook sentence
        if ((l['hook_sentence'] as String?)?.isNotEmpty == true) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1040), Color(0xFF0D1117)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kPrimary.withOpacity(0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline_rounded, color: kPrimary, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(
                l['hook_sentence'] as String? ?? '',
                style: const TextStyle(color: kText, fontSize: 14, height: 1.6, fontStyle: FontStyle.italic),
              )),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // 1. Concept
        _sectionHeader('Konsep', Icons.lightbulb_outline_rounded, kText),
        const SizedBox(height: 8),
        Text(
          l['concept_explanation'] as String? ?? '',
          style: const TextStyle(color: kText, fontSize: 14, height: 1.65),
        ),

        // 2. Worked example
        if ((l['worked_example'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 20),
          _card(
            icon: Icons.check_circle_outline_rounded, label: 'Contoh', color: _kGreen,
            child: Text(
              l['worked_example'] as String? ?? '',
              style: const TextStyle(color: kText, fontSize: 13, height: 1.65),
            ),
          ),
        ],

        // 3. Try It
        if ((l['try_it_question'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 20),
          _card(
            icon: Icons.edit_outlined, label: 'Cuba kamu selesaikan', color: _kBlue,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                l['try_it_question'] as String? ?? '',
                style: const TextStyle(color: kText, fontSize: 13, height: 1.65),
              ),
              if (!_submitted) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _tryItCtrl,
                  style: const TextStyle(color: kText, fontSize: 14),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Tulis jawapan kamu di sini...',
                    hintStyle: const TextStyle(color: kMuted, fontSize: 13),
                    filled: true,
                    fillColor: kSurface2,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _kBlue),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBlue, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Text('Hantar Jawapan', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _correct ? _kGreen.withOpacity(0.1) : kRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _correct ? _kGreen.withOpacity(0.3) : kRed.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    Icon(
                      _correct ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      color: _correct ? _kGreen : kRed, size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _correct ? 'Bagus! Jawapan kamu betul.' : 'Semak jawapan penuh di bawah.',
                      style: TextStyle(
                        color: _correct ? _kGreen : kRed,
                        fontWeight: FontWeight.w600, fontSize: 13,
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ],

        // 4. Full answer after submit
        if (_showAnswer && (l['try_it_answer'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Jawapan Penuh:',
                style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                l['try_it_answer'] as String? ?? '',
                style: const TextStyle(color: kText, fontSize: 13, height: 1.65),
              ),
            ]),
          ),
        ],

        // 5. Common Mistakes
        if ((l['common_mistakes'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 20),
          _card(
            icon: Icons.warning_amber_rounded, label: 'Kesilapan Lazim', color: _kOrange,
            child: Text(
              l['common_mistakes'] as String? ?? '',
              style: const TextStyle(color: kText, fontSize: 13, height: 1.65),
            ),
          ),
        ],

        // 6. Exam Technique
        if ((l['exam_technique'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 20),
          _card(
            icon: Icons.star_outline_rounded, label: 'Teknik SPM', color: _kPurple,
            child: Text(
              l['exam_technique'] as String? ?? '',
              style: const TextStyle(color: kText, fontSize: 13, height: 1.65),
            ),
          ),
        ],

        // â”€â”€ Tak faham button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        const SizedBox(height: 28),
        OutlinedButton(
          onPressed: _openNova,
          style: OutlinedButton.styleFrom(
            foregroundColor: kMuted,
            side: BorderSide(color: kBorder),
            padding: const EdgeInsets.symmetric(vertical: 13),
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.help_outline_rounded, size: 15),
            SizedBox(width: 8),
            Text('Tak faham? Tanya Nova', style: TextStyle(fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // â”€â”€ Dengar mode â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildDengarBody() {
    final title = _lesson!['lesson_title'] as String? ?? '';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w700, height: 1.4),
            ),
            const SizedBox(height: 40),

            // Pulsing Nova avatar
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) {
                final scale = _ttsPlaying ? 1.0 + 0.12 * _pulseCtrl.value : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      color: kPrimary.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kPrimary.withOpacity(_ttsPlaying ? 0.55 : 0.2),
                        width: 2,
                      ),
                      boxShadow: _ttsPlaying
                        ? [BoxShadow(color: kPrimary.withOpacity(0.2), blurRadius: 20, spreadRadius: 2)]
                        : [],
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: kPrimary.withOpacity(_ttsPlaying ? 1.0 : 0.5),
                      size: 46,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 36),

            if (_ttsLoading) ...[
              const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2),
              ),
              const SizedBox(height: 14),
              const Text(
                'Sedang memuatkan...',
                style: TextStyle(color: kMuted, fontSize: 13),
              ),
            ] else ...[

              // Progress bar (only when audio is ready)
              if (_audioDuration > 0) ...[
                SliderTheme(
                  data: SliderThemeData(
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    trackHeight: 3,
                    activeTrackColor: kPrimary,
                    inactiveTrackColor: kBorder,
                    thumbColor: kPrimary,
                    overlayColor: kPrimary.withOpacity(0.12),
                  ),
                  child: Slider(
                    value: _audioPosition.clamp(0.0, _audioDuration),
                    min: 0,
                    max: _audioDuration,
                    onChanged: (v) => _audioEl?.currentTime = v,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(_audioPosition.toInt()),
                        style: const TextStyle(color: kMuted, fontSize: 11)),
                      Text(_formatTime(_audioDuration.toInt()),
                        style: const TextStyle(color: kMuted, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ],

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _audioBtn(
                    icon: Icons.replay_rounded,
                    label: 'Mula\nsemula',
                    onTap: _audioDuration > 0 ? _restart : null,
                  ),
                  const SizedBox(width: 20),
                  GestureDetector(
                    onTap: _togglePlay,
                    child: Container(
                      width: 68, height: 68,
                      decoration: BoxDecoration(
                        color: kPrimary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: kPrimary.withOpacity(0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        _ttsPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  _audioBtn(
                    icon: Icons.forward_30_rounded,
                    label: '+30s',
                    onTap: _audioDuration > 0 ? _skip30 : null,
                  ),
                ],
              ),

              if (_audioDuration == 0 && !_ttsLoading) ...[
                const SizedBox(height: 20),
                Text(
                  'Tekan â–¶ untuk dengar pelajaran ini',
                  style: TextStyle(color: kMuted.withOpacity(0.6), fontSize: 12),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _audioBtn({required IconData icon, required String label, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: kSurface2,
            shape: BoxShape.circle,
            border: Border.all(color: kBorder),
          ),
          child: Icon(icon, color: enabled ? kMuted : kBorder, size: 22),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: enabled ? kMuted : kBorder, fontSize: 10, height: 1.3),
        ),
      ]),
    );
  }

  // â”€â”€ Shared helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _sectionHeader(String label, IconData icon, Color color) => Row(children: [
    Icon(icon, color: color, size: 16),
    const SizedBox(width: 6),
    Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
  ]);

  Widget _card({required IconData icon, required String label, required Color color, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _diffBadge(String diff) {
    final color = diff == 'easy' ? _kGreen : diff == 'hard' ? kRed : _kOrange;
    final label = diff == 'easy' ? 'Mudah' : diff == 'hard' ? 'Sukar' : 'Sederhana';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
