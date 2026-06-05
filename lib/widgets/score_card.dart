// lib/widgets/score_card.dart
// Displays assessment results after workspace submission
// Drop into lib/widgets/ folder

import 'package:flutter/material.dart';

class ScoreCard extends StatefulWidget {
  final int score;
  final int maxMarks;
  final String grade;
  final List<String> strengths;
  final List<String> mistakes;
  final String correctWorking;
  final String encouragement;
  final VoidCallback onTryAgain;
  final VoidCallback onContinue;

  const ScoreCard({
    Key? key,
    required this.score,
    required this.maxMarks,
    required this.grade,
    required this.strengths,
    required this.mistakes,
    required this.correctWorking,
    required this.encouragement,
    required this.onTryAgain,
    required this.onContinue,
  }) : super(key: key);

  @override
  State<ScoreCard> createState() => _ScoreCardState();
}

class _ScoreCardState extends State<ScoreCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  bool _showWorking = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnim  = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _gradeColor {
    switch (widget.grade) {
      case 'Excellent': return const Color(0xFF2E7D32);
      case 'Good':      return const Color(0xFF1565C0);
      case 'Partial':   return const Color(0xFFE65100);
      default:          return const Color(0xFFC62828);
    }
  }

  String get _gradeEmoji {
    switch (widget.grade) {
      case 'Excellent': return '🌟';
      case 'Good':      return '✅';
      case 'Partial':   return '📝';
      default:          return '💪';
    }
  }

  @override
  Widget build(BuildContext context) {
    final percentage = (widget.score / widget.maxMarks * 100).round();

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _gradeColor.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Score header
            _buildScoreHeader(percentage),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Star rating
                  _buildStarRating(),

                  const SizedBox(height: 16),

                  // ── Encouragement
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _gradeColor.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.encouragement,
                      style: TextStyle(
                        fontSize: 14,
                        color: _gradeColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Strengths
                  if (widget.strengths.isNotEmpty) ...[
                    _sectionHeader('What you did well', Icons.check_circle, const Color(0xFF2E7D32)),
                    ...widget.strengths.map((s) => _bulletItem(s, const Color(0xFF2E7D32), Icons.check)),
                    const SizedBox(height: 12),
                  ],

                  // ── Mistakes
                  if (widget.mistakes.isNotEmpty) ...[
                    _sectionHeader('Areas to improve', Icons.info_outline, const Color(0xFFE65100)),
                    ...widget.mistakes.map((m) => _bulletItem(m, const Color(0xFFE65100), Icons.close)),
                    const SizedBox(height: 12),
                  ],

                  // ── Model answer toggle
                  InkWell(
                    onTap: () => setState(() => _showWorking = !_showWorking),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E5F5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCE93D8)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFF7B1FA2)),
                          const SizedBox(width: 8),
                          const Text(
                            'Model Answer / Worked Solution',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7B1FA2),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _showWorking ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: const Color(0xFF7B1FA2),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_showWorking) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: SelectableText(
                        widget.correctWorking,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // ── Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onTryAgain,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Try Again'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1565C0),
                            side: const BorderSide(color: Color(0xFF1565C0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.onContinue,
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('Continue'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gradeColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreHeader(int percentage) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _gradeColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Text(
              _gradeEmoji,
              style: const TextStyle(fontSize: 40),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.score} / ${widget.maxMarks}',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              '${percentage}% — ${widget.grade}',
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRating() {
    final filled = (widget.score / widget.maxMarks * 4).round().clamp(0, 4);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) => Icon(
          i < filled ? Icons.star : Icons.star_border,
          color: i < filled ? Colors.amber : Colors.grey.shade300,
          size: 28,
        )),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletItem(String text, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
