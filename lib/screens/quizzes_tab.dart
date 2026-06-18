import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';
import 'main_shell.dart';
import 'quiz_screen.dart';

class QuizzesTab extends StatefulWidget {
  final String selectedSubject;
  const QuizzesTab({super.key, required this.selectedSubject});
  @override
  State<QuizzesTab> createState() => _QuizzesTabState();
}

class _QuizzesTabState extends State<QuizzesTab> {
  static const _qbSubjectMap = {
    'Matematik': 'Mathematics',
    'Biologi':   'Biology',
    'Kimia':     'Chemistry',
    'Fizik':     'Physics',
  };

  List<dynamic> _quizzes = [];
  bool _loading = true;
  String _currentSubject = 'Mathematics';

  @override
  void initState() {
    super.initState();
    _currentSubject = widget.selectedSubject;
    _load();
  }

  @override
  void didUpdateWidget(QuizzesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubject != widget.selectedSubject) {
      setState(() => _currentSubject = widget.selectedSubject);
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final qbSubject = _qbSubjectMap[_currentSubject] ?? _currentSubject;
      final r = await http.get(Uri.parse('$kApiUrl/api/quizzes/list/${Uri.encodeComponent(qbSubject)}'));
      if (r.statusCode == 200) setState(() => _quizzes = jsonDecode(r.body));
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: Text('Quizzes – $_currentSubject')),
      body: Column(children: [
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SubjectSelector(
            selected: _currentSubject,
            onChanged: (s) {
              setState(() => _currentSubject = s);
              _load();
              context.findAncestorStateOfType<MainShellState>()?.setSubject(s);
            },
          ),
        ),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : _quizzes.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.quiz_outlined, color: kMuted, size: 60),
                    const SizedBox(height: 16),
                    const Text('No quizzes yet', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('No $_currentSubject quizzes published yet', style: const TextStyle(color: kMuted, fontSize: 13)),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _quizzes.length,
                    itemBuilder: (ctx, i) {
                      final q = _quizzes[i];
                      final diff = q['difficulty'] ?? 'medium';
                      final diffColor = diff == 'easy' ? kGreen : diff == 'hard' ? kRed : kYellow;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: kGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.quiz_rounded, color: kGreen, size: 24)),
                          title: Text(q['title'] ?? 'Quiz', style: const TextStyle(color: kText, fontWeight: FontWeight.w700)),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const SizedBox(height: 4),
                            Text(q['topic'] ?? '', style: const TextStyle(color: kMuted, fontSize: 12)),
                            const SizedBox(height: 6),
                            Row(children: [
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: diffColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Text(diff, style: TextStyle(color: diffColor, fontSize: 11, fontWeight: FontWeight.w700))),
                              const SizedBox(width: 8),
                              Text('${q['total_questions'] ?? 0} questions', style: const TextStyle(color: kMuted, fontSize: 11)),
                            ]),
                          ]),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: kMuted, size: 14),
                          onTap: () {
                            final qbSubject = _qbSubjectMap[_currentSubject] ?? _currentSubject;
                            Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(subject: qbSubject, topic: q['topic'] as String)));
                          },
                        ),
                      );
                    },
                  )),
      ]),
    );
  }
}


