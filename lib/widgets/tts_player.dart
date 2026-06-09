// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class TtsPlayer extends StatefulWidget {
  final String text;
  final String title;
  final String language;
  const TtsPlayer({Key? key, required this.text, required this.title, this.language = 'bm'}) : super(key: key);
  @override
  State<TtsPlayer> createState() => _TtsPlayerState();
}

class _TtsPlayerState extends State<TtsPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _wave;
  bool _playing = false;
  bool _busy = false;
  html.AudioElement? _audioElement;

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
    try { _audioElement?.pause(); _audioElement = null; } catch (_) {}
    if (mounted) setState(() { _playing = false; _busy = false; });
  }

  String _clean(String t) => t
    .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}]', unicode: true), '')
    .replaceAll(RegExp(r'[\u{2600}-\u{27BF}]', unicode: true), '')
    .replaceAll(RegExp(r'\*+'), '')
    .replaceAll('#', '')
    .trim();

  Future<void> _speak() async {
    if (_busy) return;
    if (mounted) setState(() { _busy = true; });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final resp = await http.post(
        Uri.parse('$kApiUrl/api/tts'),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'text': _clean(widget.text), 'voice': 'nova', 'language': widget.language}),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final blob = html.Blob([resp.bodyBytes], 'audio/mpeg');
        final url  = html.Url.createObjectUrlFromBlob(blob);
        _audioElement?.pause();
        _audioElement = html.AudioElement(url);
        _audioElement!.onEnded.listen((_) {
          html.Url.revokeObjectUrl(url);
          if (mounted) setState(() { _playing = false; _busy = false; });
        });
        _audioElement!.onError.listen((_) {
          html.Url.revokeObjectUrl(url);
          if (mounted) setState(() { _playing = false; _busy = false; });
        });
        await _audioElement!.play();
        if (mounted) setState(() { _playing = true; _busy = false; });
      } else {
        if (mounted) setState(() { _busy = false; });
      }
    } catch (_) {
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

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _playing ? 'Stop reading' : 'Baca kuat mesej ini',
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
              const Text('Baca Kuat', style: TextStyle(color: Color(0xFF1E88E5), fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
