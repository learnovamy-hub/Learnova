// lib/widgets/checkin_card.dart
// Mid-topic and end-topic check-in card shown in tutor chat
// Drop into lib/widgets/ folder

import 'package:flutter/material.dart';

class CheckinCard extends StatelessWidget {
  final String message;
  final void Function(bool wantsQuiz) onResponse;

  const CheckinCard({
    Key? key,
    required this.message,
    required this.onResponse,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E88E5).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.quiz, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Check-in',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => onResponse(true),
                    icon: const Text('💪', style: TextStyle(fontSize: 16)),
                    label: const Text(
                      'Yes, test me!',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1565C0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onResponse(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'Not yet',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── MCQ Quiz Card ────────────────────────────────────────────────────────────

class QuizCard extends StatefulWidget {
  final String question;
  final Map<String, String> options;   // { A: "...", B: "...", C: "...", D: "..." }
  final int attemptNumber;             // 1 or 2
  final void Function(String answer) onAnswer;

  const QuizCard({
    Key? key,
    required this.question,
    required this.options,
    required this.attemptNumber,
    required this.onAnswer,
  }) : super(key: key);

  @override
  State<QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<QuizCard> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFCC02), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFCC02).withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFCC02),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Attempt ${widget.attemptNumber}/2',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5D4037),
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF795548)),
              ],
            ),

            const SizedBox(height: 12),

            // Question
            Text(
              widget.question,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: Color(0xFF212121),
              ),
            ),

            const SizedBox(height: 14),

            // Options
            ...widget.options.entries.map((e) => _buildOption(e.key, e.value)),

            const SizedBox(height: 12),

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected == null
                    ? null
                    : () => widget.onAnswer(_selected!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFCC02),
                  foregroundColor: const Color(0xFF5D4037),
                  disabledBackgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                ),
                child: Text(
                  _selected == null ? 'Select an answer' : 'Confirm Answer $_selected',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(String key, String value) {
    final isSelected = _selected == key;
    return GestureDetector(
      onTap: () => setState(() => _selected = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1565C0) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF1565C0) : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.2) : const Color(0xFFF0F7FF),
                shape: BoxShape.circle,
              ),
              child: Text(
                key,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : const Color(0xFF1565C0),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: isSelected ? Colors.white : const Color(0xFF212121),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Timing Warning Banner ────────────────────────────────────────────────────

class TimingWarningBanner extends StatelessWidget {
  final String message;
  final bool isFinal;

  const TimingWarningBanner({
    Key? key,
    required this.message,
    this.isFinal = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isFinal ? const Color(0xFFFCE4EC) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFinal ? const Color(0xFFE91E63) : const Color(0xFFFF9800),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFinal ? Icons.access_alarm : Icons.timer_outlined,
            color: isFinal ? const Color(0xFFC62828) : const Color(0xFFE65100),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isFinal ? const Color(0xFFC62828) : const Color(0xFFE65100),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
