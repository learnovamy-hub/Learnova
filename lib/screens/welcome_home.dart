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

enum _Step { greeting, askMode, askSubject, done }

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
  String _transcript = '';
  String _statusText = '';
  String? _token;
  String? _serverName; // refreshed from server, overrides cached name
  html.AudioElement? _audioElement;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 14) return 'Good afternoon';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName {
    final name = _serverName ?? widget.studentName;
    final first = name.split(' ').first.trim();
    return first.isEmpty ? 'there' : first;
  }

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
    if (widget.studentId.isNotEmpty && _token != null) {
      await _fetchFromServer(prefs);
    }
    await Future.delayed(const Duration(milliseconds: 300));
    _greet();
  }

  Future<void> _fetchFromServer(SharedPreferences prefs) async {
    try {
      final resp = await http.get(
        Uri.parse('$kApiUrl/api/student/profile'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        // Refresh name so greeting uses latest server name
        final name = data['student']?['name']?.toString() ?? '';
        if (name.isNotEmpty) {
          await prefs.setString('student_name', name);
          await prefs.setString('name', name);
          if (mounted) setState(() => _serverName = name);
        }
      }
    } catch (_) {}
  }

  void _greet() {
    final greetings = [
      '$_greeting, $_firstName! Would you like to start a new lesson, do some revision, or take a quiz today?',
      '$_greeting, $_firstName! Great to see you. Are we starting a new topic, revising, or doing a quick quiz?',
      '$_greeting, $_firstName! Ready to learn? Let me know if you want a new lesson, revision, or a quiz.',
      'Welcome back, $_firstName! What shall we work on today — a new lesson, revision, or a quiz?',
      'Hello, $_firstName! Good to have you here. Shall we do a new lesson, some revision, or a quiz today?',
    ];
    _speak(greetings[Random().nextInt(greetings.length)], onDone: () {
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
                ? 'Voice not supported - tap a card below'
                : error == 'no-speech'
                  ? 'No speech detected - tap to try again'
                  : 'Tap orb to speak, or choose below';
          });
        }),
      ]);
    } catch (e) {
      if (mounted) setState(() { _listening = false; _statusText = 'Voice unavailable - tap a card below'; });
    }
  }

  void _handleSpeechResult(String t) {
    switch (_step) {
      case _Step.askMode:    _parseModeFromSpeech(t);    break;
      case _Step.askSubject: _parseSubjectFromSpeech(t); break;
      default: break;
    }
  }

  void _parseModeFromSpeech(String t) {
    String? mode;
    if (t.contains('lesson') || t.contains('learn') || t.contains('baru')) mode = 'New Lesson';
    else if (t.contains('revis') || t.contains('review') || t.contains('ulang')) mode = 'Revision';
    else if (t.contains('quiz') || t.contains('test')) mode = 'Quiz';
    if (mode != null) {
      _onModeSelected(mode);
    } else {
      _speak('Sorry, I did not catch that. Please say lesson, revision, or quiz.', onDone: () {
        if (mounted) setState(() => _statusText = 'Tap orb to speak, or choose below');
        _showCards();
      });
    }
  }

  void _parseSubjectFromSpeech(String t) {
    const aliases = {
      'Mathematics':     ['math', 'maths', 'mathematics'],
      'Add Maths':       ['add math', 'additional math', 'add maths'],
      'Physics':         ['physics', 'fizik'],
      'Biology':         ['biology', 'bio', 'biologi'],
      'Chemistry':       ['chemistry', 'chem', 'kimia'],
      'Geography':       ['geography', 'geo', 'geografi'],
      'Sejarah':         ['sejarah', 'history', 'sej'],
      'Bahasa Malaysia': ['bahasa', 'malay', 'bm'],
      'English':         ['english', 'eng', 'inggeris'],
    };
    String? matched;
    for (final entry in aliases.entries) {
      if (entry.value.any((a) => t.contains(a))) { matched = entry.key; break; }
    }
    if (matched != null) {
      _onSubjectSelected(matched);
    } else {
      _speak('Sorry, I did not catch that. Please say the subject name, for example maths, physics, biology, or english.', onDone: () {
        if (mounted) setState(() => _statusText = 'Tap orb to speak, or choose below');
        _showCards();
      });
    }
  }


  void _onModeSelected(String mode) {
    if (_speaking) return;
    setState(() { _selectedMode = mode; _cardsVisible = false; _listening = false; _transcript = ''; });
    _cardsController.reset();
    final replies = {
      'New Lesson': 'Great choice! Which subject would you like to study?',
      'Revision':   'Good idea. Which subject would you like to revise?',
      'Quiz':       'Let\'s test your knowledge. Which subject would you like to be quizzed on?',
    };
    _speak(replies[mode] ?? 'Which subject would you like?', onDone: () {
      if (mounted) setState(() { _step = _Step.askSubject; _statusText = 'Tap the orb to speak, or choose below'; });
      _showCards();
    });
  }

  void _onSubjectSelected(String subject) {
    if (_speaking) return;
    setState(() { _selectedSubject = subject; _cardsVisible = false; _listening = false; _transcript = ''; });
    _cardsController.reset();
    _speak('Great, opening $subject now!', onDone: _navigate);
    Future.delayed(const Duration(seconds: 4), () { if (mounted) _navigate(); });
  }


  void _navigate() {
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => MainShell(
        initialSubject: _selectedSubject ?? 'Mathematics',
        initialTabIndex: _selectedMode == 'Quiz' ? 3 : 2,
      ),
    ));
  }

  Future<void> _speak(String text, {VoidCallback? onDone}) async {
    if (!mounted) return;
    setState(() { _speaking = true; _listening = false; _transcript = ''; _statusText = ''; });
    bool fired = false;
    void fireOnce() {
      if (fired) return;
      fired = true;
      if (mounted) setState(() => _speaking = false);
      onDone?.call();
    }
    try {
      final resp = await http.post(
        Uri.parse('$kApiUrl/api/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text, 'voice': 'nova'}),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final blob = html.Blob([resp.bodyBytes], 'audio/mpeg');
        final url = html.Url.createObjectUrlFromBlob(blob);
        _audioElement?.pause();
        _audioElement = html.AudioElement(url);
        _audioElement!.onEnded.listen((_) { html.Url.revokeObjectUrl(url); fireOnce(); });
        _audioElement!.onError.listen((_) { html.Url.revokeObjectUrl(url); fireOnce(); });
        await _audioElement!.play();
        final ms = (text.split(' ').length * 950 + 4000).clamp(5000, 20000);
        Future.delayed(Duration(milliseconds: ms), () { if (mounted && _speaking) fireOnce(); });
        return;
      }
    } catch (_) {}
    // Nova unavailable — proceed silently so the UI flow continues
    fireOnce();
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
    _audioElement?.pause();
    super.dispose();
  }

  void _skipToHome() {
    _audioElement?.pause();
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => const MainShell(initialTabIndex: 0),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060D1A),
      body: SafeArea(
        child: Stack(children: [
          FadeTransition(
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
            Center(
             child: GestureDetector(
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
           ),
            const SizedBox(height: 16),
            if (_speaking)
              Text('Nova is speaking...', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))
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
          ),  // end FadeTransition
          Positioned(
            top: 8, right: 12,
            child: TextButton.icon(
              onPressed: _skipToHome,
              icon: const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white30),
              label: const Text('Terus', style: TextStyle(color: Colors.white30, fontSize: 12)),
            ),
          ),
        ]),  // end Stack
      ),  // end SafeArea
    );
  }

  Widget _buildCards() {
    switch (_step) {
      case _Step.askMode:
        return Column(children: [
          _bigCard('New Lesson', 'Learn a new topic', const Color(0xFF1E88E5), Icons.menu_book_rounded, () => _onModeSelected('New Lesson')),
          const SizedBox(height: 12),
          _bigCard('Revision', 'Review previous topics', const Color(0xFF7C3AED), Icons.refresh_rounded, () => _onModeSelected('Revision')),
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
