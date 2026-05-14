// lib/widgets/standards_badge.dart
// Shows current learning standard progress in the tutor UI
// Usage: StandardsBadge(code: '2.1.1', desc: 'Solve quadratic...', progress: '3 of 6')

import 'package:flutter/material.dart';

class StandardsBadge extends StatelessWidget {
  final String? code;
  final String? desc;
  final String? progress;

  const StandardsBadge({Key? key, this.code, this.desc, this.progress}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (code == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF81C784)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '📌 $code',
              style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              desc ?? '',
              style: const TextStyle(fontSize: 11, color: Color(0xFF1B5E20)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(width: 8),
            Text(
              progress!,
              style: const TextStyle(
                fontSize: 10, color: Color(0xFF388E3C), fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
