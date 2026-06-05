// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/material.dart';

class LessonAudioPlayer extends StatefulWidget {
  final String? audioUrl;
  final String fallbackText;
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
    try { _audio?.callMethod('pause', []); _audio = null; } catch (_) {}
    if (mounted) setState(() { _playing = false; _loading = false; });
  }

  Future<void> _toggle() async {
    if (_playing) { _stopAll(); return; }
    if (widget.audioUrl == null || widget.audioUrl!.isEmpty) return; // no audio — do nothing

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
      });
      _audio!.callMethod('load', []);
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = widget.audioUrl != null && widget.audioUrl!.isNotEmpty;
    if (!hasAudio) return const SizedBox.shrink(); // no button if no Nova audio

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
            _loading ? 'Loading...' : _playing ? 'Stop' : 'Play Audio',
            style: TextStyle(color: _playing ? Colors.white : const Color(0xFF1E88E5), fontSize: 12, fontWeight: FontWeight.w600)),
          if (!_playing && !_loading) ...[
            const SizedBox(width: 6),
            Icon(Icons.volume_up_rounded, color: const Color(0xFF1E88E5).withOpacity(0.7), size: 14),
          ],
        ]),
      ),
    );
  }
}
