import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AnimatedMessage extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final MarkdownStyleSheet? styleSheet;
  final VoidCallback? onComplete;

  const AnimatedMessage({
    super.key,
    required this.text,
    this.style,
    this.styleSheet,
    this.onComplete,
  });

  @override
  State<AnimatedMessage> createState() => _AnimatedMessageState();
}

class _AnimatedMessageState extends State<AnimatedMessage> {
  List<String> _words = [];
  int _visibleCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant AnimatedMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _timer?.cancel();
      _reset();
    }
  }

  void _reset() {
    _words = widget.text.split(' ').where((w) => w.trim().isNotEmpty).toList();
    _visibleCount = 0;
    _startAnimation();
  }

  void _startAnimation() {
    final delay = _words.length > 50 ? 35 : 45;

    _timer = Timer.periodic(Duration(milliseconds: delay), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_visibleCount < _words.length) {
          _visibleCount += _words.length > 80 ? 3 : 2;
          if (_visibleCount > _words.length) {
            _visibleCount = _words.length;
          }
        } else {
          timer.cancel();
          widget.onComplete?.call();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleText = _words.take(_visibleCount).join(' ');

    return MarkdownBody(
      data: visibleText,
      selectable: true,
      styleSheet: widget.styleSheet ??
          MarkdownStyleSheet(
            p: widget.style ?? const TextStyle(fontSize: 14, height: 1.6),
          ),
    );
  }
}
