import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Color scheme map ──────────────────────────────────────────────────────────
const Map<String, Color> _kScheme = {
  'purple': Color(0xFF6C5CE7),
  'teal':   Color(0xFF1D9E75),
  'blue':   Color(0xFF378ADD),
  'coral':  Color(0xFFD85A30),
  'green':  Color(0xFF639922),
  'amber':  Color(0xFFBA7517),
  'pink':   Color(0xFFD4537E),
};
const _kBg      = Color(0xFF0A0A1A);
const _kSurface = Color(0xFF12122A);
const _kBorder  = Color(0xFF2A2A4A);
const _kText    = Color(0xFFE2E8F0);
const _kMuted   = Color(0xFF94A3B8);
const _kAmber   = Color(0xFFF59E0B);
const _kGreen   = Color(0xFF10B981);
const _kCyan    = Color(0xFF00D4FF);
const _kPink    = Color(0xFFFF6B9D);

Color _schemeColor(String scheme) => _kScheme[scheme] ?? _kScheme['purple']!;

// ── Widget ────────────────────────────────────────────────────────────────────
class TopicAnimationPlayer extends StatefulWidget {
  final Map<String, dynamic> animation;
  final VoidCallback? onDismiss;

  const TopicAnimationPlayer({super.key, required this.animation, this.onDismiss});

  @override
  State<TopicAnimationPlayer> createState() => _TopicAnimationPlayerState();
}

class _TopicAnimationPlayerState extends State<TopicAnimationPlayer>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late AnimationController _pulse;

  List<Map<String, dynamic>> get _steps =>
      (widget.animation['steps'] as List?)
          ?.map((s) => Map<String, dynamic>.from(s as Map))
          .toList() ?? [];

  String get _scheme => (widget.animation['color_scheme'] as String?) ?? 'purple';
  Color  get _accent => _schemeColor(_scheme);
  String get _type   => (widget.animation['animation_type'] as String?) ?? 'working';
  Map<String, dynamic>? get _graphCfg {
    final g = widget.animation['graph_config'];
    return g is Map ? Map<String, dynamic>.from(g) : null;
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(TopicAnimationPlayer old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) setState(() => _step = 0);
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  void _next() { if (_step < _steps.length - 1) setState(() => _step++); }
  void _prev() { if (_step > 0) setState(() => _step--); }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    if (steps.isEmpty) return const SizedBox.shrink();

    final idx     = _step.clamp(0, steps.length - 1);
    final current = steps[idx];
    final total   = steps.length;
    final isLast  = idx >= total - 1;
    final isFirst = idx == 0;
    final progress = (idx + 1) / total;

    final title = widget.animation['title']  as String?
                ?? widget.animation['title_bm'] as String? ?? '';
    final label = current['label'] as String? ?? '';
    final text  = current['text']  as String? ?? '';
    final math  = current['math']  as String? ?? '';
    final tip   = current['tip']   as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        color: _kBg,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: const BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.6 + 0.4 * _pulse.value),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: _accent.withOpacity(0.45 * _pulse.value),
                    blurRadius: 6)],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                style: TextStyle(color: _accent, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 0.3),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text('${idx + 1}/$total',
              style: const TextStyle(color: _kMuted, fontSize: 10)),
            if (widget.onDismiss != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onDismiss,
                child: const Icon(Icons.close_rounded, color: _kMuted, size: 16)),
            ],
          ]),
        ),

        // ── Progress bar ────────────────────────────────────────────────────
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: progress),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          builder: (_, v, __) => LinearProgressIndicator(
            value: v, minHeight: 2,
            backgroundColor: _kBorder,
            valueColor: AlwaysStoppedAnimation<Color>(_accent),
          ),
        ),

        // ── Visual area ──────────────────────────────────────────────────────
        Expanded(
          flex: 5,
          child: _buildVisual(idx, steps.length),
        ),

        // ── Step label pill ──────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.12),
            border: Border.all(color: _accent.withOpacity(0.35)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
            style: TextStyle(color: _accent, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),

        // ── Step text ────────────────────────────────────────────────────────
        if (text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(text,
              style: const TextStyle(color: _kText, fontSize: 12, height: 1.5)),
          ),

        // ── Math formula ─────────────────────────────────────────────────────
        if (math.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kSurface,
              border: Border(left: BorderSide(color: _accent, width: 2.5)),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(6), bottomRight: Radius.circular(6)),
            ),
            child: Text(math,
              style: TextStyle(color: _accent, fontSize: 14,
                fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),

        // ── SPM tip ──────────────────────────────────────────────────────────
        if (tip.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _kAmber.withOpacity(0.08),
              border: Border.all(color: _kAmber.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('💡 $tip',
              style: const TextStyle(color: _kAmber, fontSize: 11, height: 1.4)),
          ),

        // ── Controls ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(children: [
            // Dot navigation
            Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(total, (i) => GestureDetector(
                onTap: () => setState(() => _step = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: i == idx ? 20 : 6, height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == idx ? _accent : _kBorder,
                    borderRadius: BorderRadius.circular(3)),
                ),
              ))),
            const SizedBox(height: 10),
            // Back / Next
            Row(children: [
              if (!isFirst) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: _prev,
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: _kSurface, border: Border.all(color: _kBorder),
                        borderRadius: BorderRadius.circular(8)),
                      alignment: Alignment.center,
                      child: const Text('← Kembali',
                        style: TextStyle(color: _kMuted, fontSize: 12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: isLast
                  ? Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: _kGreen.withOpacity(0.12),
                        border: Border.all(color: _kGreen.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(8)),
                      alignment: Alignment.center,
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_outline_rounded, color: _kGreen, size: 14),
                        SizedBox(width: 6),
                        Text('Faham!', style: TextStyle(color: _kGreen,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    )
                  : GestureDetector(
                      onTap: _next,
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_accent, _accent.withOpacity(0.75)]),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [BoxShadow(
                            color: _accent.withOpacity(0.3), blurRadius: 8,
                            offset: const Offset(0, 2))]),
                        alignment: Alignment.center,
                        child: const Text('Seterusnya →',
                          style: TextStyle(color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w700)),
                      ),
                    ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  // ── Visual renderer ───────────────────────────────────────────────────────
  Widget _buildVisual(int stepIdx, int totalSteps) {
    final cfg = _graphCfg;
    if (_type == 'graph' && cfg != null) {
      return _GraphCanvas(config: cfg, accent: _accent, stepIdx: stepIdx, totalSteps: totalSteps);
    }
    if (_type == 'working') {
      return _WorkingVisual(steps: _steps, currentIdx: stepIdx, accent: _accent);
    }
    return _DiagramVisual(
      type: _type, accent: _accent,
      subject: widget.animation['subject'] as String? ?? '',
      topic: widget.animation['title_bm'] as String? ?? '',
      stepIdx: stepIdx, totalSteps: totalSteps,
    );
  }
}

// ── Graph canvas (CustomPaint — no packages needed) ───────────────────────────
class _GraphCanvas extends StatelessWidget {
  final Map<String, dynamic> config;
  final Color accent;
  final int stepIdx;
  final int totalSteps;

  const _GraphCanvas({required this.config, required this.accent,
    required this.stepIdx, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      padding: const EdgeInsets.all(8),
      child: CustomPaint(
        painter: _GraphPainter(config: config, accent: accent,
          stepIdx: stepIdx, totalSteps: totalSteps),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final Map<String, dynamic> config;
  final Color accent;
  final int stepIdx;
  final int totalSteps;

  _GraphPainter({required this.config, required this.accent,
    required this.stepIdx, required this.totalSteps});

  @override
  void paint(Canvas canvas, Size size) {
    final eqType  = config['equation_type'] as String? ?? 'quadratic';
    final a       = (config['a'] as num?)?.toDouble() ?? 1.0;
    final b       = (config['b'] as num?)?.toDouble() ?? 0.0;
    final c       = (config['c'] as num?)?.toDouble() ?? 0.0;
    final xMin    = (config['x_min'] as num?)?.toDouble() ?? -5.0;
    final xMax    = (config['x_max'] as num?)?.toDouble() ?? 5.0;
    final yMin    = (config['y_min'] as num?)?.toDouble() ?? -5.0;
    final yMax    = (config['y_max'] as num?)?.toDouble() ?? 5.0;
    final xLabel  = config['x_label'] as String? ?? 'x';
    final yLabel  = config['y_label'] as String? ?? 'y';
    final keyPts  = (config['key_points'] as List?)
        ?.map((p) => Map<String, dynamic>.from(p as Map)).toList() ?? [];

    final w = size.width;
    final h = size.height;

    // Coordinate transform
    Offset toCanvas(double x, double y) {
      final px = (x - xMin) / (xMax - xMin) * w;
      final py = h - (y - yMin) / (yMax - yMin) * h;
      return Offset(px, py);
    }

    // Origin
    final ox = (-xMin) / (xMax - xMin) * w;
    final oy = h - (-yMin) / (yMax - yMin) * h;

    // Grid lines
    final gridPaint = Paint()..color = const Color(0xFF2A2A4A)..strokeWidth = 0.5;
    for (int i = xMin.ceil(); i <= xMax.floor(); i++) {
      final x = (i - xMin) / (xMax - xMin) * w;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (int i = yMin.ceil(); i <= yMax.floor(); i++) {
      final y = h - (i - yMin) / (yMax - yMin) * h;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Axes
    final axisPaint = Paint()..color = const Color(0xFF4A5568)..strokeWidth = 1.5;
    if (oy >= 0 && oy <= h) canvas.drawLine(Offset(0, oy), Offset(w, oy), axisPaint);
    if (ox >= 0 && ox <= w) canvas.drawLine(Offset(ox, 0), Offset(ox, h), axisPaint);

    // Axis labels
    final labelStyle = TextStyle(color: const Color(0xFF94A3B8), fontSize: 10);
    void drawLabel(String text, Offset pos) {
      final span = TextSpan(text: text, style: labelStyle);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
    if (oy >= 0 && oy <= h) drawLabel(xLabel, Offset(w - 12, oy - 12));
    if (ox >= 0 && ox <= w) drawLabel(yLabel, Offset(ox + 12, 8));

    // Only draw curve from step 2 onwards (step 0 = axes only)
    final showCurve = stepIdx >= 1 || totalSteps <= 2;

    if (showCurve) {
      // Plot curve
      double evalY(double x) {
        switch (eqType) {
          case 'quadratic': return a * x * x + b * x + c;
          case 'linear':    return a * x + b;
          case 'cubic':     return a * x * x * x + b * x * x + c * x;
          case 'sine':      return a * math.sin(b * x + c) + (config['d'] as num? ?? 0).toDouble();
          case 'cosine':    return a * math.cos(b * x + c) + (config['d'] as num? ?? 0).toDouble();
          case 'inverse':   return x != 0 ? a / x + b : double.nan;
          case 'variation': return a > 0 ? a * math.pow(x.abs(), b).toDouble() * (x < 0 ? -1 : 1) : double.nan;
          default:          return a * x * x + b * x + c;
        }
      }

      final curvePaint = Paint()
        ..color = accent
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      bool penDown = false;
      const steps = 200;
      for (int i = 0; i <= steps; i++) {
        final x = xMin + (xMax - xMin) * i / steps;
        final y = evalY(x);
        if (y.isNaN || y.isInfinite || y < yMin - 1 || y > yMax + 1) {
          penDown = false;
          continue;
        }
        final p = toCanvas(x, y);
        if (!penDown) { path.moveTo(p.dx, p.dy); penDown = true; }
        else path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, curvePaint);
    }

    // Key points (from step 3 onwards)
    final showPoints = stepIdx >= 2 || totalSteps <= 3;
    if (showPoints && keyPts.isNotEmpty) {
      const ptColors = {'cyan': _kCyan, 'pink': _kPink, 'amber': _kAmber};
      final ptStyle = TextStyle(color: _kText, fontSize: 9, fontWeight: FontWeight.bold);

      for (final pt in keyPts) {
        final px = (pt['x'] as num?)?.toDouble() ?? 0.0;
        final py = (pt['y'] as num?)?.toDouble() ?? 0.0;
        final ptLabel = pt['label'] as String? ?? '';
        final ptColorName = pt['color'] as String? ?? 'cyan';
        final ptColor = ptColors[ptColorName] ?? _kCyan;
        final pos = toCanvas(px, py);

        if (pos.dx < 0 || pos.dx > w || pos.dy < 0 || pos.dy > h) continue;

        // Dot
        canvas.drawCircle(pos, 5, Paint()..color = ptColor);
        canvas.drawCircle(pos, 5, Paint()
          ..color = ptColor.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 3);

        // Label
        if (ptLabel.isNotEmpty) {
          final span = TextSpan(text: ptLabel, style: ptStyle);
          final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
          tp.layout();
          tp.paint(canvas, Offset(pos.dx + 6, pos.dy - tp.height - 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.stepIdx != stepIdx || old.config != config;
}

// ── Algebra working visual ─────────────────────────────────────────────────────
class _WorkingVisual extends StatelessWidget {
  final List<Map<String, dynamic>> steps;
  final int currentIdx;
  final Color accent;

  const _WorkingVisual({required this.steps, required this.currentIdx, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(math.min(currentIdx + 1, steps.length), (i) {
            final s = steps[i];
            final isCurrent = i == currentIdx;
            final mathText = s['math'] as String? ?? '';
            return AnimatedOpacity(
              opacity: isCurrent ? 1.0 : 0.35,
              duration: const Duration(milliseconds: 300),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCurrent ? _kSurface : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                      color: isCurrent ? accent : const Color(0xFF2A2A4A),
                      width: isCurrent ? 3 : 1)),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(6), bottomRight: Radius.circular(6)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((s['label'] as String? ?? '').replaceFirst(RegExp(r'^LANGKAH \d+ — '), ''),
                    style: TextStyle(
                      color: isCurrent ? accent : _kMuted,
                      fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                  if (mathText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(mathText,
                      style: TextStyle(
                        color: isCurrent ? _kText : _kMuted,
                        fontSize: isCurrent ? 15 : 13,
                        fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w400,
                        letterSpacing: 0.5)),
                  ],
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── Diagram / Physics / Biology visual ───────────────────────────────────────
class _DiagramVisual extends StatelessWidget {
  final String type;
  final Color accent;
  final String subject;
  final String topic;
  final int stepIdx;
  final int totalSteps;

  const _DiagramVisual({required this.type, required this.accent,
    required this.subject, required this.topic,
    required this.stepIdx, required this.totalSteps});

  IconData _subjectIcon() {
    if (subject.contains('Physics'))   return Icons.bolt_rounded;
    if (subject.contains('Chemistry')) return Icons.science_rounded;
    if (subject.contains('Biology'))   return Icons.eco_rounded;
    if (subject.contains('Sejarah'))   return Icons.history_edu_rounded;
    return Icons.auto_awesome_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final progress = (stepIdx + 1) / totalSteps;
    return Container(
      color: _kBg,
      child: Stack(alignment: Alignment.center, children: [
        // Radial glow background
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                accent.withOpacity(0.08 + 0.06 * progress),
                Colors.transparent,
              ],
              radius: 0.8,
            ),
          ),
        ),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Icon ring
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.1),
              border: Border.all(color: accent.withOpacity(0.35), width: 2),
            ),
            child: Icon(_subjectIcon(), color: accent, size: 34),
          ),
          const SizedBox(height: 12),
          // Step progress arc label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              border: Border.all(color: accent.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Langkah ${stepIdx + 1} daripada $totalSteps',
              style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          // Dot indicators showing progress
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(totalSteps, (i) => Container(
              width: i <= stepIdx ? 22 : 8, height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: i <= stepIdx ? accent : const Color(0xFF2A2A4A),
                borderRadius: BorderRadius.circular(3)),
            ))),
        ]),
      ]),
    );
  }
}
