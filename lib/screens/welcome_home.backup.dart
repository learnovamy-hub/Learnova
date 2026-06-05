// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:js' as js;
import 'package:flutter/material.dart';
import '../config/constants.dart';
import 'main_shell.dart';

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
  bool _cardsVisible = false;

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
    Future.delayed(const Duration(milliseconds: 600), _greet);
  }

  void _greet() {
    final text = '$_greeting, $_firstName! Welcome to Learnova. What would you like to do today?';
    _speak(text);
  }

  void _speak(String text) {
    try {
      final synth = js.context['speechSynthesis'];
      if (synth == null) { _showCards(); return; }
      synth.callMethod('cancel', []);
      final utterance = js.JsObject(js.context['SpeechSynthesisUtterance'], [text]);
      final voices = synth.callMethod('getVoices', []);
      final length = voices['length'] as int;
      for (var i = 0; i < length; i++) {
        final v = voices[i];
        final name = v['name'].toString().toLowerCase();
        if (name.contains('zira') || name.contains('female') || name.contains('samantha') || name.contains('susan') || name.contains('google uk english female')) {
          utterance['voice'] = v;
          break;
        }
      }
      utterance['rate'] = 0.85;
      utterance['pitch'] = 1.1;
      utterance['onstart'] = js.allowInterop((_) { if (mounted) setState(() => _speaking = true); });
      utterance['onend'] = js.allowInterop((_) { if (mounted) setState(() => _speaking = false); _showCards(); });
      utterance['onerror'] = js.allowInterop((_) { if (mounted) setState(() => _speaking = false); _showCards(); });
      synth.callMethod('speak', [utterance]);
      if (mounted) setState(() => _speaking = true);
    } catch (_) { _showCards(); }
  }

  void _showCards() {
    if (!mounted) return;
    setState(() => _cardsVisible = true);
    _cardsController.forward();
  }

  @override
  void dispose() {
    _orbController.dispose();
    _cardsController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    try { js.context['speechSynthesis']?.callMethod('cancel', []); } catch (_) {}
    super.dispose();
  }

  void _navigate() { }

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
            Text('What would you like to do today?', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)),
            const SizedBox(height: 48),
            GestureDetector(
              onTap: () { if (!_speaking) _greet(); },
              child: AnimatedBuilder(
                animation: _orbController,
                builder: (_, __) {
                  final scale = 0.95 + 0.05 * _orbController.value;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 140, height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          const Color(0xFF1E88E5).withOpacity(0.9),
                          const Color(0xFF7C3AED).withOpacity(0.6),
                          Colors.transparent,
                        ]),
                        boxShadow: [BoxShadow(
                          color: const Color(0xFF1E88E5).withOpacity(_speaking ? 0.7 : 0.25),
                          blurRadius: _speaking ? 70 : 30,
                          spreadRadius: _speaking ? 20 : 5)]),
                      child: Center(child: _speaking ? _soundWave() : const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 44)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _speaking ? 'Speaking...' : _cardsVisible ? 'Tap to replay' : '',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
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
                    child: Column(children: [
                      _card('New Lesson', 'Start learning something new', const Color(0xFF1E88E5), Icons.menu_book_rounded),
                      const SizedBox(height: 12),
                      _card('Revision', 'Review topics you have studied', const Color(0xFF7C3AED), Icons.refresh_rounded),
                      const SizedBox(height: 12),
                      _card('Quiz Me', 'Test your knowledge', const Color(0xFF059669), Icons.quiz_rounded),
                    ]),
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

  Widget _card(String title, String subtitle, Color color, IconData icon) {
    return GestureDetector(
      onTap: _navigate,
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


