// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TtsPlayer extends StatefulWidget {
  final String text;
  final String title;
  const TtsPlayer({Key? key, required this.text, required this.title}) : super(key: key);
  @override
  State<TtsPlayer> createState() => _TtsPlayerState();
}

class _TtsPlayerState extends State<TtsPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _wave;
  bool _playing = false;
  bool _busy = false; // prevents double-tap issues
  double _rate = 0.9;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _stop();
    _wave.dispose();
    super.dispose();
  }

  void _stop() {
    try {
      js.context['speechSynthesis']?.callMethod('cancel', []);
    } catch (_) {}
    if (mounted) setState(() { _playing = false; _busy = false; });
  }

  Future<void> _speak() async {
    if (_busy) return;
    _busy = true;

    try {
      final synth = js.context['speechSynthesis'];
      if (synth == null) { _busy = false; return; }

      // Cancel any ongoing speech and wait for it to clear
      synth.callMethod('cancel', []);
      await Future.delayed(const Duration(milliseconds: 150));

      if (!mounted) { _busy = false; return; }

      final clean = widget.text
        .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{2600}-\u{27BF}]', unicode: true), '')
        .replaceAll(RegExp(r'\*+'), '')
        .replaceAll('#', '')
        .trim();

      final utterance = js.JsObject(js.context['SpeechSynthesisUtterance'], [clean]);
      utterance['rate']   = _rate;
      utterance['pitch']  = 1.0;
      utterance['volume'] = 1.0;
      utterance['lang']   = 'en-US';

      // Pick best voice
      try {
        final voices = synth.callMethod('getVoices', []);
        if (voices != null) {
          final preferred = ['Google UK English Female', 'Samantha', 'Karen', 'Microsoft Zira', 'Google US English'];
          for (final name in preferred) {
            for (var i = 0; i < (voices['length'] as int? ?? 0); i++) {
              final v = voices.callMethod('item', [i]);
              if (v != null && (v['name'] as String? ?? '').contains(name.split(' ').first)) {
                utterance['voice'] = v;
                break;
              }
            }
            if (utterance['voice'] != null) break;
          }
        }
      } catch (_) {}

      utterance['onstart'] = js.allowInterop((_) {
        if (mounted) setState(() { _playing = true; _busy = false; });
      });
      utterance['onend'] = js.allowInterop((_) {
        if (mounted) setState(() { _playing = false; _busy = false; });
      });
      utterance['onerror'] = js.allowInterop((_) {
        if (mounted) setState(() { _playing = false; _busy = false; });
      });

      synth.callMethod('speak', [utterance]);
      if (mounted) setState(() => _playing = true);

    } catch (e) {
      if (mounted) setState(() { _playing = false; _busy = false; });
    }
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    if (_playing) {
      _stop();
    } else {
      await _speak();
    }
  }

  Future<void> _setRate(double rate) async {
    setState(() => _rate = rate);
    if (_playing) {
      _stop();
      await Future.delayed(const Duration(milliseconds: 200));
      await _speak();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _playing ? 'Stop reading' : 'Listen to this message',
      button: true,
      child: GestureDetector(
        onTap: _busy ? null : _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _playing
              ? const Color(0xFF1E88E5)
              : _busy
                ? const Color(0xFF1E88E5).withOpacity(0.3)
                : const Color(0xFF1E88E5).withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E88E5).withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(
                  _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  color: _playing ? Colors.white : const Color(0xFF1E88E5),
                  size: 16,
                ),
            const SizedBox(width: 5),
            if (_playing)
              AnimatedBuilder(
                animation: _wave,
                builder: (_, __) => Row(mainAxisSize: MainAxisSize.min,
                  children: List.generate(4, (i) {
                    final h = 3.0 + (i % 3 + 1) * 2.5 * (_wave.value + 0.3).clamp(0.3, 1.0);
                    return Container(margin: const EdgeInsets.only(right: 2), width: 2, height: h,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)));
                  })),
              )
            else if (!_busy)
              const Text('Listen', style: TextStyle(color: Color(0xFF1E88E5), fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            PopupMenuButton<double>(
              icon: Icon(Icons.speed_rounded, size: 12,
                color: _playing ? Colors.white70 : const Color(0xFF1E88E5).withOpacity(0.6)),
              color: const Color(0xFF1565C0),
              padding: EdgeInsets.zero,
              tooltip: 'Speed',
              onSelected: _setRate,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 0.6, child: Text('Slow',   style: TextStyle(color: Colors.white, fontSize: 12))),
                const PopupMenuItem(value: 0.9, child: Text('Normal', style: TextStyle(color: Colors.white, fontSize: 12))),
                const PopupMenuItem(value: 1.2, child: Text('Fast',   style: TextStyle(color: Colors.white, fontSize: 12))),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

