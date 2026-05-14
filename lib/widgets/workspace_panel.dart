// lib/widgets/workspace_panel.dart
// Student workspace — draw (finger/stylus) or type mode with symbol bar
// Drop into lib/widgets/ folder

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

class WorkspaceResult {
  final String mode;          // 'typed' | 'drawn'
  final String? typedAnswer;
  final String? imageBase64;
  WorkspaceResult({required this.mode, this.typedAnswer, this.imageBase64});
}

// ─── Draw stroke ──────────────────────────────────────────────────────────────

class DrawStroke {
  final List<Offset> points;
  final Color color;
  final double width;
  DrawStroke({required this.points, required this.color, required this.width});
}

// ─── Main Widget ──────────────────────────────────────────────────────────────

class WorkspacePanel extends StatefulWidget {
  final String subject;
  final String question;
  final String initialMode;          // 'type' | 'draw'
  final bool isSubmitting;
  final bool embedded;               // true = inline (no handle, rounded, no shadow)
  final void Function(WorkspaceResult) onSubmit;
  final VoidCallback? onClose;

  const WorkspacePanel({
    Key? key,
    required this.subject,
    required this.question,
    required this.onSubmit,
    this.initialMode = 'type',
    this.isSubmitting = false,
    this.embedded = false,
    this.onClose,
  }) : super(key: key);

  @override
  State<WorkspacePanel> createState() => _WorkspacePanelState();
}

class _WorkspacePanelState extends State<WorkspacePanel>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;
  late TextEditingController _textController;
  final GlobalKey _canvasKey = GlobalKey();

  // Draw state
  final List<DrawStroke> _strokes = [];
  List<Offset> _currentStroke = [];
  Color _penColor = Colors.black;
  double _penWidth = 3.0;
  bool _isEraser = false;

  // Math symbol bar
  static const List<String> _mathSymbols = [
    'x²', '√', '÷', '×', 'π', '≤', '≥', '≠', '∞', '±', '∫', 'Δ',
  ];

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialMode == 'draw' ? 1 : 0;
    _tabController = TabController(length: 2, vsync: this, initialIndex: initialIndex);
    _textController = TextEditingController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  bool get _isMathSubject {
    final s = widget.subject.toLowerCase();
    return s.contains('math') || s.contains('physic') || s.contains('chem');
  }

  // ─── Draw helpers ──────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    setState(() {
      _currentStroke = [d.localPosition];
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      _currentStroke.add(d.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    setState(() {
      _strokes.add(DrawStroke(
        points: List.from(_currentStroke),
        color: _isEraser ? Colors.white : _penColor,
        width: _isEraser ? 20.0 : _penWidth,
      ));
      _currentStroke = [];
    });
  }

  void _clearCanvas() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
    });
  }

  Future<String?> _canvasToBase64() async {
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      return base64Encode(bytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('Canvas export error: $e');
      return null;
    }
  }

  // ─── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_tabController.index == 0) {
      // Typed mode
      final answer = _textController.text.trim();
      if (answer.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please write your answer first.')),
        );
        return;
      }
      widget.onSubmit(WorkspaceResult(mode: 'typed', typedAnswer: answer));
    } else {
      // Draw mode
      if (_strokes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please draw your working first.')),
        );
        return;
      }
      final base64 = await _canvasToBase64();
      widget.onSubmit(WorkspaceResult(mode: 'drawn', imageBase64: base64));
    }
  }

  // ─── Symbol insertion ──────────────────────────────────────────────────────

  void _insertSymbol(String symbol) {
    final symbolMap = {
      'x²': '²', '√': '√', '÷': '÷', '×': '×', 'π': 'π',
      '≤': '≤', '≥': '≥', '≠': '≠', '∞': '∞', '±': '±',
      '∫': '∫', 'Δ': 'Δ',
    };
    final insert = symbolMap[symbol] ?? symbol;
    final text = _textController.text;
    final sel = _textController.selection;
    final newText = text.replaceRange(
      sel.start < 0 ? text.length : sel.start,
      sel.end < 0 ? text.length : sel.end,
      insert,
    );
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: (sel.start < 0 ? text.length : sel.start) + insert.length,
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: widget.embedded
            ? BorderRadius.circular(12)
            : const BorderRadius.vertical(top: Radius.circular(20)),
        border: widget.embedded
            ? Border.all(color: const Color(0xFFE2E8F0))
            : null,
        boxShadow: widget.embedded
            ? null
            : [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Column(
        children: [
          // ── Handle bar (bottom-sheet mode only)
          if (!widget.embedded) _buildHandle(),

          // ── Header (embedded mode) or question chip (sheet mode)
          if (widget.embedded)
            _buildEmbeddedHeader()
          else if (widget.question.isNotEmpty)
            _buildQuestionChip(),

          // ── Mode tabs
          _buildTabs(),

          // ── Content (type / draw)
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTypeMode(),
                _buildDrawMode(),
              ],
            ),
          ),

          // ── Action bar
          _buildActionBar(),

          if (!widget.embedded)
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  // Compact header for embedded mode
  Widget _buildEmbeddedHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 4),
      child: Row(children: [
        const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF6366F1)),
        const SizedBox(width: 6),
        const Expanded(
          child: Text('My Working',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: Color(0xFF374151))),
        ),
        if (widget.question.isNotEmpty)
          Flexible(
            child: Text(widget.question,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ),
        if (widget.onClose != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: widget.onClose,
            child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF))),
        ],
      ]),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Spacer(),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Spacer(),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onClose,
              padding: const EdgeInsets.only(right: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionChip() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBD6F8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.help_outline, size: 16, color: Color(0xFF2196F3)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.question,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1565C0),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFF1E88E5),
          borderRadius: BorderRadius.circular(10),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        tabs: const [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.keyboard, size: 16),
                SizedBox(width: 6),
                Text('Type', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.draw, size: 16),
                SizedBox(width: 6),
                Text('Draw', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Type mode ────────────────────────────────────────────────────────────────

  Widget _buildTypeMode() {
    return Column(
      children: [
        // Symbol bar (math subjects only)
        if (_isMathSubject) _buildSymbolBar(),

        // Text field
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 15, height: 1.5),
              decoration: const InputDecoration(
                hintText: 'Type your answer or working here...',
                hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSymbolBar() {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _mathSymbols.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final sym = _mathSymbols[i];
          return InkWell(
            onTap: () => _insertSymbol(sym),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF90CAF9)),
              ),
              child: Text(
                sym,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1565C0),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Draw mode ─────────────────────────────────────────────────────────────────

  Widget _buildDrawMode() {
    return Column(
      children: [
        // Toolbar
        _buildDrawToolbar(),

        // Canvas
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RepaintBoundary(
                key: _canvasKey,
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    painter: _DrawingPainter(
                      strokes: _strokes,
                      currentStroke: _currentStroke,
                      currentColor: _isEraser ? Colors.white : _penColor,
                      currentWidth: _isEraser ? 20.0 : _penWidth,
                    ),
                    child: Container(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrawToolbar() {
    final colors = [Colors.black, Colors.blue, Colors.red, const Color(0xFF2E7D32)];
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Color dots
          ...colors.map((c) => GestureDetector(
            onTap: () => setState(() { _penColor = c; _isEraser = false; }),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _penColor == c && !_isEraser
                      ? const Color(0xFF1E88E5)
                      : Colors.grey.shade300,
                  width: _penColor == c && !_isEraser ? 2.5 : 1,
                ),
              ),
            ),
          )),

          const SizedBox(width: 8),

          // Pen size
          _toolBtn(
            icon: Icons.edit,
            label: 'Thin',
            active: _penWidth == 2.0 && !_isEraser,
            onTap: () => setState(() { _penWidth = 2.0; _isEraser = false; }),
          ),
          _toolBtn(
            icon: Icons.edit,
            label: 'Thick',
            active: _penWidth == 5.0 && !_isEraser,
            onTap: () => setState(() { _penWidth = 5.0; _isEraser = false; }),
          ),

          const SizedBox(width: 4),

          // Eraser
          _toolBtn(
            icon: Icons.auto_fix_high,
            label: 'Erase',
            active: _isEraser,
            onTap: () => setState(() => _isEraser = !_isEraser),
          ),

          const Spacer(),

          // Undo
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            tooltip: 'Undo',
            onPressed: _strokes.isEmpty ? null : () {
              setState(() => _strokes.removeLast());
            },
          ),

          // Clear
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Clear all',
            onPressed: _strokes.isEmpty ? null : _clearCanvas,
          ),
        ],
      ),
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE3F2FD) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? const Color(0xFF1E88E5) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? const Color(0xFF1E88E5) : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: active ? const Color(0xFF1E88E5) : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Action bar ───────────────────────────────────────────────────────────────

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Clear typed / canvas
          OutlinedButton.icon(
            onPressed: () {
              if (_tabController.index == 0) {
                _textController.clear();
              } else {
                _clearCanvas();
              }
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Clear'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),

          const Spacer(),

          // Submit
          ElevatedButton.icon(
            onPressed: widget.isSubmitting ? null : _submit,
            icon: widget.isSubmitting
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(widget.isSubmitting
                ? 'Sending...'
                : widget.embedded ? 'Send to Tutor' : 'Submit Answer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _DrawingPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final List<Offset> currentStroke;
  final Color currentColor;
  final double currentWidth;

  _DrawingPainter({
    required this.strokes,
    required this.currentStroke,
    required this.currentColor,
    required this.currentWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw existing strokes
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      _drawStroke(canvas, stroke.points, paint);
    }

    // Draw current stroke
    if (currentStroke.length > 1) {
      final paint = Paint()
        ..color = currentColor
        ..strokeWidth = currentWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      _drawStroke(canvas, currentStroke, paint);
    }
  }

  void _drawStroke(Canvas canvas, List<Offset> points, Paint paint) {
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      // Smooth curve through points
      if (i < points.length - 1) {
        final mid = Offset(
          (points[i].dx + points[i + 1].dx) / 2,
          (points[i].dy + points[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(
          points[i].dx, points[i].dy,
          mid.dx, mid.dy,
        );
      } else {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DrawingPainter old) => true;
}
