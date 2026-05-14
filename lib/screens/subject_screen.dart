import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'main_shell.dart';
import 'lesson_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SubjectScreen extends StatefulWidget {
  const SubjectScreen({super.key});
  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  String _name = '';
  String _studentId = '';
  Map<String, List<dynamic>> _lessonsBySubject = {};
  Map<String, int> _progressBySubject = {};
  bool _loading = true;
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('student_name') ?? prefs.getString('name') ?? 'Student';
    _studentId = prefs.getString('userId') ?? '';
    await Future.wait([_fetchAllLessons(), _fetchProfile()]);
    setState(() => _loading = false);
  }

  Future<void> _fetchProfile() async {
    if (_studentId.isEmpty) return;
    try {
      final r = await http.get(Uri.parse('$kApiUrl/api/student/profile?studentId=$_studentId'));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        final s = d['student'] ?? d;
        setState(() => _streak = (s['streak'] ?? s['current_streak'] ?? 0) as int);
      }
    } catch (_) {}
  }

  Future<void> _fetchAllLessons() async {
    final futures = kSubjects.map((s) async {
      final name = s['name'] as String;
      try {
        final r = await http.get(Uri.parse(
          '$kApiUrl/api/lessons?subject=${Uri.encodeComponent(name)}&status=published&limit=6'));
        if (r.statusCode == 200) {
          _lessonsBySubject[name] = jsonDecode(r.body) as List;
        }
      } catch (_) {}
    });
    await Future.wait(futures);
  }

  String get _firstName => _name.split(' ').first;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _selectSubject(String subject) {
    final shell = context.findAncestorStateOfType<MainShellState>();
    if (shell != null) {
      shell.setSubject(subject);
      shell.setState(() => shell.currentIndex = 1); // Go to AI Tutor with this subject
    }
  }

  void _openLesson(dynamic lesson) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson: lesson)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : CustomScrollView(slivers: [
              _buildHeroHeader(),
              SliverToBoxAdapter(child: _buildFeaturedSubjects()),
              SliverToBoxAdapter(child: const SizedBox(height: 12)),
              ..._buildSubjectRows(),
              SliverToBoxAdapter(child: const SizedBox(height: 100)),
            ]),
    );
  }

  Widget _buildHeroHeader() {
    return SliverToBoxAdapter(
      child: Container(
        height: 200,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E1B4B), Color(0xFF0A0A0F)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_greeting, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(_firstName, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                ])),
                if (_streak > 0) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF8C00)]),
                    borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text('$_streak day streak', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ])),
              ]),
              const SizedBox(height: 20),
              const Text('What are you studying today?',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedSubjects() {
    final featured = kSubjects.take(3).toList();
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: featured.length,
        itemBuilder: (ctx, i) {
          final s = featured[i];
          final name = s['name'] as String;
          final color = Color(s['color'] as int);
          final icon = s['icon'] as String? ?? '📚';
          final lessons = _lessonsBySubject[name] ?? [];
          return GestureDetector(
            onTap: () => _selectSubject(name),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.72,
              margin: const EdgeInsets.only(right: 12, bottom: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withOpacity(0.6), const Color(0xFF0A0A0F)],
                ),
                boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Stack(children: [
                Positioned(right: -20, top: -20,
                  child: Text(icon, style: const TextStyle(fontSize: 100))),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(i == 0 ? 'FEATURED' : 'POPULAR',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    ),
                    const SizedBox(height: 8),
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('${lessons.length} lessons available',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.play_arrow_rounded, size: 16),
                        const SizedBox(width: 4),
                        Text('Start studying', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
                      ])),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildSubjectRows() {
    return kSubjects.map((s) {
      final name = s['name'] as String;
      final color = Color(s['color'] as int);
      final icon = s['icon'] as String? ?? '📚';
      final lessons = _lessonsBySubject[name] ?? [];
      if (lessons.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
      return SliverToBoxAdapter(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(
                onTap: () => _selectSubject(name),
                child: Text('See all', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
            ]),
          ),
          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: lessons.length,
              itemBuilder: (ctx, i) {
                final lesson = lessons[i];
                final title = lesson['title'] as String? ?? lesson['topic'] as String? ?? 'Lesson';
                final form = lesson['form_level'];
                return GestureDetector(
                  onTap: () => _openLesson(lesson),
                  child: Container(
                    width: 160,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color.withOpacity(0.25)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                          child: Center(child: Text('${i + 1}', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)))),
                        const Spacer(),
                        if (form != null) Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text('F$form', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800))),
                      ]),
                      const Spacer(),
                      Text(title,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, height: 1.3),
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      );
    }).toList();
  }
}
