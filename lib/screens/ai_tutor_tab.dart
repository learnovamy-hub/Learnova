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
  const AITutorTab({super.key, required this.selectedSubject, this.initialTopic, this.preRead = false});
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
  String? _currentStandardCode;
  String? _currentStandardDesc;
  String? _standardsProgress;
  String _language = 'bm';
  bool _useEnglish = false;

  // ── Animation state ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _animSteps    = [];
  List<Map<String, dynamic>> _animAltSteps = [];
  bool _showAnim        = false;
  bool _studentConfused = false;
  String? _lastAnimCode;

  // ── Topic animation (pre-built, stored in engine, served on demand) ──
  Map<String, dynamic>? _topicAnimation;
  bool _showTopicAnim = true;

  // ── Voice state ─────────────────────────────────────────────────────
  bool _isListening = false;
  bool _voiceMode   = false; // when true: auto-TTS + auto-mic loop

  // ── Quiz state ──────────────────────────────────────────────────────
  Map<String, dynamic>? _activeQuestion;

  // ── Workspace state ─────────────────────────────────────────────────
  bool _workspaceSubmitting = false;
  bool _workspaceExpanded   = false;

  // ── TTS state ────────────────────────────────────────────────────────
  String? _authToken;
  html.AudioElement? _audioElement;
  String? _audioBlobUrl;    // tracked separately so _stopSpeech can revoke it
  bool _ttsPlaying = false;
  int _ttsGeneration = 0;   // incremented each call; stale HTTP responses are discarded

  // ── Illustration overlay state ────────────────────────────────────────
  bool _showIllustrationOverlay = false;
  String _illustrationTitle = '';
  String _currentSvgCode = '';
  List<Map<String, dynamic>> _topicIllustrations = [];
  int _illustrationIndex = 0;

  // ── Character ────────────────────────────────────────────────────────
  static const List<Map<String, dynamic>> _kCharacters = [
    {'id': 'nova',   'name': 'Nova',        'emoji': '⭐', 'tagline': 'Mesra & sabar',    'color': 0xFF6C5CE7},
    {'id': 'sarjan', 'name': 'Sarjan Rex',  'emoji': '🎖', 'tagline': 'Tegas & disiplin', 'color': 0xFFDC2626},
    {'id': 'sensei', 'name': 'Sensei',      'emoji': '⛩', 'tagline': 'Anime & dramatik', 'color': 0xFFDB2777},
    {'id': 'bestie', 'name': 'Bestie Alia', 'emoji': '🤙', 'tagline': 'Gen Z & santai',   'color': 0xFF059669},
    {'id': 'chaos',  'name': 'Chaos-chan',  'emoji': '🔥', 'tagline': 'Wild & energetik', 'color': 0xFFF59E0B},
  ];
  String _characterId = 'nova';

  // ── Session tracking ─────────────────────────────────────────────────
  String? _sessionId;
  String? _studentId;

  // ── Orb overlay state ────────────────────────────────────────────────
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
    // Load token first — then start session if navigated from TopicIntroScreen
    _loadToken().then((_) {
      if (mounted && widget.preRead && widget.initialTopic != null && widget.initialTopic!.isNotEmpty) {
        _startTutorSession(widget.initialTopic!, preRead: true);
      }
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
        // Subject changed while session is active — update label only, don't reset
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
    // Always BM by default — language is now subject-locked or per-request
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

  // ── Animation ────────────────────────────────────────────────────────
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

  // ── Voice: speech-to-text ────────────────────────────────────────────
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

  // ── Voice: text-to-speech (auto-play tutor response) ─────────────────
  String _cleanForTts(String text) {
    return text
        // Remove markdown formatting
        .replaceAll(RegExp(r'\*\*?|__?|~~|`+'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r'#+\s*'), '')
        // Remove bullet/list markers
        .replaceAll(RegExp(r'^\s*[-•*]\s+', multiLine: true), '')
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
        .replaceAll(RegExp(r'[ðŸ€-ŸšÿÞý]'), '')
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
      // Loading is still in progress — poll until it finishes, then re-arm mic
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

  // ── Workspace submit ─────────────────────────────────────────────────
  Future<void> _onWorkspaceSubmit(WorkspaceResult result) async {
    setState(() => _workspaceSubmitting = true);
    try {
      if (result.mode == 'typed' && (result.typedAnswer ?? '').isNotEmpty) {
        await _tutorSession(result.typedAnswer!);
      } else if (result.mode == 'drawn') {
        await _tutorSession('[Student submitted handwritten working — please continue teaching.]');
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

  // ── Session ──────────────────────────────────────────────────────────
  Future<void> _startTutorSession(String topic, {bool preRead = false}) async {
    if (_sessionStarting || topic.isEmpty) return;
    _sessionStarting = true;
    _sessionId = _newSessionId();
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
    _loadTopicIllustrations();
    await _tutorSession('start', preRead: preRead);
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
        _activeQuestion = data['activeQuestion'] != null
            ? Map<String, dynamic>.from(data['activeQuestion'] as Map)
            : null;
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

  // MCQ tappable buttons disabled — students must type their answers
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

  // ── Layout ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final subjectColor = Color(_subjectInfo['color'] as int);
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: kBg,
      appBar: _tutorMode
        ? AppBar(
            leading: BackButton(onPressed: _exitTutorMode),
            title: Text(
              _currentTopic == null ? '' :
                (_currentTopic!.length > 20 ? '${_currentTopic!.substring(0, 20)}…' : _currentTopic!),
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

  // ── Desktop layout ────────────────────────────────────────────────────
  Widget _buildWideLayout(Color subjectColor) {
    return Row(children: [
      // Left panel
      if (_tutorMode)
        SizedBox(
          width: 360,
          child: Column(children: [
            // Topic animation (pre-built from engine) — top priority
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
        if (_messages.isEmpty && !_tutorMode) _buildWelcome(subjectColor),
        Expanded(child: _buildMessageList()),
        if (_isMcqPhase) _buildMcqButtons(),
        if (!_tutorMode && _messages.isEmpty) _buildSuggestions(),
        _buildChatInput(),
      ])),
    ]);
  }

  // ── Mobile layout ─────────────────────────────────────────────────────
  Widget _buildMobileLayout() {
    return Stack(children: [
      // ── Main column ─────────────────────────────────────────────────
      Column(children: [
        if (!_tutorMode) _buildSubjectBar(),
        if (_tutorMode) _buildDisclaimerBanner(),
        // Topic animation (pre-built, from engine) — shown first when in tutor mode
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
      // ── Fullscreen orb overlay ───────────────────────────────────────
      if (_orbMode) _buildOrbOverlay(),
      // ── Illustration fullscreen overlay ──────────────────────────────
      if (_showIllustrationOverlay) _buildIllustrationOverlay(),
    ]);
  }

  // ── Collapsible workspace panel ───────────────────────────────────────
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
          // ── Header strip — always visible ────────────────────────────
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
          // ── Workspace body — visible when expanded ───────────────────
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

  // ── A/B/C/D grid — only shown when phase=quiz_answer ─────────────────
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
          'Platform AI — semak dengan guru untuk pengesahan',
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

  Widget _buildSubjectBar() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SubjectSelector(
        selected: _currentSubject,
        onChanged: (s) {
          setState(() => _currentSubject = s);
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
        const SizedBox(height: 12),
        Text('$_currentSubject AI Tutor',
          style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Pilih topik untuk pelajaran berpandu, atau tanya sebarang soalan di bawah',
          style: TextStyle(color: kMuted, fontSize: 13), textAlign: TextAlign.center),
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
        const Text('Ketik mana-mana topik untuk pelajaran berpandu, atau tanya soalan di bawah',
          style: TextStyle(color: kMuted, fontSize: 12)),
        ..._suggestions.take(4).map((q) => GestureDetector(
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
    final text   = msg['text'] as String? ?? '';
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
              if (!isUser && _topicIllustrations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(spacing: 6, children: List.generate(_topicIllustrations.length, (i) {
                    final ill = _topicIllustrations[i];
                    return GestureDetector(
                      onTap: () => _showIllustrationItem(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C5CE7).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF6C5CE7).withOpacity(0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.image_outlined, size: 13, color: Color(0xFF6C5CE7)),
                          const SizedBox(width: 4),
                          Text(ill['title'] as String? ?? 'Ilustrasi',
                            style: const TextStyle(color: Color(0xFF6C5CE7), fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    );
                  })),
                ),
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
    return 'Taip jawapan atau soalan kau...';
  }

  // ── ChatGPT-style input bar ───────────────────────────────────────────
  Widget _buildChatInput() {
    final hasText = _ctrl.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: kSurface,
        border: const Border(top: BorderSide(color: kBorder)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // ── Plus button: workspace + tools ──────────────────────────
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
        // ── Text field ───────────────────────────────────────────────
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
        // ── Send (when typing) or Mic/Orb (when empty) ───────────────
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

  // ── Workspace bottom sheet ────────────────────────────────────────────
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

  // ── Illustration fullscreen overlay ──────────────────────────────────
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

  // ── Fullscreen orb overlay ────────────────────────────────────────────
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
              // Transcript — what the student said
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
    super.dispose();
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
