// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as webHtml;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:fl_chart/fl_chart.dart';

/// Renders tutor-generated visual content: math workings, Desmos graphs, or charts.
/// Shows nothing (SizedBox.shrink) when visual is null or type is 'none'.
class VisualWidget extends StatelessWidget {
  final Map<String, dynamic>? visual;

  const VisualWidget({super.key, this.visual});

  @override
  Widget build(BuildContext context) {
    if (visual == null) return const SizedBox.shrink();
    final type = visual!['type'] as String? ?? 'none';
    if (type == 'none') return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(type),
          _buildContent(type),
        ],
      ),
    );
  }

  Widget _buildHeader(String type) {
    final icons = {
      'math_working': Icons.functions,
      'desmos': Icons.show_chart,
      'chart': Icons.bar_chart,
    };
    final labels = {
      'math_working': 'Step-by-step Working',
      'desmos': 'Graph',
      'chart': 'Chart',
    };
    final data = visual![type] as Map<String, dynamic>?;
    final title = data?['title'] as String? ?? labels[type] ?? 'Visual';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Icon(icons[type] ?? Icons.auto_graph, color: const Color(0xFF6C63FF), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFFE0D7FF),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(String type) {
    switch (type) {
      case 'math_working':
        return _MathWorkingView(data: visual!['math_working'] as Map<String, dynamic>? ?? {});
      case 'desmos':
        return _DesmosView(data: visual!['desmos'] as Map<String, dynamic>? ?? {});
      case 'chart':
        return _ChartView(data: visual!['chart'] as Map<String, dynamic>? ?? {});
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Math Working ──────────────────────────────────────────────────────────────

class _MathWorkingView extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MathWorkingView({required this.data});

  @override
  Widget build(BuildContext context) {
    final steps = (data['steps'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    if (steps.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: steps.asMap().entries.map((entry) {
          final i = entry.key;
          final step = entry.value;
          final label = step['label'] as String? ?? '';
          final latex = step['latex'] as String? ?? '';
          return _StepRow(index: i + 1, label: label, latex: latex);
        }).toList(),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final String label;
  final String latex;

  const _StepRow({required this.index, required this.label, required this.latex});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF13111F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '$index',
                        style: const TextStyle(
                          color: Color(0xFF6C63FF),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFB0A8D0),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (latex.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _safeLatex(latex),
            ),
        ],
      ),
    );
  }

  Widget _safeLatex(String latex) {
    try {
      return Math.tex(
        latex,
        textStyle: const TextStyle(color: Color(0xFFF0ECFF), fontSize: 15),
        mathStyle: MathStyle.display,
        onErrorFallback: (err) => Text(
          latex,
          style: const TextStyle(color: Color(0xFFF0ECFF), fontSize: 13, fontFamily: 'monospace'),
        ),
      );
    } catch (_) {
      return Text(
        latex,
        style: const TextStyle(color: Color(0xFFF0ECFF), fontSize: 13, fontFamily: 'monospace'),
      );
    }
  }
}

// ── Desmos Graph ──────────────────────────────────────────────────────────────

class _DesmosView extends StatefulWidget {
  final Map<String, dynamic> data;
  const _DesmosView({required this.data});

  @override
  State<_DesmosView> createState() => _DesmosViewState();
}

class _DesmosViewState extends State<_DesmosView> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'desmos-${DateTime.now().millisecondsSinceEpoch}';
    _registerView();
  }

  void _registerView() {
    final expressions = (widget.data['expressions'] as List<dynamic>? ?? [])
        .cast<String>();
    final bounds = widget.data['bounds'] as Map<String, dynamic>?;
    final degreeMode = widget.data['degreeMode'] as bool? ?? true;

    final left = bounds?['left'] ?? -360;
    final right = bounds?['right'] ?? 360;
    final bottom = bounds?['bottom'] ?? -2;
    final top = bounds?['top'] ?? 2;

    final expJs = expressions.asMap().entries.map((e) =>
      "calc.setExpression({id:'e${e.key}', latex:'${_escapeJs(e.value)}'});"
    ).join('\n');

    final desmosHtml = '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #13111F; }
  #calc { width: 100%; height: 280px; }
</style>
<script src="https://www.desmos.com/api/v1.9/calculator.js?apiKey=dcb31709b452b1cf9dc26972add0fda6"></script>
</head>
<body>
<div id="calc"></div>
<script>
  var elt = document.getElementById('calc');
  var calc = Desmos.GraphingCalculator(elt, {
    expressionsCollapsed: true,
    settingsMenu: false,
    zoomButtons: true,
    border: false,
    keypad: false,
    expressions: false,
    invertedColors: true,
    degreeMode: ${degreeMode ? 'true' : 'false'}
  });
  calc.setMathBounds({left:$left, right:$right, bottom:$bottom, top:$top});
  $expJs
</script>
</body>
</html>''';

    ui.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      return webHtml.IFrameElement()
        ..srcdoc = desmosHtml
        ..style.width = '100%'
        ..style.height = '290px'
        ..style.border = 'none'
        ..allow = 'scripts';
    });
  }

  String _escapeJs(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 290,
          child: HtmlElementView(viewType: _viewId),
        ),
      ),
    );
  }
}

// ── Chart (fl_chart) ──────────────────────────────────────────────────────────

class _ChartView extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ChartView({required this.data});

  @override
  Widget build(BuildContext context) {
    final series = (data['series'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final xLabel = data['xLabel'] as String? ?? '';
    final yLabel = data['yLabel'] as String? ?? '';

    if (series.isEmpty) return const SizedBox.shrink();

    // Convert series to fl_chart data
    final lineBars = series.map((s) {
      final points = (s['points'] as List<dynamic>? ?? [])
          .map((p) {
            final arr = p as List<dynamic>;
            return FlSpot(
              (arr[0] as num).toDouble(),
              (arr[1] as num).toDouble(),
            );
          }).toList();
      final colorHex = (s['color'] as String? ?? '#6C63FF').replaceAll('#', '');
      final color = Color(int.parse('FF$colorHex', radix: 16));

      return LineChartBarData(
        spots: points,
        isCurved: true,
        color: color,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: color.withOpacity(0.1),
        ),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              getDrawingHorizontalLine: (v) => FlLine(color: Colors.white12, strokeWidth: 1),
              getDrawingVerticalLine: (v) => FlLine(color: Colors.white12, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                axisNameWidget: Text(xLabel, style: const TextStyle(color: Color(0xFFB0A8D0), fontSize: 11)),
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, m) => Text('${v.toInt()}', style: const TextStyle(color: Color(0xFF7B75A8), fontSize: 10)),
                  reservedSize: 24,
                ),
              ),
              leftTitles: AxisTitles(
                axisNameWidget: Text(yLabel, style: const TextStyle(color: Color(0xFFB0A8D0), fontSize: 11)),
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, m) => Text(v.toStringAsFixed(1), style: const TextStyle(color: Color(0xFF7B75A8), fontSize: 10)),
                  reservedSize: 36,
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
            ),
            lineBarsData: lineBars,
          ),
        ),
      ),
    );
  }
}
