import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../config/constants.dart';
import '../config/disclaimers.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'main_shell.dart';
import 'topic_intro_screen.dart';
import '../widgets/tts_player.dart';
import '../widgets/animation_panel.dart';
import '../widgets/topic_animation_player.dart';
import '../widgets/workspace_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AITutorTab extends StatefulWidget {
  final String selectedSubject;
  final String? initialTopic;
  final bool preRead;
  final Map<String, dynamic>? lessonContext;
  const AITutorTab({super.key, required this.selectedSubject, this.initialTopic, this.preRead = false, this.lessonContext});
  @override
  State<AITutorTab> createState() => _AITutorTabState();
}

class _AITutorTabState extends State<AITutorTab> with SingleTickerProviderStateMixin {
  final _ctrl       = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _loading         = false;
  bool _sessionStarting = false;
  String _currentSubject = 'Mathematics';

  bool   _tutorMode  = false;
  String? _currentTopic;
  String  _phase     = 'intro';
  int     _segment   = 0;
  List<String> _suggestedResponses = [];
  List<Map<String, dynamic>> _topics = [];
  List<String> _suggestions = [];
  String? _pendingSwitchTopic;
  // Set when an idle-screen intent chip (Jelaskan / Bagi kuiz / ...) is tapped
  // without a topic. Drained into the session as the student's first message
  // after _startTutorSession completes, so Nova teaches instead of asking
  // "which topic?".
  String? _pendingIntent;
  String? _currentStandardCode;
  String? _currentStandardDesc;
  String? _standardsProgress;
  String _language = 'bm';
  bool _useEnglish = false;

  // â”€â”€ Animation state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<Map<String, dynamic>> _animSteps    = [];
  List<Map<String, dynamic>> _animAltSteps = [];
  bool _showAnim        = false;
  bool _studentConfused = false;
  String? _lastAnimCode;

  // â”€â”€ Topic animation (pre-built, stored in engine, served on demand) â”€â”€
  Map<String, dynamic>? _topicAnimation;
  bool _showTopicAnim = true;

  // â”€â”€ Voice state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _isListening = false;
  bool _voiceMode   = false; // when true: auto-TTS + auto-mic loop

  // â”€â”€ Quiz state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Map<String, dynamic>? _activeQuestion;

  // â”€â”€ Workspace state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _workspaceSubmitting = false;
  bool _workspaceExpanded   = false;

  // â”€â”€ TTS state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String? _authToken;
  html.AudioElement? _audioElement;
  String? _audioBlobUrl;    // tracked separately so _stopSpeech can revoke it
  bool _ttsPlaying = false;
  int _ttsGeneration = 0;   // incremented each call; stale HTTP responses are discarded

  // â”€â”€ Illustration overlay state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _showIllustrationOverlay = false;
  String _illustrationTitle = '';
  String _currentSvgCode = '';
  List<Map<String, dynamic>> _topicIllustrations = [];
  int _illustrationIndex = 0;

  // â”€â”€ Character â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const List<Map<String, dynamic>> _kCharacters = [
    {'id': 'nova',   'name': 'Nova',        'emoji': 'â­', 'tagline': 'Mesra & sabar',    'color': 0xFF6C5CE7},
    {'id': 'sarjan', 'name': 'Sarjan Rex',  'emoji': 'ðŸŽ–', 'tagline': 'Tegas & disiplin', 'color': 0xFFDC2626},
    {'id': 'sensei', 'name': 'Sensei',      'emoji': 'â›©', 'tagline': 'Anime & dramatik', 'color': 0xFFDB2777},
    {'id': 'bestie', 'name': 'Bestie Alia', 'emoji': 'ðŸ¤™', 'tagline': 'Gen Z & santai',   'color': 0xFF059669},
    {'id': 'chaos',  'name': 'Chaos-chan',  'emoji': 'ðŸ”¥', 'tagline': 'Wild & energetik', 'color': 0xFFF59E0B},
  ];
  String _characterId = 'nova';

  // â”€â”€ Session tracking â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String? _sessionId;
  String? _studentId;
  DateTime? _novaSessionStart;

  // â”€â”€ Orb overlay state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _orbMode = false;
  late AnimationController _orbPulse;
  String _orbTranscript = '';

  @override
  void initState() {
    super.initState();
    _currentSubject = widget.selectedSubject;
    _orbPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _loadTopics();
    _loadSuggestions();
    _loadLanguage();
    _loadCharacter();
    // Load token â€” then start session if navigated from TopicIntroScreen or LessonScreen
    _loadToken().then((_) {
      if (!mounted) return;
      if (widget.lessonContext != null) {
        _enterLessonMode(widget.lessonContext!);
      } else if (widget.preRead && widget.initialTopic != null && widget.initialTopic!.isNotEmpty) {
        _startTutorSession(widget.initialTopic!, preRead: true);
      }
    });
  }

  // Enter Nova from a LessonScreen with lesson context pre-loaded
  void _enterLessonMode(Map<String, dynamic> lc) {
    final lessonTitle = lc['lesson_title'] as String? ?? lc['topic'] as String? ?? 'pelajaran ini';
    final topic = lc['topic'] as String? ?? '';
    _sessionId = _newSessionId();
    _novaSessionStart = DateTime.now();
    setState(() {
      _tutorMode    = true;
      _currentTopic = topic;
      _phase        = 'teach';
      _segment      = 0;
      _messages.clear();
    });
    context.findAncestorStateOfType<MainShellState>()?.setTutorMode(true);
    Future.microtask(() {
      if (mounted) _tutorSession('Saya nak faham $lessonTitle dengan lebih baik');
    });
  }

  String? _studentName;

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('token');
    _studentId = prefs.getString('student_id');
    _studentName = prefs.getString('student_name') ?? prefs.getString('name');
  }

  Future<void> _loadCharacter() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('character_id') ?? 'nova';
    if (mounted) setState(() => _characterId = saved);
  }

  Future<void> _saveCharacter(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('character_id', id);
    setState(() => _characterId = id);
  }

  String _newSessionId() =>
    '${_studentId ?? 'anon'}_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';

  void _enterOrbMode() {
    setState(() { _orbMode = true; _voiceMode = true; _orbTranscript = ''; });
    Future.delayed(const Duration(milliseconds: 400), _startVoiceInput);
  }

  void _exitOrbMode() {
    _stopSpeech();
    setState(() { _orbMode = false; _voiceMode = false; _isListening = false; _orbTranscript = ''; });
  }

  @override
  void didUpdateWidget(AITutorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubject != widget.selectedSubject) {
      if (!_tutorMode) {
        setState(() {
          _currentSubject = widget.selectedSubject;
          _tutorMode = false; _currentTopic = null;
          _messages.clear(); _suggestedResponses = [];
          _animSteps = []; _animAltSteps = [];
          _showAnim = false; _lastAnimCode = null;
          _activeQuestion = null;
          _voiceMode = false; _isListening = false;
          _workspaceExpanded = false;
        });
        _stopSpeech();
        _loadTopics();
        _loadSuggestions();
      } else {
        // Subject changed while session is active â€” update label only, don't reset
        setState(() => _currentSubject = widget.selectedSubject);
      }
    }
    if (widget.preRead && widget.initialTopic != null &&
        (oldWidget.initialTopic != widget.initialTopic || !oldWidget.preRead)) {
      setState(() { _currentSubject = widget.selectedSubject; });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && widget.initialTopic != null) {
          _startTutorSession(widget.initialTopic!, preRead: true);
        }
      });
    }
    // New lesson context arrived (student tapped Tanya Nova from a different lesson)
    if (widget.lessonContext != null && widget.lessonContext != oldWidget.lessonContext) {
      setState(() { _currentSubject = widget.selectedSubject; });
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && widget.lessonContext != null) _enterLessonMode(widget.lessonContext!);
      });
    }
  }

  Future<void> _loadTopics() async {
    try {
      final r = await http.get(Uri.parse('$kApiUrl/api/tutor/topics?subject=${Uri.encodeComponent(_currentSubject)}'));
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        List data;
        if (body is List) {
          data = body;
        } else if (body is Map && body['topics'] is List) {
          data = body['topics'] as List;
        } else {
          // fallback: load from lessons endpoint
          final r2 = await http.get(Uri.parse('$kApiUrl/api/lessons?subject=${Uri.encodeComponent(_currentSubject)}&status=published&limit=50'));
          data = r2.statusCode == 200 ? jsonDecode(r2.body) as List : [];
        }
        if (mounted) setState(() => _topics = data.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
  }

  Future<void> _loadLanguage() async {
    // Always BM by default â€” language is now subject-locked or per-request
    if (mounted) setState(() => _language = 'bm');
  }

  bool get _forceEnglish => ['English', 'English Literature', 'Geography'].contains(_currentSubject);
  bool get _isEnglishUI => _forceEnglish || _useEnglish;
  bool get _isBm => !_isEnglishUI;
  bool get _showLanguageToggle => !['Bahasa Malaysia', 'Sejarah'].contains(_currentSubject);
  String _t(String bm, String en) => _isEnglishUI ? en : bm;

  void _toggleEnglishRequest() {
    setState(() => _useEnglish = !_useEnglish);
  }

  void _loadSuggestions() {
    if (!mounted) return;
    setState(() => _suggestions = [
      'Terangkan topik $_currentSubject yang paling penting',
      'Bagi contoh soalan SPM untuk $_currentSubject',
      'Topik mana yang perlu saya belajar dulu?',
      'Bantu saya faham konsep asas',
      'Apakah kesilapan lazim yang pelajar buat?',
    ]);
  }

  // â”€â”€ Animation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _fetchAnimation(String code) async {
    if (code == _lastAnimCode) return;
    try {
      final r = await http.get(Uri.parse('$kApiUrl/api/animations/${Uri.encodeComponent(code)}'));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final steps = (data['steps'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        final alt = (data['altSteps'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        if (mounted && steps.isNotEmpty) {
          setState(() {
            _animSteps    = steps;
            _animAltSteps = alt;
            _showAnim     = true;
            _studentConfused = false;
            _lastAnimCode = code;
          });
        }
      }
    } catch (_) {}
  }

  // Fetch pre-built topic animation from engine (Claude-generated, stored in Supabase)
  Future<void> _fetchTopicAnimation(String subject, String topic) async {
    try {
      final url = '$kApiUrl/api/topic-animations?subject=${Uri.encodeComponent(subject)}&topic=${Uri.encodeComponent(topic)}';
      final r = await http.get(Uri.parse(url));
      if (r.statusCode == 200 && mounted) {
        final data = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
        if ((data['steps'] as List?)?.isNotEmpty == true) {
          setState(() {
            _topicAnimation = data;
            _showTopicAnim = true;
          });
        }
      }
    } catch (_) {}
  }

  bool _isConfused(String msg) {
    final l = msg.toLowerCase();
    const en = ["don't understand", "dont understand", "confused", "not sure",
      "doesn't make sense", "doesnt make sense", "what do you mean",
      "i'm lost", "im lost", "lost", "another way", "explain again",
      "don't get it", "dont get it", "no idea", "huh?"];
    const ms = ['tak faham', 'tidak faham', 'keliru', 'apa maksud',
      'cara lain', 'susah', 'faham tak', 'tolong terangkan'];
    return en.any((k) => l.contains(k)) || ms.any((k) => l.contains(k));
  }

  // â”€â”€ Voice: speech-to-text â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _startVoiceInput() {
    if (_isListening || _loading) return;
    setState(() => _isListening = true);
    final lang = _forceEnglish ? 'en-US' : 'ms-MY';
    try {
      js.context.callMethod('startSpeechRecognition', [
        lang,
        (String result) {
          if (!mounted) return;
          setState(() { _isListening = false; _orbTranscript = result.trim(); });
          if (result.trim().isNotEmpty) _ask(result.trim());
        },
        (String error) {
          if (mounted) setState(() { _isListening = false; _orbTranscript = ''; });
          // In orb mode, retry listening after a short pause if not loading
          if (_orbMode && mounted && !_loading) {
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted && _orbMode && !_loading && !_isListening) _startVoiceInput();
            });
          }
        },
      ]);
    } catch (_) {
      if (mounted) setState(() => _isListening = false);
    }
  }

  // â”€â”€ Voice: text-to-speech (auto-play tutor response) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String _cleanForTts(String text) {
    return text
        // Remove markdown formatting
        .replaceAll(RegExp(r'\*\*?|__?|~~|`+'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r'#+\s*'), '')
        // Remove bullet/list markers
        .replaceAll(RegExp(r'^\s*[-â€¢*]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
        // Remove ellipsis and dashes used as separators
        .replaceAll('...', '.')
        .replaceAll('---', '.')
        .replaceAll('--', ',')
        // Remove underscore separators
        .replaceAll(RegExp(r'_{2,}'), '')
        // Remove any emoji or non-BMP characters
        .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{2600}-\u{27BF}]', unicode: true), '')
        // Remove garbled encoding artifacts
        .replaceAll(RegExp(r'[Ã°Å¸â‚¬-Å¸Å¡Ã¿ÃžÃ½]'), '')
        // Collapse multiple spaces/newlines
        .replaceAll(RegExp(r'\n+'), '. ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
  }

  void _speakText(String text) {
    final clean = _cleanForTts(text);
    if (clean.isEmpty) return;
    _stopSpeech();
    _speakWithOpenAI(clean);
  }

  void _stopSpeech() {
    try {
      _audioElement?.pause();
      _audioElement = null;
      // Revoke blob URL to prevent memory leak across multiple TTS calls
      if (_audioBlobUrl != null) {
        html.Url.revokeObjectUrl(_audioBlobUrl!);
        _audioBlobUrl = null;
      }
    } catch (_) {}
    if (mounted) setState(() => _ttsPlaying = false);
  }

  Future<void> _speakWithOpenAI(String text) async {
    final gen = ++_ttsGeneration;
    try {
      if (mounted) setState(() => _ttsPlaying = true);

      final ttsLang = _forceEnglish ? 'en' : _language;
      final response = await http.post(
        Uri.parse('$kApiUrl/api/tts'),
        headers: {
          'Content-Type': 'application/json',
          if (_authToken != null) 'Authorization': 'Bearer $_authToken',
        },
        body: jsonEncode({'text': text, 'voice': 'nova', 'language': ttsLang}),
      ).timeout(const Duration(seconds: 20));

      // Discard response if a newer TTS call was made while this one was in-flight
      if (gen != _ttsGeneration) return;

      if (response.statusCode == 200 && mounted) {
        final blob = html.Blob([response.bodyBytes], 'audio/mpeg');
        final url  = html.Url.createObjectUrlFromBlob(blob);
        _audioBlobUrl = url;
        final audio = html.AudioElement(url)
          ..preload = 'auto';
        _audioElement = audio;

        audio.onEnded.listen((_) {
          html.Url.revokeObjectUrl(url);
          _audioBlobUrl = null;
          if (mounted) setState(() => _ttsPlaying = false);
          _onTtsDone();
        });

        audio.onError.listen((_) {
          html.Url.revokeObjectUrl(url);
          _audioBlobUrl = null;
          if (mounted) setState(() => _ttsPlaying = false);
          _onTtsDone();
        });

        await audio.play();
      } else {
        if (mounted) setState(() => _ttsPlaying = false);
        _onTtsDone();
      }
    } catch (_) {
      if (gen != _ttsGeneration) return;
      if (mounted) setState(() => _ttsPlaying = false);
      _onTtsDone();
    }
  }

  void _onTtsDone() {
    if (!_voiceMode || !mounted) return;
    if (!_loading) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _voiceMode && !_loading && !_isListening) _startVoiceInput();
      });
    } else {
      // Loading is still in progress â€” poll until it finishes, then re-arm mic
      Future.delayed(const Duration(milliseconds: 600), _onTtsDone);
    }
  }

  // Quick voice input for home screen (fills text field, no orb overlay)
  void _startQuickVoice() {
    if (_isListening || _loading) return;
    setState(() { _isListening = true; _ctrl.clear(); });
    final lang = _forceEnglish ? 'en-US' : 'ms-MY';
    try {
      js.context.callMethod('startSpeechRecognition', [
        lang,
        (String result) {
          if (!mounted) return;
          setState(() { _isListening = false; });
          if (result.trim().isNotEmpty) {
            _ctrl.text = result.trim();
            setState(() {}); // shows send button
          }
        },
        (String error) {
          if (mounted) setState(() => _isListening = false);
        },
      ]);
    } catch (_) {
      if (mounted) setState(() => _isListening = false);
    }
  }

  void _toggleVoiceMode() {
    setState(() => _voiceMode = !_voiceMode);
    if (_voiceMode) {
      // Kick off the first listen
      Future.delayed(const Duration(milliseconds: 300), _startVoiceInput);
    } else {
      _stopSpeech();
      setState(() => _isListening = false);
    }
  }

  // â”€â”€ Workspace submit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _onWorkspaceSubmit(WorkspaceResult result) async {
    setState(() => _workspaceSubmitting = true);
    try {
      if (result.mode == 'typed' && (result.typedAnswer ?? '').isNotEmpty) {
        await _tutorSession(result.typedAnswer!);
      } else if (result.mode == 'drawn') {
        await _tutorSession('[Student submitted handwritten working â€” please continue teaching.]');
      }
    } finally {
      if (mounted) setState(() => _workspaceSubmitting = false);
    }
  }

  // Convert the inline visual object from the tutor API into TopicAnimationPlayer format
  Map<String, dynamic>? _convertVisualToAnimation(Map<String, dynamic> visual) {
    final type = visual['type'] as String?;
    if (type == 'math_working') {
      final mw = visual['math_working'];
      if (mw is! Map) return null;
      final rawSteps = (mw as Map)['steps'];
      if (rawSteps is! List || (rawSteps as List).isEmpty) return null;
      final steps = (rawSteps as List).map((s) {
        final step = Map<String, dynamic>.from(s as Map);
        return <String, dynamic>{
          'label': step['label'] ?? '',
          'math': step['math'] ?? step['latex'] ?? '',
          'text': '',
          'tip': '',
        };
      }).toList();
      return {
        'animation_type': 'working',
        'title': (mw as Map)['title'] ?? _currentTopic ?? '',
        'color_scheme': 'purple',
        'steps': steps,
      };
    }
    if (type == 'graph') {
      final g = visual['graph'] as Map<String, dynamic>?;
      if (g == null) return null;
      return {
        'animation_type': 'graph',
        'title': g['title'] ?? _currentTopic ?? '',
        'color_scheme': 'blue',
        'graph_config': {
          'equation_type': g['equation_type'] ?? 'quadratic',
          'a': g['a'] ?? 1, 'b': g['b'] ?? 0, 'c': g['c'] ?? 0, 'd': g['d'] ?? 0,
          'x_min': g['x_min'] ?? -5, 'x_max': g['x_max'] ?? 5,
          'y_min': g['y_min'] ?? -5, 'y_max': g['y_max'] ?? 5,
          'x_label': g['x_label'] ?? 'x', 'y_label': g['y_label'] ?? 'y',
          'key_points': g['key_points'] ?? [],
        },
        'steps': [<String, dynamic>{
          'label': g['title'] ?? 'Graf',
          'math': '',
          'text': '',
          'tip': '',
        }],
      };
    }
    return null;
  }

  // â”€â”€ Session â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _startTutorSession(String topic, {bool preRead = false}) async {
    if (_sessionStarting || topic.isEmpty) return;
    _sessionStarting = true;
    _sessionId = _newSessionId();
    _novaSessionStart = DateTime.now();
    context.findAncestorStateOfType<MainShellState>()?.setTutorMode(true);
    setState(() {
      _tutorMode = true; _currentTopic = topic;
      _phase = 'intro'; _segment = 0;
      _messages.clear(); _suggestedResponses = [];
      _loading = true;
      _animSteps = []; _animAltSteps = [];
      _showAnim = false; _lastAnimCode = null; _studentConfused = false;
      _topicAnimation = null; _showTopicAnim = true;
    });
    _preGenerateQuiz(topic);
    _fetchTopicAnimation(_currentSubject, topic);
    await _tutorSession('start', preRead: preRead);
    // Drain pending intent (e.g. "Jelaskan topik ini") as the student's first
    // real message so Nova continues into the requested intent instead of
    // stopping after intro.
    final pending = _pendingIntent;
    _pendingIntent = null;
    if (pending != null && pending.trim().isNotEmpty) {
      await _tutorSession(pending);
    }
    _sessionStarting = false;
  }

  void _preGenerateQuiz(String topic) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final studentId = prefs.getString('student_id') ?? '';
      if (studentId.isEmpty) return;
      await http.post(
        Uri.parse('$kApiUrl/api/session-quiz/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'student_id': studentId, 'subject': _currentSubject, 'topic': topic,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  Future<void> _loadTopicIllustrations() async {
    if (_currentTopic == null) return;
    try {
      final r = await http.get(Uri.parse(
        '$kApiUrl/api/tutor/illustrations?subject=${Uri.encodeComponent(_currentSubject)}&topic=${Uri.encodeComponent(_currentTopic!)}'));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final list = (data['illustrations'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (mounted) setState(() { _topicIllustrations = list; _illustrationIndex = 0; });
      }
    } catch (_) {}
  }

  void _showIllustrationItem(int index) {
    final ill = _topicIllustrations[index];
    setState(() {
      _illustrationIndex = index;
      _currentSvgCode = ill['svg_code'] as String? ?? '';
      _illustrationTitle = ill['title'] as String? ?? 'Ilustrasi';
      _showIllustrationOverlay = true;
    });
  }

  void _maybeShowIllustrations(String userMessage) {
    const triggers = [
      'show me', 'tunjukkan', 'diagram', 'gambar',
      'ilustrasi', 'example', 'contoh', 'show',
    ];
    final lower = userMessage.toLowerCase();
    if (triggers.any((t) => lower.contains(t))) {
      if (_topicIllustrations.isNotEmpty) {
        _showIllustrationItem(0);
      } else {
        _loadTopicIllustrations().then((_) {
          if (_topicIllustrations.isNotEmpty) _showIllustrationItem(0);
        });
      }
    }
  }

  Future<void> _tutorSession(String message, {bool preRead = false}) async {
    if (!_tutorMode || _currentTopic == null) return;
    setState(() => _loading = true);

    if (message != 'start' && _isConfused(message)) {
      setState(() => _studentConfused = true);
    }
    final history = _messages.take(10)
      .map((m) => {'role': m['role'] == 'user' ? 'user' : 'assistant', 'content': m['text'] ?? ''})
      .toList();
    if (message != 'start') {
      setState(() => _messages.add({'role': 'user', 'text': message}));
      _scrollToBottom();
    }
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/tutor/session'),
        headers: {
          'Content-Type': 'application/json',
          if (_authToken != null) 'Authorization': 'Bearer $_authToken',
        },
        body: jsonEncode({
          'subject': _currentSubject, 'topic': _currentTopic,
          'message': message, 'history': history,
          'phase': _phase, 'segment': _segment,
          'language': _forceEnglish ? 'en' : (_useEnglish ? 'en' : 'bm'),
          'activeQuestion': _activeQuestion,
          'studentConfused': _studentConfused,
          'personality': 'balanced',
          'character': _characterId,
          'student_id': _studentId,
          'student_name': _studentName ?? '',
          'session_id': _sessionId,
          if (preRead && message == 'start') 'pre_read': true,
          if (widget.lessonContext != null) 'lessonId': widget.lessonContext!['lesson_id'],
          if (widget.lessonContext != null) 'lessonContext': widget.lessonContext,
          'nova_source': widget.lessonContext != null ? 'nova_from_lesson' : 'nova_direct',
        }),
      );
      final data = jsonDecode(r.body);
      final newCode = data['standardCode'] as String?;

      setState(() {
        _phase    = data['phase']   ?? _phase;
        _segment  = data['segment'] ?? _segment;
        _studentConfused = false;
        _currentStandardCode = newCode;
        _currentStandardDesc = data['standardDesc']      as String?;
        _standardsProgress   = data['standardsProgress'] as String?;
        if (data['topicSwitchSuggested'] == true) {
          _pendingSwitchTopic = data['suggestedTopic'] as String?;
        }
        _suggestedResponses = (data['suggestedResponses'] as List?)?.cast<String>() ?? [];
        // New server contract: hasActiveQuestion is a bool. Old contract
        // shipped activeQuestion as a Map?. Treat either as a truthiness flag.
        final hasQ = data['hasActiveQuestion'] == true || data['activeQuestion'] != null;
        _activeQuestion = hasQ ? <String, dynamic>{} : null;
        _messages.add({
          'role': 'ai', 'text': data['reply'] ?? '',
          'source': data['source'], 'isCheckIn': data['isCheckIn'] ?? false,
        });
        _loading = false;
      });

      // Use inline visual from response first; fall back to pre-stored standard animation
      final visualData = data['visual'];
      if (visualData is Map) {
        final converted = _convertVisualToAnimation(Map<String, dynamic>.from(visualData as Map));
        if (converted != null && mounted) {
          setState(() { _topicAnimation = converted; _showTopicAnim = true; });
        }
      } else if (newCode != null && newCode != _lastAnimCode) {
        _fetchAnimation(newCode);
      }
      // Auto-speak tutor reply in voice mode
      if (_voiceMode) {
        final reply = data['reply'] as String? ?? '';
        if (reply.isNotEmpty) _speakText(reply);
      }
    } catch (_) {
      setState(() {
        _messages.add({'role': 'ai', 'text': 'Ralat sambungan. Cuba lagi.'});
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  Future<void> _ask(String question) async {
    if (question.trim().isEmpty) return;
    if (_pendingSwitchTopic != null && question.toLowerCase().startsWith('yes')) {
      final t = _pendingSwitchTopic!;
      _pendingSwitchTopic = null;
      _ctrl.clear();
      await _startTutorSession(t);
      return;
    }
    if (_tutorMode && _currentTopic != null) {
      _ctrl.clear();
      await _tutorSession(question);
      _maybeShowIllustrations(question);
      return;
    }
    setState(() { _messages.add({'role': 'user', 'text': question}); _loading = true; });
    _ctrl.clear();
    _scrollToBottom();
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/tutor/session'),
        headers: {
          'Content-Type': 'application/json',
          if (_authToken != null) 'Authorization': 'Bearer $_authToken',
        },
        body: jsonEncode({
          'question': question,
          'subject': _currentSubject,
          'language': _forceEnglish ? 'en' : 'bm',
        }),
      );
      final data = jsonDecode(r.body);
      final related = data['related_questions'];
      setState(() {
        _messages.add({
          'role': 'ai',
          'text': data['reply'] ?? data['answer'] ?? 'Maaf, saya tidak dapat menjawab soalan itu.',
          'example': data['example'], 'source': data['source'],
          'related_questions': (related is List) ? related.cast<String>() : <String>[],
          'wrong_subject_note': data['wrong_subject_note'],
        });
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _messages.add({'role': 'ai', 'text': 'Ralat sambungan. Cuba lagi.'});
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      }
    });
  }

  void _showFeedback(Map<String, dynamic> msg) {
    final logId = msg['log_id'] as String?;
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Maklum balas respons ini', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Bantu kami penambahbaikan Learnova', style: TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _feedbackChip('Mengelirukan', 'confusing', logId),
            _feedbackChip('Jawapan salah', 'wrong', logId),
            _feedbackChip('Terlalu panjang', 'too_long', logId),
            _feedbackChip('Terlalu pendek', 'too_short', logId),
            _feedbackChip('Masalah bahasa', 'language_issue', logId),
            _feedbackChip('Sangat membantu', 'helpful', logId, positive: true),
          ]),
        ]),
      ),
    );
  }

  Widget _feedbackChip(String label, String type, String? logId, {bool positive = false}) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _sendFeedback(logId, type);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: positive ? kGreen.withOpacity(0.1) : kSurface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: positive ? kGreen.withOpacity(0.4) : kBorder)),
        child: Text(label, style: TextStyle(
          color: positive ? kGreen : kText, fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Future<void> _sendFeedback(String? logId, String feedbackType) async {
    try {
      await http.post(
        Uri.parse('$kApiUrl/api/admin/response-feedback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'conversation_log_id': logId,
          'student_id': _studentId,
          'session_id': _sessionId,
          'feedback_type': feedbackType,
        }),
      );
    } catch (_) {}
  }

  void _showFullDisclaimer() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Tentang Learnova AI', style: TextStyle(color: kText, fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(LearnovaDisclaimers.fullNotice, style: const TextStyle(color: kText, fontSize: 13, height: 1.6)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Faham', style: TextStyle(color: kPrimary)))],
      ),
    );
  }

  void _showPrivacyNotice() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Privasi & Data', style: TextStyle(color: kText, fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(LearnovaDisclaimers.privacyNotice, style: const TextStyle(color: kText, fontSize: 13, height: 1.6)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Faham', style: TextStyle(color: kPrimary)))],
      ),
    );
  }

  Map<String, dynamic> get _subjectInfo =>
    kSubjects.firstWhere((s) => s['name'] == _currentSubject, orElse: () => kSubjects.first);

  bool get _animVisible => _tutorMode && _showAnim && _animSteps.isNotEmpty;

  // MCQ tappable buttons disabled â€” students must type their answers
  bool get _isMcqPhase => false;

  void _exitTutorMode() {
    context.findAncestorStateOfType<MainShellState>()?.setTutorMode(false);
    setState(() {
      _tutorMode = false; _currentTopic = null;
      _messages.clear(); _suggestedResponses = [];
      _animSteps = []; _animAltSteps = [];
      _showAnim = false; _lastAnimCode = null;
      _topicAnimation = null; _showTopicAnim = true;
      _workspaceExpanded = false;
    });
  }

  // â”€â”€ Layout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildIdleScreen() {
    const chips = ['Jelaskan topik ini', 'Bagi saya kuiz', 'Selesaikan soalan', 'Pelan belajar'];
    return Scaffold(
      backgroundColor: const Color(0xFF07080C),
      body: Column(children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1018),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF181C28)),
                ),
                child: const Center(child: Icon(Icons.auto_awesome_rounded,
                  color: Color(0xFF4A7AFA), size: 16)),
              ),
              const SizedBox(width: 10),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nova', style: TextStyle(
                  color: Color(0xFFE8ECF8), fontSize: 14, fontWeight: FontWeight.w500)),
                Text('Pembantu belajar kamu', style: TextStyle(
                  color: Color(0xFF4A5070), fontSize: 10)),
              ]),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.5,
            children: chips.map((label) => GestureDetector(
              onTap: () {
                // Intent chips need a topic. If we already have one (mid-session
                // chip use), let _ask route to the existing _tutorMode branch.
                // Otherwise stash the intent and force the topic picker — the
                // intent gets sent as the first message once _startTutorSession
                // completes (see _startTutorSession).
                if (_currentTopic != null) {
                  _ask(label);
                } else {
                  setState(() => _pendingIntent = label);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1018),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF181C28)),
                ),
                alignment: Alignment.center,
                child: Text(label,
                  style: const TextStyle(color: Color(0xFF6A7A9A), fontSize: 12),
                  textAlign: TextAlign.center),
              ),
            )).toList(),
          ),
        ),
        const Spacer(),
        Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          child: _buildChatInput(),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjectColor = Color(_subjectInfo['color'] as int);
    final isWide = MediaQuery.of(context).size.width > 700;

    // Skip the idle screen when an intent is pending — fall through to the
    // tutor-mode chrome so _buildTopicSelector renders and the student can pick.
    if (_messages.isEmpty && !_tutorMode && widget.lessonContext == null && _pendingIntent == null) {
      return _buildIdleScreen();
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: _tutorMode
        ? AppBar(
            leading: BackButton(onPressed: () {
              if (widget.lessonContext != null && Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                _exitTutorMode();
              }
            }),
            title: Text(
              _currentTopic == null ? '' :
                (_currentTopic!.length > 20 ? '${_currentTopic!.substring(0, 20)}â€¦' : _currentTopic!),
              style: const TextStyle(fontSize: 14)),
            actions: [
              if (_showLanguageToggle && !_forceEnglish)
                GestureDetector(
                  onTap: _toggleEnglishRequest,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: _useEnglish ? kPrimary.withOpacity(0.15) : kSurface2,
                      border: Border.all(color: _useEnglish ? kPrimary.withOpacity(0.5) : kBorder),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_useEnglish ? 'EN' : 'BM',
                      style: TextStyle(
                        color: _useEnglish ? kPrimary : kMuted,
                        fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          )
        : AppBar(
            title: Text('AI Tutor - $_currentSubject',
              style: const TextStyle(fontSize: 15)),
            actions: [
              if (_showLanguageToggle && !_forceEnglish)
                GestureDetector(
                  onTap: _toggleEnglishRequest,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: _useEnglish ? kPrimary.withOpacity(0.15) : kSurface2,
                      border: Border.all(color: _useEnglish ? kPrimary.withOpacity(0.5) : kBorder),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_useEnglish ? 'EN' : 'BM',
                      style: TextStyle(
                        color: _useEnglish ? kPrimary : kMuted,
                        fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              if (_topicAnimation != null)
                IconButton(
                  icon: Icon(
                    _showTopicAnim ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                    color: _showTopicAnim ? kYellow : kMuted, size: 20),
                  tooltip: _showTopicAnim ? 'Sembunyi animasi' : 'Tunjuk animasi',
                  onPressed: () => setState(() => _showTopicAnim = !_showTopicAnim),
                ),
              if (_animSteps.isNotEmpty && _topicAnimation == null)
                IconButton(
                  icon: Icon(
                    _showAnim ? Icons.picture_in_picture_alt_rounded : Icons.auto_graph_rounded,
                    color: _showAnim ? kPrimary : kMuted, size: 20),
                  tooltip: _showAnim ? 'Hide visual' : 'Show visual',
                  onPressed: () => setState(() => _showAnim = !_showAnim),
                ),
              if (_currentTopic != null)
                IconButton(
                  icon: const Icon(Icons.menu_book_rounded, size: 19),
                  color: kMuted,
                  tooltip: 'Baca semula bahan',
                  onPressed: () {
                    final lessonData = _topics.firstWhere(
                      (t) => (t['topic'] ?? t['title'] ?? '') == _currentTopic,
                      orElse: () => <String, dynamic>{},
                    );
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => TopicIntroScreen(
                        subject: _currentSubject,
                        topic: _currentTopic!,
                        lessonData: lessonData,
                      ),
                    ));
                  },
                ),
              if (_messages.isNotEmpty)
                IconButton(icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => setState(() => _messages.clear())),
            ],
          ),
      body: isWide ? _buildWideLayout(subjectColor) : _buildMobileLayout(),
    );
  }

  // â”€â”€ Desktop layout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildWideLayout(Color subjectColor) {
    return Row(children: [
      // Left panel
      if (_tutorMode)
        SizedBox(
          width: 360,
          child: Column(children: [
            // Topic animation (pre-built from engine) â€” top priority
            if (_topicAnimation != null && _showTopicAnim)
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: TopicAnimationPlayer(
                    animation: _topicAnimation!,
                    onDismiss: () => setState(() => _showTopicAnim = false),
                  ),
                ),
              )
            else if (_animVisible)
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: AnimationPanel(
                    steps:      _animSteps,
                    altSteps:   _animAltSteps,
                    isConfused: _studentConfused,
                    onDismiss:  () => setState(() => _showAnim = false),
                  ),
                ),
              ),
            // Workspace (always visible in tutor mode)
            SizedBox(
              height: (_topicAnimation != null && _showTopicAnim) || _animVisible ? 260 : 420,
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, ((_topicAnimation != null && _showTopicAnim) || _animVisible) ? 0 : 10, 10, 10),
                child: WorkspacePanel(
                  subject:      _currentSubject,
                  question:     _currentStandardDesc ?? '',
                  embedded:     true,
                  isSubmitting: _workspaceSubmitting,
                  onSubmit:     _onWorkspaceSubmit,
                ),
              ),
            ),
          ]),
        )
      else
        SizedBox(
          width: 280,
          child: Container(
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(right: BorderSide(color: kBorder))),
            child: _buildTopicSidebar(),
          ),
        ),

      // Chat column
      Expanded(child: Column(children: [
        if (!_tutorMode) _buildSubjectBar(),
        if (_tutorMode) _buildDisclaimerBanner(),
        if (_tutorMode && widget.lessonContext != null) _buildLessonBanner(),
        if (_messages.isEmpty && !_tutorMode) _buildWelcome(subjectColor),
        Expanded(child: _buildMessageList()),
        if (_isMcqPhase) _buildMcqButtons(),
        if (!_tutorMode && _messages.isEmpty) _buildSuggestions(),
        _buildChatInput(),
      ])),
    ]);
  }

  // â”€â”€ Mobile layout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildMobileLayout() {
    return Stack(children: [
      // â”€â”€ Main column â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      Column(children: [
        if (!_tutorMode) _buildSubjectBar(),
        if (_tutorMode) _buildDisclaimerBanner(),
        if (_tutorMode && widget.lessonContext != null) _buildLessonBanner(),
        // Topic animation (pre-built, from engine) â€” shown first when in tutor mode
        if (_tutorMode && _topicAnimation != null && _showTopicAnim)
          SizedBox(
            height: 310,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: TopicAnimationPlayer(
                animation: _topicAnimation!,
                onDismiss: () => setState(() => _showTopicAnim = false),
              ),
            ),
          )
        // Fallback: standards-based SVG animation
        else if (_animVisible)
          SizedBox(
            height: 230,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: AnimationPanel(
                steps:      _animSteps,
                altSteps:   _animAltSteps,
                isConfused: _studentConfused,
                onDismiss:  () => setState(() => _showAnim = false),
              ),
            ),
          ),
        Expanded(child: _messages.isEmpty && !_tutorMode
          ? _buildTopicSelector()
          : _buildMessageList()),
        if (_isMcqPhase) _buildMcqButtons(),
        _buildChatInput(),
      ]),
      // â”€â”€ Fullscreen orb overlay â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // â”€â”€ Illustration fullscreen overlay â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      if (_showIllustrationOverlay) _buildIllustrationOverlay(),
    ]);
  }

  // â”€â”€ Collapsible workspace panel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildWorkspacePanel() {
    // Auto-expand when a question is active
    final bool hasQuestion = _activeQuestion != null;
    final bool expanded = _workspaceExpanded || hasQuestion;
    final double expandedHeight = 320.0;
    final double collapsedHeight = 44.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      height: expanded ? expandedHeight : collapsedHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08), width: 1)),
      ),
      child: Column(
        children: [
          // â”€â”€ Header strip â€” always visible â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          GestureDetector(
            onTap: () => setState(() => _workspaceExpanded = !_workspaceExpanded),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: collapsedHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.edit_note_rounded, color: Color(0xFF6366F1), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Kerja Saya',
                      style: TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasQuestion) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Soalan aktif',
                          style: TextStyle(color: Color(0xFF6366F1), fontSize: 10)),
                      ),
                    ],
                    const Spacer(),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 260),
                      child: const Icon(Icons.keyboard_arrow_up_rounded,
                        color: Color(0xFF94A3B8), size: 22),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // â”€â”€ Workspace body â€” visible when expanded â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (expanded)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: WorkspacePanel(
                  subject:      _currentSubject,
                  question:     _currentStandardDesc ?? '',
                  embedded:     true,
                  isSubmitting: _workspaceSubmitting,
                  onSubmit:     _onWorkspaceSubmit,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // â”€â”€ A/B/C/D grid â€” only shown when phase=quiz_answer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildMcqButtons() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_t('Pilih jawapan kamu:', 'Choose your answer:'),
          style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: ['A', 'B', 'C', 'D'].map((letter) =>
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () {
                  _tutorSession(letter);
                  setState(() => _suggestedResponses = []);
                },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.08),
                    border: Border.all(color: kPrimary.withOpacity(0.5), width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(letter,
                    style: const TextStyle(
                      color: kPrimary, fontSize: 18,
                      fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ).toList()),
      ]),
    );
  }

  Widget _buildDisclaimerBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFFF59E0B).withOpacity(0.08),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 13, color: Colors.amber[700]),
        const SizedBox(width: 6),
        const Expanded(child: Text(
          'Platform AI â€” semak dengan guru untuk pengesahan',
          style: TextStyle(fontSize: 11, color: Color(0xFF92400E)))),
        GestureDetector(
          onTap: _showFullDisclaimer,
          child: Text('Info', style: TextStyle(
            fontSize: 11, color: Colors.amber[800],
            decoration: TextDecoration.underline,
            decorationColor: Colors.amber[800]))),
      ]),
    );
  }

  Widget _buildLessonBanner() {
    final lc = widget.lessonContext!;
    final lessonTitle = lc['lesson_title'] as String? ?? lc['topic'] as String? ?? 'Pelajaran';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: kPrimary.withOpacity(0.1),
      child: Row(children: [
        const Text('ðŸ“š', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(lessonTitle,
            style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
        ),
        GestureDetector(
          onTap: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              _exitTutorMode();
            }
          },
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_back_ios_rounded, color: kPrimary, size: 12),
            SizedBox(width: 2),
            Text('Pelajaran', style: TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSubjectBar() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SubjectSelector(
        selected: _currentSubject,
        onChanged: (s) {
          setState(() {
            _currentSubject = s;
            // Reset topic so the next idle-screen chip tap routes through the
            // picker for the new subject (the old subject's topic isn't valid
            // here anyway).
            _currentTopic = null;
          });
          _loadTopics(); _loadSuggestions();
          context.findAncestorStateOfType<MainShellState>()?.setSubject(s);
        },
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _messages.length) return _typingIndicator();
        return _buildMessage(_messages[i]);
      },
    );
  }

  Widget _buildWelcome(Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(children: [
        Container(width: 64, height: 64,
          decoration: BoxDecoration(color: color.withOpacity(0.15),
            border: Border.all(color: color.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(16)),
          child: const Center(child: Icon(Icons.auto_awesome_rounded, size: 30, color: Colors.white))),
        const SizedBox(height: 16),
        const Text('Hei! Kamu nak belajar apa hari ni?',
          style: TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center),
        const SizedBox(height: 6),
        const Text('Atau ada topik dari pelajaran tadi yang kamu nak faham lebih dalam?',
          style: TextStyle(color: kMuted, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        const Text('Pilih topik di bawah atau taip soalan terus.',
          style: TextStyle(color: kBorder, fontSize: 12), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildTopicSidebar() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.all(16),
        child: Text('Topik', style: TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w700))),
      Expanded(child: ListView(children: _topics.map((t) {
        final topic = t['topic'] as String? ?? t['title'] as String? ?? '';
        return ListTile(
          leading: const Icon(Icons.play_circle_outline, color: kPrimary, size: 20),
          title: Text(topic, style: const TextStyle(color: kText, fontSize: 13)),
          subtitle: const Text('Pelajaran berpandu', style: TextStyle(color: kMuted, fontSize: 11)),
          onTap: () => _startTutorSession(topic),
          dense: true,
        );
      }).toList())),
    ]);
  }

  Widget _buildTopicSelector() {
    final subjectInfo = kSubjects.firstWhere(
      (s) => s['name'] == _currentSubject,
      orElse: () => kSubjects.first,
    );
    final subjectColor = Color(subjectInfo['color'] as int);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Row(children: const [
          Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 20),
          SizedBox(width: 8),
          Text('Pilih topik untuk mula belajar',
            style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        const Text('Pilih topik di bawah untuk pelajaran berpandu bersama Nova',
          style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 12),
        if (_topics.isNotEmpty) ...[
          ..._topics.map((t) {
            final topicName = (t['topic'] as String? ?? t['title'] as String? ?? '').trim();
            if (topicName.isEmpty) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () => _startTutorSession(topicName),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: subjectColor.withOpacity(0.06),
                  border: Border.all(color: subjectColor.withOpacity(0.25)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.play_circle_outline_rounded, color: subjectColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(topicName, style: const TextStyle(color: kText, fontSize: 13))),
                  Icon(Icons.arrow_forward_ios_rounded, color: subjectColor.withOpacity(0.5), size: 12),
                ]),
              ),
            );
          }),
          const SizedBox(height: 8),
          const Divider(color: kBorder, height: 1),
          const SizedBox(height: 12),
        ],
        const Text('Tanya soalan', style: TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        ..._suggestions.take(3).map((q) => GestureDetector(
          onTap: () => _ask(q),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.arrow_forward_ios_rounded, color: kPrimary, size: 10),
              const SizedBox(width: 10),
              Expanded(child: Text(q, style: const TextStyle(color: kText, fontSize: 13))),
            ]),
          ),
        )),
      ]),
    );
  }

  Widget _buildSuggestions() {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => GestureDetector(
          onTap: () => _ask(_suggestions[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: kSurface2, border: Border.all(color: kBorder),
              borderRadius: BorderRadius.circular(20)),
            child: Text(_suggestions[i], style: const TextStyle(color: kText, fontSize: 12))),
        ),
      ),
    );
  }

  void _showCharacterPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Pilih Watak Tutor', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Cara Nova mengajar kamu', style: TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 16),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _kCharacters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx2, i) {
                  final c = _kCharacters[i];
                  final selected = _characterId == c['id'];
                  final color = Color(c['color'] as int);
                  return GestureDetector(
                    onTap: () {
                      _saveCharacter(c['id'] as String);
                      setSheet(() {});
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 84,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      decoration: BoxDecoration(
                        color: selected ? color.withOpacity(0.15) : kSurface2,
                        border: Border.all(color: selected ? color : kBorder, width: selected ? 2 : 1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(c['emoji'] as String, style: const TextStyle(fontSize: 26)),
                        const SizedBox(height: 4),
                        Text(c['name'] as String,
                          style: TextStyle(color: selected ? color : kText, fontSize: 10, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(c['tagline'] as String,
                          style: const TextStyle(color: kMuted, fontSize: 9),
                          textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _buildCharacterSelector() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Pilih Tutor', style: TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Cara Nova mengajar kamu', style: TextStyle(color: kMuted, fontSize: 11)),
      const SizedBox(height: 10),
      SizedBox(
        height: 100,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: _kCharacters.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (ctx, i) {
            final c = _kCharacters[i];
            final selected = _characterId == c['id'];
            final color = Color(c['color'] as int);
            return GestureDetector(
              onTap: () => _saveCharacter(c['id'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 80,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  color: selected ? color.withOpacity(0.15) : kSurface2,
                  border: Border.all(color: selected ? color : kBorder, width: selected ? 2 : 1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(c['emoji'] as String, style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 4),
                  Text(c['name'] as String,
                    style: TextStyle(color: selected ? color : kText, fontSize: 10, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(c['tagline'] as String,
                    style: const TextStyle(color: kMuted, fontSize: 9),
                    textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // Normalise escape sequences in plain teaching text.
  // Server now returns plain reply text (no JSON envelope), so the JSON
  // unwrap logic is gone; this only converts literal \n / \t that some
  // upstream paths may still include.
  static String _parseNovaText(dynamic raw) {
    if (raw == null) return '';
    final t = raw is String ? raw : raw.toString();
    return t.replaceAll(r'\n', '\n').replaceAll(r'\t', '\t');
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    // Disclaimer pill
    if (msg['role'] == 'disclaimer') {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(20),
          color: kSurface,
        ),
        child: Text(
          msg['text'] as String? ?? '',
          style: const TextStyle(fontSize: 12, color: kMuted),
          textAlign: TextAlign.center,
        ),
      );
    }

    final isUser = msg['role'] == 'user';
    final text = _parseNovaText(msg['text']);
    final source = msg['source'] as String?;
    String sourceLabel = '';
    if (source == 'lesson_db')   sourceLabel = 'Dari buku teks';
    else if (source == 'faq_cache')  sourceLabel = 'Jawapan segera';
    else if (source == 'quiz_bank')  sourceLabel = 'Bank soalan SPM';
    else if (source == 'claude')     sourceLabel = 'Jana AI';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kPrimary, kPrimary2]),
                borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 10),
          ],
          Flexible(child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isUser && text.length > 50) TtsPlayer(text: text, title: 'Tutor', language: _language),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isUser ? kPrimary : kSurface,
                  border: Border.all(color: isUser ? kPrimary : kBorder),
                  borderRadius: BorderRadius.circular(14)),
                child: !isUser && text.length > 400
                  ? _AutoScrollText(text: text)
                  : MarkdownBody(data: text, styleSheet: MarkdownStyleSheet(
                      p:      const TextStyle(color: kText, fontSize: 14, height: 1.6),
                      h2:     const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700),
                      h3:     const TextStyle(color: kPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                      strong: const TextStyle(color: kText, fontWeight: FontWeight.w700),
                      code:   const TextStyle(color: kGreen, fontSize: 13, fontFamily: 'monospace'),
                    )),
              ),
              if (!isUser && msg['example'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: kGreen.withOpacity(0.1),
                    border: Border.all(color: kGreen.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Contoh:', style: TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(msg['example'].toString(), style: const TextStyle(color: kText, fontSize: 13)),
                  ])),
              ],
              if (!isUser && msg['wrong_subject_note'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: kYellow.withOpacity(0.1),
                    border: Border.all(color: kYellow.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(10)),
                  child: Text(msg['wrong_subject_note'].toString(),
                    style: const TextStyle(color: kYellow, fontSize: 12, fontWeight: FontWeight.w600))),
              ],
              if (!isUser && sourceLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(sourceLabel, style: const TextStyle(color: kMuted, fontSize: 11)),
              ],
              if (!isUser) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _showFeedback(msg),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.thumb_down_outlined, size: 13, color: kMuted.withOpacity(0.5)),
                    const SizedBox(width: 4),
                    Text('Maklum balas', style: TextStyle(color: kMuted.withOpacity(0.5), fontSize: 10)),
                  ]),
                ),
              ],
            ],
          )),
          if (isUser) const SizedBox(width: 10),
        ],
      ),
    );
  }

  bool _isGraphTopic() {
    final t = (_currentTopic ?? '').toLowerCase();
    return t.contains('graph') || t.contains('graf') || t.contains('coordinate')
        || t.contains('koordinat') || t.contains('elevation') || t.contains('sudut')
        || t.contains('angle') || t.contains('trigonometr') || t.contains('sin ')
        || t.contains('cos ') || t.contains('tan ') || t.contains('quadratic')
        || t.contains('kuadratik') || t.contains('linear') || t.contains('garis lurus');
  }

  Widget _buildGraphPlaceholder() {
    final t = (_currentTopic ?? '').toLowerCase();
    final isAnglesTopic = t.contains('elevation') || t.contains('angle') || t.contains('sudut') || t.contains('trigonometr');

    // Static SVG for Angles of Elevation / trigonometry
    const anglesSvg = '''
<svg viewBox="0 0 320 200" xmlns="http://www.w3.org/2000/svg">
  <rect width="320" height="200" fill="#0D1117"/>
  <!-- Ground line -->
  <line x1="20" y1="160" x2="300" y2="160" stroke="#6C5CE7" stroke-width="2"/>
  <!-- Vertical object -->
  <line x1="60" y1="160" x2="60" y2="50" stroke="#00B894" stroke-width="2"/>
  <!-- Line of sight -->
  <line x1="60" y1="160" x2="260" y2="60" stroke="#FDCB6E" stroke-width="2" stroke-dasharray="6,3"/>
  <!-- Right angle box -->
  <rect x="60" y="148" width="12" height="12" fill="none" stroke="#00B894" stroke-width="1.5"/>
  <!-- Angle arc -->
  <path d="M 100 160 A 40 40 0 0 0 78 131" fill="none" stroke="#FDCB6E" stroke-width="1.5"/>
  <!-- Labels -->
  <text x="275" y="155" fill="#6C5CE7" font-size="11" font-family="monospace">x</text>
  <text x="45" y="46" fill="#00B894" font-size="11" font-family="monospace">h</text>
  <text x="105" y="148" fill="#FDCB6E" font-size="11" font-family="monospace">Î¸</text>
  <text x="130" y="100" fill="#FDCB6E" font-size="10" font-family="monospace">Garis Nampak</text>
  <text x="90" y="180" fill="#DFE6E9" font-size="10" font-family="monospace">Jarak mendatar</text>
  <text x="4" y="108" fill="#DFE6E9" font-size="10" font-family="monospace" transform="rotate(-90 20 110)">Tinggi</text>
</svg>''';

    // Generic coordinate graph SVG
    const graphSvg = '''
<svg viewBox="0 0 320 200" xmlns="http://www.w3.org/2000/svg">
  <rect width="320" height="200" fill="#0D1117"/>
  <!-- Grid lines -->
  <g stroke="#1E2432" stroke-width="1">
    <line x1="40" y1="20" x2="40" y2="180"/>
    <line x1="80" y1="20" x2="80" y2="180"/>
    <line x1="120" y1="20" x2="120" y2="180"/>
    <line x1="160" y1="20" x2="160" y2="180"/>
    <line x1="200" y1="20" x2="200" y2="180"/>
    <line x1="240" y1="20" x2="240" y2="180"/>
    <line x1="280" y1="20" x2="280" y2="180"/>
    <line x1="20" y1="40" x2="300" y2="40"/>
    <line x1="20" y1="80" x2="300" y2="80"/>
    <line x1="20" y1="120" x2="300" y2="120"/>
    <line x1="20" y1="160" x2="300" y2="160"/>
  </g>
  <!-- Axes -->
  <line x1="160" y1="10" x2="160" y2="190" stroke="#6C5CE7" stroke-width="2"/>
  <line x1="10" y1="100" x2="310" y2="100" stroke="#6C5CE7" stroke-width="2"/>
  <!-- Arrow heads -->
  <polygon points="160,8 155,18 165,18" fill="#6C5CE7"/>
  <polygon points="312,100 302,95 302,105" fill="#6C5CE7"/>
  <!-- Sample curve (parabola) -->
  <path d="M 60 170 Q 160 20 260 170" fill="none" stroke="#FDCB6E" stroke-width="2"/>
  <!-- Labels -->
  <text x="165" y="15" fill="#6C5CE7" font-size="11" font-family="monospace">y</text>
  <text x="298" y="96" fill="#6C5CE7" font-size="11" font-family="monospace">x</text>
  <text x="130" y="115" fill="#DFE6E9" font-size="9" font-family="monospace">O(0,0)</text>
</svg>''';

    final svgData = isAnglesTopic ? anglesSvg : graphSvg;
    final label = isAnglesTopic ? 'Diagram Sudut Dongakan' : 'Graf â€” $_currentTopic';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6C5CE7).withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            const Icon(Icons.bar_chart_rounded, size: 14, color: Color(0xFF6C5CE7)),
            const SizedBox(width: 6),
            Expanded(child: Text(label,
              style: const TextStyle(color: Color(0xFF6C5CE7), fontSize: 11, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis)),
            GestureDetector(
              onTap: () {
                if (_topicIllustrations.isNotEmpty) _showIllustrationItem(0);
              },
              child: const Text('Lihat â†’', style: TextStyle(color: Color(0xFF6C5CE7), fontSize: 10)),
            ),
          ]),
        ),
        SizedBox(
          height: 160,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SvgPicture.string(svgData, fit: BoxFit.contain),
          ),
        ),
      ]),
    );
  }

  Widget _typingIndicator() {
    return Row(children: [
      Container(width: 32, height: 32,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kPrimary, kPrimary2]),
          borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16)),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(14)),
        child: const Row(children: [
          SizedBox(width: 6, height: 6,
            child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
          SizedBox(width: 8),
          Text('Sedang fikir...', style: TextStyle(color: kMuted, fontSize: 13)),
        ])),
    ]);
  }

  String get _hintText {
    if (_forceEnglish) return 'Type your answer or question...';
    if (widget.lessonContext != null && _tutorMode) {
      final title = widget.lessonContext!['lesson_title'] as String? ?? '';
      return title.isNotEmpty ? 'Tanya pasal $title...' : 'Tanya pasal pelajaran ini...';
    }
    return 'Taip jawapan atau soalan kamu...';
  }

  // â”€â”€ ChatGPT-style input bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildChatInput() {
    final hasText = _ctrl.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: kSurface,
        border: const Border(top: BorderSide(color: kBorder)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // â”€â”€ Plus button: workspace + tools â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        GestureDetector(
          onTap: _showWorkspaceSheet,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: kSurface2,
              shape: BoxShape.circle,
              border: Border.all(color: kBorder),
            ),
            child: const Icon(Icons.add_rounded, color: kMuted, size: 22),
          ),
        ),
        const SizedBox(width: 8),
        // â”€â”€ Text field â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Expanded(
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: kText, fontSize: 14),
            maxLines: 4,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: _hintText,
              hintStyle: const TextStyle(color: kMuted, fontSize: 13),
              filled: true,
              fillColor: kSurface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: kPrimary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        // â”€â”€ Send (when typing) or Mic/Orb (when empty) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: hasText
            ? GestureDetector(
                key: const ValueKey('send'),
                onTap: () { final t = _ctrl.text.trim(); _ctrl.clear(); setState(() {}); if (t.isNotEmpty) _ask(t); },
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPrimary, kPrimary2]),
                    shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                ),
              )
            : GestureDetector(
                key: const ValueKey('mic'),
                onTap: _tutorMode ? _startVoiceInput : _startQuickVoice,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: kPrimary.withOpacity(0.5)),
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _isListening ? Colors.redAccent : kPrimary,
                    size: 20),
                ),
              ),
        ),
      ]),
    );
  }

  // â”€â”€ Workspace bottom sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showWorkspaceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1D27),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            // Handle bar
            Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: kBorder, borderRadius: BorderRadius.circular(2)),
            )),
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
              child: Row(children: [
                const Icon(Icons.edit_note_rounded, color: kPrimary, size: 20),
                const SizedBox(width: 8),
                const Text('Kerja Saya', style: TextStyle(
                  color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                // Language toggle in sheet header (only for dual-language subjects)
                if (_showLanguageToggle && !_forceEnglish)
                  GestureDetector(
                    onTap: _toggleEnglishRequest,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _useEnglish ? kPrimary.withOpacity(0.15) : kSurface2,
                        border: Border.all(color: _useEnglish ? kPrimary.withOpacity(0.5) : kBorder),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_useEnglish ? 'EN' : 'BM',
                        style: TextStyle(
                          color: _useEnglish ? kPrimary : kMuted,
                          fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),
            // Workspace panel fills the rest
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: WorkspacePanel(
                  subject:      _currentSubject,
                  question:     _currentStandardDesc ?? '',
                  embedded:     true,
                  isSubmitting: _workspaceSubmitting,
                  onSubmit: (result) {
                    Navigator.pop(context); // close sheet
                    _onWorkspaceSubmit(result);
                  },
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // â”€â”€ Illustration fullscreen overlay â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildIllustrationOverlay() {
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Container(
          color: const Color(0xF5060D1A),
          child: SafeArea(
            child: Column(children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
                child: Row(children: [
                  Expanded(child: Text(_illustrationTitle,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
                  GestureDetector(
                    onTap: () => setState(() => _showIllustrationOverlay = false),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20)),
                  ),
                ]),
              ),
              // Tab row when multiple illustrations
              if (_topicIllustrations.length > 1) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _topicIllustrations.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final selected = i == _illustrationIndex;
                      return GestureDetector(
                        onTap: () => _showIllustrationItem(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF6C5CE7) : Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(_topicIllustrations[i]['title'] as String? ?? 'Ilustrasi ${i + 1}',
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white54,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      );
                    },
                  ),
                ),
              ],
              // SVG content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _currentSvgCode.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          color: Colors.white.withOpacity(0.04),
                          padding: const EdgeInsets.all(12),
                          child: SvgPicture.string(
                            _currentSvgCode,
                            fit: BoxFit.contain,
                            colorFilter: null,
                          ),
                        ),
                      )
                    : const Center(child: Text('Tiada ilustrasi tersedia.',
                        style: TextStyle(color: Colors.white38, fontSize: 14))),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // â”€â”€ Fullscreen orb overlay â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildOrbOverlay() {
    final isActive = _isListening || _ttsPlaying || _loading;
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Container(
          color: const Color(0xF0060D1A),
          child: SafeArea(
            child: Column(children: [
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GestureDetector(
                    onTap: _exitOrbMode,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // Status label
              Text(
                _loading ? 'Sedang fikir...' : _ttsPlaying ? 'Bercakap...' : _isListening ? 'Mendengar...' : 'Ketik orb untuk bercakap',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 40),
              // Animated orb
              AnimatedBuilder(
                animation: _orbPulse,
                builder: (_, __) {
                  final scale = isActive ? 0.92 + 0.08 * _orbPulse.value : 0.97 + 0.03 * _orbPulse.value;
                  final glowColor = _isListening
                      ? const Color(0xFF10B981)
                      : _ttsPlaying
                          ? const Color(0xFF6366F1)
                          : _loading
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF1E88E5);
                  return GestureDetector(
                    onTap: () {
                      if (_isListening) return;
                      if (_ttsPlaying) { _stopSpeech(); return; }
                      if (!_loading) _startVoiceInput();
                    },
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 160, height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            glowColor.withOpacity(0.9),
                            const Color(0xFF7C3AED).withOpacity(0.5),
                            Colors.transparent,
                          ]),
                          boxShadow: [BoxShadow(
                            color: glowColor.withOpacity(isActive ? 0.6 : 0.2),
                            blurRadius: isActive ? 80 : 30,
                            spreadRadius: isActive ? 20 : 5,
                          )],
                        ),
                        child: Center(child: _loading
                          ? const SizedBox(width: 36, height: 36,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70))
                          : _isListening
                            ? _buildSoundWave()
                            : _ttsPlaying
                              ? _buildSpeakingWave()
                              : const Icon(Icons.mic_rounded, color: Colors.white, size: 52)),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              // Transcript â€” what the student said
              if (_orbTranscript.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text('"$_orbTranscript"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 15, fontStyle: FontStyle.italic)),
                ),
              const Spacer(),
              // Last AI message preview
              if (_messages.isNotEmpty) ...[
                Builder(builder: (_) {
                  final lastAi = _messages.lastWhere(
                    (m) => m['role'] == 'ai',
                    orElse: () => {'text': ''},
                  );
                  final preview = (lastAi['text'] as String? ?? '')
                      .replaceAll(RegExp(r'\*+'), '')
                      .split('\n').first.trim();
                  if (preview.isEmpty) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Text(
                      preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6), fontSize: 13),
                    ),
                  );
                }),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildSoundWave() {
    return AnimatedBuilder(
      animation: _orbPulse,
      builder: (_, __) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final h = [16.0, 28.0, 40.0, 28.0, 16.0][i] *
              (0.4 + 0.6 * ((_orbPulse.value + i * 0.2) % 1.0));
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 5, height: h,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3)),
          );
        }),
      ),
    );
  }

  Widget _buildSpeakingWave() {
    return AnimatedBuilder(
      animation: _orbPulse,
      builder: (_, __) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final h = [12.0, 24.0, 36.0, 24.0, 12.0][i] *
              (0.5 + 0.5 * ((_orbPulse.value + i * 0.15) % 1.0));
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 5, height: h,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(3)),
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _orbPulse.dispose();
    _stopSpeech();
    _recordNovaSession();
    super.dispose();
  }

  void _recordNovaSession() {
    final sid = _studentId;
    final start = _novaSessionStart;
    final msgCount = _messages.where((m) => m['role'] == 'user').length;
    if (sid == null || start == null || msgCount == 0) return;
    final durationMinutes = DateTime.now().difference(start).inMinutes;
    http.post(
      Uri.parse('$kApiUrl/api/nova/session-end'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'studentId': sid,
        'subject': _currentSubject,
        'topic': _currentTopic ?? '',
        'messagesCount': msgCount,
        'durationMinutes': durationMinutes,
      }),
    ).ignore();
  }
}

// Auto-scrolling text widget for long AI messages
class _AutoScrollText extends StatefulWidget {
  final String text;
  const _AutoScrollText({required this.text});
  @override
  State<_AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<_AutoScrollText> {
  final _sc = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1200), _startScroll);
    });
  }

  void _startScroll() {
    if (!mounted || !_sc.hasClients || _scrolled) return;
    final max = _sc.position.maxScrollExtent;
    if (max <= 4) return;
    _scrolled = true;
    final words = widget.text.split(RegExp(r'\s+')).length;
    final ms = (words / 150 * 60000).clamp(3000.0, 45000.0).round();
    _sc.animateTo(max, duration: Duration(milliseconds: ms), curve: Curves.linear);
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        controller: _sc,
        child: MarkdownBody(data: widget.text, styleSheet: MarkdownStyleSheet(
          p:      const TextStyle(color: kText, fontSize: 14, height: 1.6),
          h2:     const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700),
          h3:     const TextStyle(color: kPrimary, fontSize: 14, fontWeight: FontWeight.w700),
          strong: const TextStyle(color: kText, fontWeight: FontWeight.w700),
          code:   const TextStyle(color: kGreen, fontSize: 13, fontFamily: 'monospace'),
        )),
      ),
    );
  }
}
