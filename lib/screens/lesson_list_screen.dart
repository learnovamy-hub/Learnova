import 'package:flutter/material.dart';
import '../config/constants.dart';
import 'lesson_screen.dart';

class LessonListScreen extends StatefulWidget {
  final String topic;
  final List<Map<String, dynamic>> lessons;
  final String subjectKey;
  final String subjectName;
  final Color  subjectColor;
  final Map<String, Map<String, dynamic>> progress;
  const LessonListScreen({
    super.key,
    required this.topic,
    required this.lessons,
    required this.subjectKey,
    required this.subjectName,
    required this.subjectColor,
    required this.progress,
  });
  @override
  State<LessonListScreen> createState() => _LessonListScreenState();
}

class _LessonListScreenState extends State<LessonListScreen> {
  late Map<String, Map<String, dynamic>> _progress;

  @override
  void initState() {
    super.initState();
    _progress = Map.from(widget.progress);
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = widget.lessons.where((l) {
      final p = _progress[l['id'] as String?];
      return p?['status'] == 'completed';
    }).length;
    final allLessonsDone = completedCount == widget.lessons.length && widget.lessons.isNotEmpty;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        foregroundColor: kText,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.topic,
            style: const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
          Text(widget.subjectName,
            style: const TextStyle(color: kMuted, fontSize: 11)),
        ]),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: kBorder, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Progress summary
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.subjectColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.subjectColor.withOpacity(0.2)),
            ),
            child: Row(children: [
              Icon(Icons.auto_stories_outlined, color: widget.subjectColor, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(
                '$completedCount daripada ${widget.lessons.length} pelajaran selesai',
                style: TextStyle(color: widget.subjectColor, fontSize: 13, fontWeight: FontWeight.w600),
              )),
            ]),
          ),
          const SizedBox(height: 16),

          // Lesson rows
          ...widget.lessons.asMap().entries.map((entry) {
            return _buildLessonRow(entry.value, entry.key);
          }),

          // Mastery Quiz row
          const SizedBox(height: 8),
          _buildQuizRow(allLessonsDone),
        ],
      ),
    );
  }

  Widget _buildLessonRow(Map<String, dynamic> lesson, int index) {
    final id     = lesson['id'] as String? ?? '';
    final lesNum = (lesson['lesson_number'] as int?) ?? (index + 1);
    final title  = lesson['lesson_title'] as String? ?? '';
    final mins   = (lesson['estimated_minutes'] as int?) ?? 15;
    final diff   = lesson['difficulty'] as String? ?? 'medium';

    final prog      = _progress[id];
    final status    = prog?['status'] as String? ?? 'not_started';
    final isCompleted  = status == 'completed';
    final isInProgress = status == 'in_progress';

    Color statusColor;
    IconData statusIcon;
    if (isCompleted) {
      statusColor = kGreen;
      statusIcon  = Icons.check_circle_rounded;
    } else if (isInProgress) {
      statusColor = kYellow;
      statusIcon  = Icons.play_circle_outline_rounded;
    } else {
      statusColor = kBorder;
      statusIcon  = Icons.radio_button_unchecked_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final result = await Navigator.push(context, MaterialPageRoute(
              builder: (_) => LessonScreen(lessonId: id, subject: widget.subjectKey),
            ));
            if (result == true && mounted) {
              // Update local progress state to show completion immediately
              setState(() {
                _progress[id] = {'lesson_id': id, 'status': 'completed'};
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isCompleted ? kGreen.withOpacity(0.3) : kBorder),
            ),
            child: Row(children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$lesNum. $title',
                  style: TextStyle(
                    color: isCompleted ? kMuted : kText,
                    fontSize: 14, fontWeight: FontWeight.w500,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                  )),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.timer_outlined, size: 12, color: kBorder),
                  const SizedBox(width: 4),
                  Text('~$mins min', style: const TextStyle(color: kBorder, fontSize: 11)),
                  const SizedBox(width: 10),
                  _diffChip(diff),
                ]),
              ])),
              Icon(Icons.chevron_right_rounded, color: kBorder, size: 18),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildQuizRow(bool unlocked) {
    return Opacity(
      opacity: unlocked ? 1.0 : 0.45,
      child: Material(
        color: unlocked ? kPrimary.withOpacity(0.08) : kSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: unlocked ? () {
            // TODO: navigate to quiz screen for this topic
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Kuiz akan tersedia tidak lama lagi!'), backgroundColor: kPrimary),
            );
          } : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: unlocked ? kPrimary.withOpacity(0.3) : kBorder),
            ),
            child: Row(children: [
              Icon(
                unlocked ? Icons.quiz_rounded : Icons.lock_outline_rounded,
                color: unlocked ? kPrimary : kBorder,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Kuiz Penguasaan',
                  style: TextStyle(
                    color: unlocked ? kPrimary : kMuted,
                    fontSize: 14, fontWeight: FontWeight.w600,
                  )),
                const SizedBox(height: 2),
                Text(
                  unlocked
                    ? 'Uji kefahaman kamu untuk topik ini'
                    : 'Selesaikan semua pelajaran untuk buka kuiz ini',
                  style: const TextStyle(color: kBorder, fontSize: 11),
                ),
              ])),
              if (unlocked)
                Icon(Icons.chevron_right_rounded, color: kPrimary.withOpacity(0.6), size: 18),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _diffChip(String diff) {
    final color = diff == 'easy'
        ? kGreen
        : diff == 'hard'
            ? kRed
            : kYellow;
    final label = diff == 'easy' ? 'Mudah' : diff == 'hard' ? 'Sukar' : 'Sederhana';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10)),
    );
  }
}
