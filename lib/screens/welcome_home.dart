// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:js' as js;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'main_shell.dart';

enum _Step { greeting, askMode, askSubject, askForm, done }

class WelcomeHome extends StatefulWidget {
  final String studentName;
  final String studentId;
  const WelcomeHome({Key? key, required this.studentName, required this.studentId}) : super(key: key);
  @override
  State<WelcomeHome> createState() => _WelcomeHomeState();
}

class _WelcomeHomeState extends State<WelcomeHome> with TickerProviderStateMixin {
  late AnimationController _orbController;
  late AnimationController _cardsController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;

  bool _speaking = false;
  bool _listening = false;
  bool _cardsVisible = false;
  bool _navigated = false;
  _Step _step = _Step.greeting;
  String? _selectedMode;
  String? _selectedSubject;
  String? _savedForm;
  String _transcript = '';
  String _statusText = '';
  String? _token;
  html.AudioElement? _audioElement;

  static const _forms = ['Form 1', 'Form 2', 'Form 3', 'Form 4', 'Form 5'];

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName => widget.studentName.split(' ').first;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _cardsController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeController.forward();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    // Check local cache first
    _savedForm = prefs.getString('student_form_${widget.studentId}');
    // If not in local cache, WAIT for server before starting the orb flow
    // This is the key fix — previously this was fire-and-forget so _savedForm
    // was always null when _greet() ran, causing the form question every login.
    if (_savedForm == null && widget.studentId.isNotEmpty && _token != null) {
      await _fetchFormFromServer(prefs);
    }
    await Future.delayed(const Duration(milliseconds: 400));
    _greet();
  }

  Future<void> _fetchFormFromServer(SharedPreferences prefs) async {
    try {
      final resp = await http.get(
        Uri.parse('$kApiUrl/api/auth/student-profile'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final form = data['student']?['form_level'];
        if (form != null && form is String && form.isNotEmpty) {
          await prefs.setString('student_form_${widget.studentId}', form);
          if (mounted) setState(() => _savedForm = form);
        }
      }
    } catch (_) { /* non-fatal */ }
  }

  void _greet() {
    final rng = Random();
    final h = DateTime.now().hour;
    final timeGreets = h < 12
        ? ['Rise and shine, $_firstName!', 'Morning, $_firstName!', 'Early bird today, $_firstName!']
        : h < 17
            ? ['Hey $_firstName, good afternoon!', 'Afternoon, $_firstName!', '$_greeting, $_firstName!']
            : ['Evening, $_firstName!', 'Hey $_firstName, burning the midnight oil?', 'Late session today, $_firstName!'];
    final opener = timeGreets[rng.nextInt(timeGreets.length)];
    final follow = [
      'What are we smashing today — lesson, revision, or quiz?',
      'Lesson, revision, or quiz? Your call.',
      'So what is the plan — new lesson, revision, or a quick quiz?',
      'Ready to go? Pick your poison — lesson, revision, or quiz!',
      'What are we working on today?',
      'What is on the agenda — lesson, revision, or quiz?',
      'Let us get into it. Lesson, revision, or quiz today?',
      'Good to see you. Are we doing a lesson, revision, or quiz?',
      'Shall we pick up where you left off, or start something new?',
    ];
    _speak('$opener ${follow[rng.nextInt(follow.length)]}', onDone: () {
      if (mounted) setState(() {
        _step = _Step.askMode;
        _statusText = 'Tap the orb to speak, or choose below';
      });
      _showCards();
    });
  }

  void _onOrbTap() {
    if (_speaking) return;
    if (_listening) {
      if (mounted) setState(() { _listening = false; _statusText = 'Tap orb to speak, or choose below'; });
      return;
    }
    if (_step == _Step.greeting) return;
    _startListening();
  }

  void _startListening() {
    if (_speaking) return;
    if (mounted) setState(() { _listening = true; _transcript = ''; _statusText = 'Listening...'; });
    try {
      js.context.callMethod('startSpeechRecognition', [
        'en-US',
        js.allowInterop((String result) {
          if (!mounted) return;
          setState(() { _transcript = result; _listening = false; });
          _handleSpeechResult(result);
        }),
        js.allowInterop((String error) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _statusText = error == 'not-supported'
                ? 'Voice not supported — tap a card below'
                : error == 'no-speech'
                  ? 'No speech detected — tap to try again'
                  : error == 'end'
                    ? 'Tap orb to speak, or choose below'
                    : 'Mic error — tap a card below';
          });
        }),
      ]);
    } catch (e) {
      if (mounted) setState(() { _listening = false; _statusText = 'Voice unavailable — tap a card below'; });
    }
  }

  void _handleSpeechResult(String t) {
    switch (_step) {
      case _Step.askMode:    _parseModeFromSpeech(t);    break;
      case _Step.askSubject: _parseSubjectFromSpeech(t); break;
      case _Step.askForm:    _parseFormFromSpeech(t);    break;
      default: break;
    }
  }

  void _parseModeFromSpeech(String t) {
    String? mode;
    if (t.contains('lesson') || t.contains('learn') || t.contains('new')) mode = 'New Lesson';
    else if (t.contains('revis') || t.contains('review'))                  mode = 'Revision';
    else if (t.contains('quiz') || t.contains('test'))                     mode = 'Quiz';
    if (mode != null) {
      _onModeSelected(mode);
    } else {
      final rng = Random();
      final retries = [
        'Hmm, I did not quite catch that. Lesson, revision, or quiz?',
        'Sorry, say that again? Lesson, revision, or quiz?',
        'Did not get that one! Which is it — lesson, revision, or quiz?',
      ];
      _speak(retries[rng.nextInt(retries.length)], onDone: () {
        if (mounted) setState(() => _statusText = 'Tap orb to speak, or choose below');
        _showCards();
      });
    }
  }

  void _parseSubjectFromSpeech(String t) {
    const aliases = {
      'Mathematics':     ['math', 'maths', 'mathematics'],
      'Add Maths':       ['add math', 'additional math', 'add maths'],
      'Physics':         ['physics'],
      'Biology':         ['biology', 'bio'],
      'Chemistry':       ['chemistry', 'chem'],
      'Geography':       ['geography', 'geo'],
      'Sejarah':         ['sejarah', 'history', 'sej'],
      'Bahasa Malaysia': ['bahasa', 'malay'],
      'English':         ['english', 'eng'],
    };
    String? matched;
    for (final entry in aliases.entries) {
      if (entry.value.any((a) => t.contains(a))) { matched = entry.key; break; }
    }
    if (matched != null) {
      _onSubjectSelected(matched);
    } else {
      final rng = Random();
      final retries = [
        'Hmm, which subject? Try maths, physics, biology, or english.',
        'Did not catch the subject! Say something like maths, chemistry, or english.',
        'Say that again? Which subject — maths, physics, bio?',
      ];
      _speak(retries[rng.nextInt(retries.length)], onDone: () {
        if (mounted) setState(() => _statusText = 'Tap orb to speak, or choose below');
        _showCards();
      });
    }
  }

  void _parseFormFromSpeech(String t) {
    // Also pick up subject if mentioned in same utterance
    if (_selectedSubject == null) {
      const aliases = {
        'Mathematics':     ['math', 'maths', 'mathematics'],
        'Add Maths':       ['add math', 'additional math', 'add maths'],
        'Physics':         ['physics'],
        'Biology':         ['biology', 'bio'],
        'Chemistry':       ['chemistry', 'chem'],
        'Geography':       ['geography', 'geo'],
        'Sejarah':         ['sejarah', 'history', 'sej'],
        'Bahasa Malaysia': ['bahasa', 'malay'],
        'English':         ['english', 'eng'],
      };
      for (final entry in aliases.entries) {
        if (entry.value.any((a) => t.contains(a))) { _selectedSubject = entry.key; break; }
      }
    }
    const formMap = {
      'Form 1': ['form 1', 'form one', 'one', '1'],
      'Form 2': ['form 2', 'form two', 'two', '2'],
      'Form 3': ['form 3', 'form three', 'three', '3'],
      'Form 4': ['form 4', 'form four', 'four', '4'],
      'Form 5': ['form 5', 'form five', 'five', '5'],
    };
    String? matched;
    for (final entry in formMap.entries) {
      if (entry.value.any((a) => t.contains(a))) { matched = entry.key; break; }
    }
    if (matched != null) {
      _onFormSelected(matched);
    } else {
      final rng = Random();
      final retries = [
        'Which form are you in? Say form one, two, three, four, or five.',
        'Did not catch that! Which form — one through five?',
        'Just tell me your form! One, two, three, four, or five?',
      ];
      _speak(retries[rng.nextInt(retries.length)], onDone: () {
        if (mounted) setState(() => _statusText = 'Tap orb to speak, or choose below');
        _showCards();
      });
    }
  }

  void _onModeSelected(String mode) {
    if (_speaking) return;
    setState(() { _selectedMode = mode; _cardsVisible = false; _listening = false; _transcript = ''; });
    _cardsController.reset();
    final rng = Random();
    final lessonReplies = [
      'Love it! Which subject are we diving into?',
      'New lesson — nice! Which subject?',
      'Let us learn something new! Which subject are we doing?',
      'Fresh start! Which subject today?',
      'Alright, new lesson mode! Pick your subject.',
    ];
    final revisionReplies = [
      'Smart move! Which subject are we revising?',
      'Revision it is! Which subject needs some love?',
      'Good thinking. Which subject are we going over?',
      'Let us brush it up! Which subject?',
      'Revision mode on! Which subject are we tackling?',
    ];
    final quizReplies = [
      'Ooh, quiz time! Which subject do you want to be tested on?',
      'Let us see what you have got! Pick a subject.',
      'Challenge accepted! Which subject?',
      'Quiz mode — love the confidence! Which subject?',
      'Time to test yourself! Which subject?',
    ];
    final reply = mode == 'New Lesson'
        ? lessonReplies[rng.nextInt(lessonReplies.length)]
        : mode == 'Revision'
            ? revisionReplies[rng.nextInt(revisionReplies.length)]
            : quizReplies[rng.nextInt(quizReplies.length)];
    _speak(reply, onDone: () {
      if (mounted) setState(() { _step = _Step.askSubject; _statusText = 'Tap the orb to speak, or choose below'; });
      _showCards();
    });
  }

  void _onSubjectSelected(String subject) {
    if (_speaking) return;
    setState(() { _selectedSubject = subject; _cardsVisible = false; _listening = false; _transcript = ''; });
    _cardsController.reset();
    final rng = Random();
    if (_savedForm != null) {
      final goReplies = [
        '$subject it is! Let us go!',
        'Alright, $subject — let us get into it!',
        'Nice, $subject! Opening it up now.',
        '$subject? Great pick. Let us do this!',
        'On it! Loading $subject for you now.',
      ];
      _speak(goReplies[rng.nextInt(goReplies.length)], onDone: _navigate);
      Future.delayed(const Duration(seconds: 4), () { if (mounted) _navigate(); });
    } else {
      final formReplies = [
        'Nice choice! Quick one — which form are you in?',
        '$subject, nice! Just tell me — Form 1 to 5?',
        'Good pick! Which form are you in so I can tailor it right?',
        'Solid choice! Which form — one through five?',
        'Love it! Just need to know your form level first.',
      ];
      _speak(formReplies[rng.nextInt(formReplies.length)], onDone: () {
        if (mounted) setState(() { _step = _Step.askForm; _statusText = 'Tap the orb to speak, or choose below'; });
        _showCards();
      });
    }
  }

  Future<void> _onFormSelected(String form) async {
    if (_speaking) return;
    setState(() { _listening = false; _cardsVisible = false; _transcript = ''; });
    final prefs = await SharedPreferences.getInstance();
    // Save locally
    await prefs.setString('student_form_${widget.studentId}', form);
    setState(() => _savedForm = form);
    // Save to server (so it persists across devices/browsers)
    _saveFormToServer(form);
    final rng = Random();
    final formDoneReplies = [
      'Got it, $form! Let us go!',
      '$form — perfect, I have got you. Let us do this!',
      'Nice, $form! All set. Let us go!',
      'Okay $form student! Time to get to work.',
      'Noted! $form it is. Opening things up now.',
    ];
    _speak(formDoneReplies[rng.nextInt(formDoneReplies.length)], onDone: _navigate);
    Future.delayed(const Duration(seconds: 4), () { if (mounted) _navigate(); });
  }

  Future<void> _saveFormToServer(String form) async {
    if (_token == null) return;
    try {
      await http.patch(
        Uri.parse('$kApiUrl/api/auth/update-form'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'form_level': form}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) { /* non-fatal */ }
  }

  void _navigate() {
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => MainShell(
        initialSubject: _selectedSubject ?? 'Mathematics',
        initialTabIndex: _selectedMode == 'Quiz' ? 2 : 1,
      ),
    ));
  }

  void _speak(String text, {VoidCallback? onDone}) {
    bool fired = false;
    if (mounted) setState(() { _listening = false; _transcript = ''; _statusText = ''; _speaking = true; });
    void fireOnce() {
      if (fired) return;
      fired = true;
      if (mounted) setState(() => _speaking = false);
      onDone?.call();
    }
    // Safety timeout — always fires onDone even if TTS hangs
    final ms = (text.split(' ').length * 600 + 2500).clamp(3000, 14000);
    Future.delayed(Duration(milliseconds: ms), fireOnce);

    // Try OpenAI TTS first
    _speakWithOpenAI(text, fireOnce);
  }

  void _speakWithOpenAI(String text, VoidCallback fireOnce) async {
    if (_token == null) { _fallbackBrowserTts(text, fireOnce); return; }
    try {
      // Stop any previous audio
      try { _audioElement?.pause(); _audioElement = null; } catch (_) {}
      try { js.context['speechSynthesis']?.callMethod('cancel', []); } catch (_) {}

      final resp = await http.post(
        Uri.parse('$kApiUrl/api/tts'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'text': text, 'voice': 'nova'}),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200 && mounted) {
        final blob = html.Blob([resp.bodyBytes], 'audio/mpeg');
        final url  = html.Url.createObjectUrlFromBlob(blob);
        final audio = html.AudioElement(url);
        _audioElement = audio;
        audio.onEnded.listen((_) { html.Url.revokeObjectUrl(url); fireOnce(); });
        audio.onError.listen((_) { html.Url.revokeObjectUrl(url); _fallbackBrowserTts(text, fireOnce); });
        await audio.play();
      } else {
        _fallbackBrowserTts(text, fireOnce);
      }
    } catch (_) {
      _fallbackBrowserTts(text, fireOnce);
    }
  }

  void _fallbackBrowserTts(String text, VoidCallback fireOnce) {
    try {
      final synth = js.context['speechSynthesis'];
      if (synth == null) { fireOnce(); return; }
      synth.callMethod('cancel', []);
      final utterance = js.JsObject(js.context['SpeechSynthesisUtterance'], [text]);
      final voices = synth.callMethod('getVoices', []);
      final length = voices['length'] as int;
      for (var i = 0; i < length; i++) {
        final v = voices[i];
        final name = v['name'].toString().toLowerCase();
        if (name.contains('zira') || name.contains('samantha') || name.contains('susan') || name.contains('google uk english female')) {
          utterance['voice'] = v;
          break;
        }
      }
      utterance['rate'] = 1.05;
      utterance['pitch'] = 1.1;
      utterance['onend']   = js.allowInterop((_) { fireOnce(); });
      utterance['onerror'] = js.allowInterop((_) { fireOnce(); });
      synth.callMethod('speak', [utterance]);
    } catch (_) { fireOnce(); }
  }

  void _showCards() {
    if (!mounted) return;
    _cardsController.reset();
    setState(() => _cardsVisible = true);
    _cardsController.forward();
  }

  @override
  void dispose() {
    _orbController.dispose();
    _cardsController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    try { _audioElement?.pause(); _audioElement = null; } catch (_) {}
    try { js.context['speechSynthesis']?.callMethod('cancel', []); } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060D1A),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeController,
          child: Column(children: [
            const SizedBox(height: 48),
            Text(_greeting + ',', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16)),
            const SizedBox(height: 4),
            Text(_firstName, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _listening && _transcript.isNotEmpty ? '"$_transcript"' : _statusText,
                key: ValueKey(_listening ? _transcript : _statusText),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _listening ? const Color(0xFF10B981) : Colors.white.withOpacity(0.4),
                  fontSize: 13),
              ),
            ),
            const SizedBox(height: 48),
            GestureDetector(
              onTap: _onOrbTap,
              child: AnimatedBuilder(
                animation: _orbController,
                builder: (_, __) {
                  final scale = 0.95 + 0.05 * _orbController.value;
                  final isActive = _speaking || _listening;
                  final color = _listening ? const Color(0xFF10B981) : const Color(0xFF1E88E5);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 140, height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          color.withOpacity(0.9),
                          const Color(0xFF7C3AED).withOpacity(0.6),
                          Colors.transparent,
                        ]),
                        boxShadow: [BoxShadow(
                          color: color.withOpacity(isActive ? 0.7 : 0.25),
                          blurRadius: isActive ? 70 : 30,
                          spreadRadius: isActive ? 20 : 5)]),
                      child: Center(child: _speaking
                        ? _soundWave()
                        : _listening
                          ? _micPulse()
                          : const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 44)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_speaking)
              Text('Speaking...', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))
            else if (_listening)
              Text('Tap orb to cancel', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))
            else if (_step != _Step.greeting && _step != _Step.done)
              GestureDetector(
                onTap: _startListening,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1E88E5).withOpacity(0.4))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.mic_rounded, color: Color(0xFF1E88E5), size: 16),
                    const SizedBox(width: 6),
                    Text('Tap to speak', style: TextStyle(color: const Color(0xFF1E88E5).withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            const Spacer(),
            if (_cardsVisible) AnimatedBuilder(
              animation: _cardsController,
              builder: (_, __) {
                final slide = (1 - _cardsController.value) * 60;
                final fade = _cardsController.value;
                return Transform.translate(
                  offset: Offset(0, slide),
                  child: Opacity(opacity: fade, child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildCards(),
                  )),
                );
              },
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }

  Widget _buildCards() {
    switch (_step) {
      case _Step.askMode:
        return Column(children: [
          _bigCard('New Lesson', 'Start learning something new', const Color(0xFF1E88E5), Icons.menu_book_rounded, () => _onModeSelected('New Lesson')),
          const SizedBox(height: 12),
          _bigCard('Revision', 'Review topics you have studied', const Color(0xFF7C3AED), Icons.refresh_rounded, () => _onModeSelected('Revision')),
          const SizedBox(height: 12),
          _bigCard('Quiz Me', 'Test your knowledge', const Color(0xFF059669), Icons.quiz_rounded, () => _onModeSelected('Quiz')),
        ]);
      case _Step.askSubject:
        return Wrap(spacing: 10, runSpacing: 10,
          children: kSubjects.map((s) {
            final color = Color(s['color'] as int);
            return GestureDetector(
              onTap: () => _onSubjectSelected(s['name'] as String),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: color.withOpacity(0.45), width: 1.5)),
                child: Text(s['name'] as String,
                  style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            );
          }).toList(),
        );
      case _Step.askForm:
        return Wrap(spacing: 10, runSpacing: 10,
          children: _forms.map((f) => GestureDetector(
            onTap: () => _onFormSelected(f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5).withOpacity(0.15),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF1E88E5).withOpacity(0.45), width: 1.5)),
              child: Text(f, style: const TextStyle(color: Color(0xFF1E88E5), fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          )).toList(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _soundWave() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final h = [20.0,35.0,50.0,35.0,20.0][i] * (0.4 + 0.6 * ((_pulseController.value + i * 0.2) % 1.0));
          return Container(margin: const EdgeInsets.symmetric(horizontal: 3), width: 4, height: h,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)));
        })));
  }

  Widget _micPulse() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) => Transform.scale(
        scale: 0.85 + 0.15 * _pulseController.value,
        child: const Icon(Icons.mic_rounded, color: Colors.white, size: 44),
      ),
    );
  }

  Widget _bigCard(String title, String subtitle, Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35), width: 1.5)),
        child: Row(children: [
          Container(width: 46, height: 46,
            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, color: color.withOpacity(0.7), size: 14),
        ]),
      ),
    );
  }
}