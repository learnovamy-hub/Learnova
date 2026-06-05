// lib/widgets/mistake_card.dart
// Renders Mistake Intelligence Layer response in the tutor chat
// Shown when student answers wrong — replaces generic "incorrect" message
// Drop into lib/widgets/

import 'package:flutter/material.dart';

class MistakeCard extends StatefulWidget {
  final String mistakeLabel;
  final String tutorResponse;        // Claude-generated human-tutor message
  final String whyItHappens;
  final String fixStrategy;
  final bool isRecurring;
  final int occurrenceCount;
  final String frequencyEmoji;
  final String frequencyLabel;
  final String? patternAlert;        // shown if recurring
  final int attempt;                 // 1 or 2
  final VoidCallback onTryAgain;
  final VoidCallback? onSkip;

  const MistakeCard({
    Key? key,
    required this.mistakeLabel,
    required this.tutorResponse,
    required this.whyItHappens,
    required this.fixStrategy,
    required this.isRecurring,
    required this.occurrenceCount,
    required this.frequencyEmoji,
    required this.frequencyLabel,
    this.patternAlert,
    required this.attempt,
    required this.onTryAgain,
    this.onSkip,
  }) : super(key: key);

  @override
  State<MistakeCard> createState() => _MistakeCardState();
}

class _MistakeCardState extends State<MistakeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slideAnim;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _cardColor => widget.isRecurring
      ? const Color(0xFFFFF3E0)   // amber tint for recurring
      : const Color(0xFFFCE4EC);  // light red for first-time

  Color get _accentColor => widget.isRecurring
      ? const Color(0xFFE65100)
      : const Color(0xFFC62828);

  Color get _headerColor => widget.isRecurring
      ? const Color(0xFFFF6F00)
      : const Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnim,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accentColor.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _accentColor.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _buildHeader(),

            // ── Recurring pattern alert ──────────────────────────────────────
            if (widget.isRecurring && widget.patternAlert != null)
              _buildPatternAlert(),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Tutor response (main message) ────────────────────────
                  _buildTutorMessage(),

                  const SizedBox(height: 12),

                  // ── Expandable "Why this happens" + Fix ──────────────────
                  _buildExpandable(),

                  const SizedBox(height: 14),

                  // ── Attempt indicator ────────────────────────────────────
                  _buildAttemptIndicator(),

                  const SizedBox(height: 14),

                  // ── Action buttons ───────────────────────────────────────
                  _buildActions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _headerColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
      ),
      child: Row(
        children: [
          Text(
            widget.frequencyEmoji,
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mistakeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${widget.frequencyLabel} · Occurrence #${widget.occurrenceCount}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Attempt badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Attempt ${widget.attempt}/2',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatternAlert() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6F00).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF6F00).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_up, size: 16, color: Color(0xFFE65100)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.patternAlert!,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFE65100),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorMessage() {
    // Render the tutor response with bold support (**text**)
    final spans = <TextSpan>[];
    final parts = widget.tutorResponse.split('**');
    for (int i = 0; i < parts.length; i++) {
      spans.add(TextSpan(
        text: parts[i],
        style: TextStyle(
          fontWeight: i.isOdd ? FontWeight.w700 : FontWeight.normal,
          fontSize: 14,
          height: 1.55,
          color: const Color(0xFF212121),
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 14,
            backgroundColor: Color(0xFF1565C0),
            child: Text('AI', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(child: RichText(text: TextSpan(children: spans))),
        ],
      ),
    );
  }

  Widget _buildExpandable() {
    return InkWell(
      onTap: () => setState(() => _showDetails = !_showDetails),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _showDetails ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: _accentColor,
              ),
              const SizedBox(width: 4),
              Text(
                _showDetails ? 'Hide details' : 'Why does this happen? + How to fix',
                style: TextStyle(
                  fontSize: 12,
                  color: _accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          if (_showDetails) ...[
            const SizedBox(height: 10),

            // Why it happens
            _detailSection(
              icon: Icons.psychology_outlined,
              title: 'Why this usually happens',
              content: widget.whyItHappens,
              color: const Color(0xFF5C6BC0),
            ),

            const SizedBox(height: 10),

            // Fix strategy
            _detailSection(
              icon: Icons.build_circle_outlined,
              title: 'How to fix it going forward',
              content: widget.fixStrategy,
              color: const Color(0xFF2E7D32),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailSection({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF424242),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttemptIndicator() {
    return Row(
      children: [
        // Attempt dots
        ...List.generate(2, (i) => Container(
          margin: const EdgeInsets.only(right: 6),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < widget.attempt
                ? _accentColor
                : Colors.grey.shade300,
          ),
        )),
        const SizedBox(width: 6),
        Text(
          widget.attempt == 1
              ? 'Have another look — 1 attempt remaining'
              : 'That was your last attempt — check the solution above',
          style: TextStyle(
            fontSize: 11,
            color: _accentColor.withOpacity(0.8),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        if (widget.attempt < 2) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: widget.onTryAgain,
              icon: const Text('💪', style: TextStyle(fontSize: 16)),
              label: const Text(
                'Try Again',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _headerColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                elevation: 0,
              ),
            ),
          ),
          if (widget.onSkip != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onSkip,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ] else ...[
          // After 2nd attempt — show next steps
          Expanded(
            child: ElevatedButton.icon(
              onPressed: widget.onSkip ?? widget.onTryAgain,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Continue Lesson', style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                elevation: 0,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Recurring Mistake Badge (for home/profile tab) ───────────────────────────
// Small chip shown on topic cards when student has recurring mistakes on that topic

class RecurringMistakeBadge extends StatelessWidget {
  final String mistakeLabel;
  final int count;
  final String severity;   // 'high' | 'medium'

  const RecurringMistakeBadge({
    Key? key,
    required this.mistakeLabel,
    required this.count,
    required this.severity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = severity == 'high'
        ? const Color(0xFFD32F2F)
        : const Color(0xFFE65100);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$mistakeLabel ($count×)',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
