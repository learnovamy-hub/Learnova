import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'main_shell.dart';
import 'topic_intro_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SubjectScreen extends StatefulWidget {
  const SubjectScreen({super.key});
  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  Map<String, int> _lessonCount = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final futures = kSubjects.map((s) async {
      final name = s['name'] as String;
      try {
        final r = await http.get(Uri.parse(
            '$kApiUrl/api/lessons?subject=${Uri.encodeComponent(name)}&status=published&limit=100'));
        if (r.statusCode == 200) {
          final list = jsonDecode(r.body) as List;
          if (mounted) setState(() => _lessonCount[name] = list.length);
        }
      } catch (_) {}
    });
    await Future.wait(futures);
    if (mounted) setState(() => _loading = false);
  }

  void _openSubject(String subject) {
    final shell = context.findAncestorStateOfType<MainShellState>();
    shell?.setSubject(subject);
    shell?.setState(() => shell.currentIndex = 2);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: top + 56),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Mata Pelajaran', style: TextStyle(color: kText, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('SPM · ${kSubjects.length} subjek', style: const TextStyle(color: kMuted, fontSize: 13)),
            ]),
          ),
          const Divider(color: kBorder, height: 1),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2)))
          else
            Expanded(
              child: ListView.separated(
                itemCount: kSubjects.length,
                separatorBuilder: (_, __) => const Divider(color: kBorder, height: 1, indent: 20, endIndent: 20),
                itemBuilder: (ctx, i) {
                  final s = kSubjects[i];
                  final name = s['name'] as String;
                  final color = Color(s['color'] as int);
                  final count = _lessonCount[name] ?? 0;
                  final hasLessons = count > 0;
                  return InkWell(
                    onTap: () => _openSubject(name),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasLessons ? color : kBorder,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(name,
                            style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w400)),
                        ),
                        Text(
                          hasLessons ? '$count pelajaran' : '—',
                          style: TextStyle(
                            color: hasLessons ? kMuted : kBorder,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded, color: kBorder, size: 18),
                      ]),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
