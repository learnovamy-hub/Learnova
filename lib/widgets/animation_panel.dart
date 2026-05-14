import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import '../config/constants.dart';

class AnimationPanel extends StatefulWidget {
  final List<Map<String, dynamic>> steps;
  final List<Map<String, dynamic>> altSteps;
  final bool isConfused;
  final VoidCallback? onDismiss;

  const AnimationPanel({
    super.key,
    required this.steps,
    required this.altSteps,
    this.isConfused = false,
    this.onDismiss,
  });

  @override
  State<AnimationPanel> createState() => _AnimationPanelState();
}

class _AnimationPanelState extends State<AnimationPanel> {
  // Track which viewType IDs have already been registered — process-lifetime singleton
  static final Set<String> _registered = {};

  int _step = 0;
  bool _useAlt = false;

  List<Map<String, dynamic>> get _active =>
      (_useAlt && widget.altSteps.isNotEmpty) ? widget.altSteps : widget.steps;

  @override
  void didUpdateWidget(AnimationPanel old) {
    super.didUpdateWidget(old);
    // New standard loaded — reset to step 1, main explanation
    if (old.steps != widget.steps && widget.steps.isNotEmpty) {
      setState(() { _step = 0; _useAlt = false; });
    }
    // Student confused — switch to alternative explanation
    if (!old.isConfused && widget.isConfused && widget.altSteps.isNotEmpty) {
      setState(() { _useAlt = true; _step = 0; });
    }
  }

  String _wrapSvg(String svgContent) => '''<!DOCTYPE html>
<html><head><style>
*{margin:0;padding:0;box-sizing:border-box;}
body{background:#0F1117;display:flex;align-items:center;justify-content:center;
     height:100vh;overflow:hidden;}
svg{max-width:100%;max-height:100%;}
</style></head>
<body>$svgContent</body></html>''';

  Widget _svgView(String svgContent) {
    final viewId = 'anim_${svgContent.hashCode.abs()}';
    if (!_registered.contains(viewId)) {
      _registered.add(viewId);
      final html5 = _wrapSvg(svgContent);
      ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
        return html.IFrameElement()
          ..srcdoc = html5
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..setAttribute('scrolling', 'no')
          ..setAttribute('sandbox', 'allow-scripts');
      });
    }
    return HtmlElementView(viewType: viewId);
  }

  @override
  Widget build(BuildContext context) {
    final steps = _active;
    if (steps.isEmpty) return const SizedBox.shrink();

    final idx = _step.clamp(0, steps.length - 1);
    final current = steps[idx];
    final svg       = current['svg']      as String? ?? '';
    final title     = current['title']    as String? ?? '';
    final narration = current['narration'] as String? ?? '';
    final total     = steps.length;
    final isLast    = idx >= total - 1;

    return Container(
      decoration: BoxDecoration(
        color: kBg,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        // ── Header ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12)),
          ),
          child: Row(children: [
            const Icon(Icons.auto_graph_rounded, color: kPrimary, size: 15),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Visual Explanation',
                style: TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            Text('${idx + 1} / $total',
              style: const TextStyle(color: kMuted, fontSize: 11)),
            if (widget.onDismiss != null) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: widget.onDismiss,
                child: const Icon(Icons.close_rounded, color: kMuted, size: 16)),
            ],
          ]),
        ),

        // ── SVG frame ────────────────────────────────────────────────────
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: svg.isNotEmpty
              ? _svgView(svg)
              : Container(
                  color: kBg,
                  alignment: Alignment.center,
                  child: Text(title,
                    style: const TextStyle(color: kPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
                ),
          ),
        ),

        // ── Narration ────────────────────────────────────────────────────
        if (narration.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: kSurface,
            child: Text(narration,
              style: const TextStyle(color: kMuted, fontSize: 12, height: 1.4)),
          ),

        // ── Controls ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: Row(children: [
            // "Another way" toggle
            if (widget.altSteps.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() { _useAlt = !_useAlt; _step = 0; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _useAlt ? kPrimary.withOpacity(0.15) : kSurface2,
                    border: Border.all(
                      color: _useAlt ? kPrimary.withOpacity(0.5) : kBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lightbulb_outline_rounded,
                      color: _useAlt ? kPrimary : kMuted, size: 12),
                    const SizedBox(width: 4),
                    Text('Another way',
                      style: TextStyle(
                        color: _useAlt ? kPrimary : kMuted,
                        fontSize: 11)),
                  ]),
                ),
              ),

            const Spacer(),

            // Back button
            if (idx > 0) ...[
              GestureDetector(
                onTap: () => setState(() => _step--),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: kSurface2,
                    border: Border.all(color: kBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('← Back',
                    style: TextStyle(color: kMuted, fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Next / Done button
            if (!isLast)
              GestureDetector(
                onTap: () => setState(() => _step++),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPrimary, kPrimary2]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Next →',
                    style: TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w600)),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.15),
                  border: Border.all(color: kGreen.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_outline, color: kGreen, size: 12),
                  SizedBox(width: 4),
                  Text('Got it!',
                    style: TextStyle(color: kGreen, fontSize: 11,
                      fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
