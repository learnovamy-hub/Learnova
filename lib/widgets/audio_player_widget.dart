// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/material.dart';

class LessonAudioPlayer extends StatefulWidget {
  final String? audioUrl;    // pre-generated OpenAI URL
  final String fallbackText; // browser TTS fallback
  final String title;
  const LessonAudioPlayer({Key? key, this.audioUrl, required this.fallbackText, required this.title}) : super(key: key);
  @override
  State<LessonAudioPlayer> createState() => _LessonAudioPlayerState();
}

class _LessonAudioPlayerState extends State<LessonAudioPlayer> {
  bool _playing = false;
  bool _loading = false;
  js.JsObject? _audio;

  @override
  void dispose() {
    _stopAll();
    super.dispose();
  }

  void _stopAll() {
    // Stop HTML audio
    try { _audio?.callMethod('pause', []); _audio = null; } catch (_) {}
    // Stop browser TTS
    try { js.context['speechSynthesis']?.callMethod('cancel', []); } catch (_) {}
    if (mounted) setState(() { _playing = false; _loading = false; });
  }

  Future<void> _toggle() async {
    if (_playing) { _stopAll(); return; }

    if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty) {
      // Play pre-generated OpenAI audio
      setState(() { _loading = true; });
      try {
        _audio = js.JsObject(js.context['Audio'], [widget.audioUrl]);
        _audio!['oncanplaythrough'] = js.allowInterop((_) {
          _audio?.callMethod('play', []);
          if (mounted) setState(() { _loading = false; _playing = true; });
        });
        _audio!['onended'] = js.allowInterop((_) {
          if (mounted) setState(() { _playing = false; });
        });
        _audio!['onerror'] = js.allowInterop((_) {
          if (mounted) setState(() { _loading = false; _playing = false; });
          _fallbackTts();
        });
        _audio!.callMethod('load', []);
      } catch (e) {
        setState(() { _loading = false; });
        _fallbackTts();
      }
    } else {
      _fallbackTts();
    }
  }

  void _fallbackTts() {
    try {
      final synth = js.context['speechSynthesis'];
      if (synth == null) return;
      synth.callMethod('cancel', []);
      final clean = widget.fallbackText
        .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{2600}-\u{27BF}]', unicode: true), '')
        .replaceAll(RegExp(r'\*+'), '').replaceAll('#', '').trim();
      final utterance = js.JsObject(js.context['SpeechSynthesisUtterance'], [clean]);
      utterance['rate'] = 0.9;
      utterance['onstart'] = js.allowInterop((_) { if (mounted) setState(() => _playing = true); });
      utterance['onend']   = js.allowInterop((_) { if (mounted) setState(() => _playing = false); });
      utterance['onerror'] = js.allowInterop((_) { if (mounted) setState(() => _playing = false); });
      synth.callMethod('speak', [utterance]);
      setState(() => _playing = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hasRealAudio = widget.audioUrl != null && widget.audioUrl!.isNotEmpty;
    return GestureDetector(
      onTap: _loading ? null : _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _playing ? const Color(0xFF1E88E5) : const Color(0xFF1E88E5).withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1E88E5).withOpacity(0.5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: _playing ? Colors.white : const Color(0xFF1E88E5), size: 18),
          const SizedBox(width: 6),
          Text(
            _loading ? 'Loading...' : _playing ? 'Stop' : hasRealAudio ? 'Play Audio' : 'Listen',
            style: TextStyle(color: _playing ? Colors.white : const Color(0xFF1E88E5), fontSize: 12, fontWeight: FontWeight.w600)),
          if (hasRealAudio && !_playing && !_loading) ...[ 
            const SizedBox(width: 6),
            Icon(Icons.volume_up_rounded, color: const Color(0xFF1E88E5).withOpacity(0.7), size: 14),
          ],
        ]),
      ),
    );
  }
}
