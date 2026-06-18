import 'package:flutter/material.dart';
import '../config/constants.dart';
import 'quizzes_tab.dart';

class QuizSubjectSelectorScreen extends StatelessWidget {
  final List<String> activeSubjects;
  const QuizSubjectSelectorScreen({super.key, required this.activeSubjects});

  static const _keyToName = {
    'MY-Mathematics': 'Mathematics', 'MY-AddMaths': 'Add Maths',
    'MY-Physics': 'Physics',         'MY-Biology': 'Biology',
    'MY-Chemistry': 'Chemistry',     'MY-Sejarah': 'Sejarah',
    'MY-BahasaMalaysia': 'Bahasa Malaysia', 'MY-English': 'English',
    'AL-Mathematics': 'A-Level Math','AL-Physics': 'A-Level Physics',
    'AL-Chemistry': 'A-Level Chem',  'AL-Biology': 'A-Level Bio',
  };

  static const _keyToIcon = {
    'MY-Mathematics': Icons.functions_rounded,
    'MY-AddMaths': Icons.calculate_rounded,
    'MY-Physics': Icons.science_rounded,
    'MY-Biology': Icons.biotech_rounded,
    'MY-Chemistry': Icons.bubble_chart_rounded,
    'MY-Sejarah': Icons.history_edu_rounded,
    'MY-BahasaMalaysia': Icons.translate_rounded,
    'MY-English': Icons.menu_book_rounded,
    'AL-Mathematics': Icons.functions_rounded,
    'AL-Physics': Icons.science_rounded,
    'AL-Chemistry': Icons.bubble_chart_rounded,
    'AL-Biology': Icons.biotech_rounded,
  };

  String _displayName(String key) =>
      _keyToName[key] ?? key.replaceFirst('MY-', '').replaceFirst('AL-', '');

  IconData _icon(String key) =>
      _keyToIcon[key] ?? Icons.menu_book_rounded;

  Color _subjectColor(String key) {
    const nameToKey = {
      'Mathematics': 'MY-Mathematics', 'Add Maths': 'MY-AddMaths',
      'Physics': 'MY-Physics',         'Biology': 'MY-Biology',
      'Chemistry': 'MY-Chemistry',     'Sejarah': 'MY-Sejarah',
      'Bahasa Malaysia': 'MY-BahasaMalaysia', 'English': 'MY-English',
    };
    final name = _displayName(key);
    final mapped = nameToKey[name] ?? key;
    for (final s in kSubjects) {
      final k = nameToKey[s['name'] as String] ?? '';
      if (k == mapped) return Color(s['color'] as int);
    }
    return kPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final _raw = activeSubjects.isEmpty
        ? ['MY-BahasaMalaysia', 'MY-English']
        : activeSubjects;
    // Deduplicate by display name — keeps first occurrence of each name
    final _seen = <String>{};
    final subjects = _raw.where((k) => _seen.add(_displayName(k))).toList();

    return Scaffold(
      backgroundColor: kBg,
      body: Column(children: [
        SizedBox(
          height: top + 64,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: kMuted, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              const Text('Pilih Subjek Quiz',
                style: TextStyle(
                  color: kText,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            itemCount: subjects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final key   = subjects[i];
              final name  = _displayName(key);
              final color = _subjectColor(key);
              final icon  = _icon(key);
              return GestureDetector(
                onTap: () => Navigator.push(ctx, MaterialPageRoute(
                  builder: (_) => QuizzesTab(selectedSubject: name),
                )),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(name,
                        style: const TextStyle(
                          color: kText,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: kMuted, size: 20),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
