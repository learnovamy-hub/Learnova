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
  String _name = '';
  String _studentId = '';
  Map<String, List<dynamic>> _lessonsBySubject = {};
  Map<String, int> _progressBySubject = {};
  bool _loading = true;
  int _streak = 0;
  int _formLevel = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('student_name') ?? prefs.getString('name') ?? '';
    _studentId = prefs.getString('userId') ?? prefs.getString('student_id') ?? '';

    // Detect form level — Form 1-3 = PT3 (content not yet uploaded)
    final formStr = prefs.getString('student_form_$_studentId') ?? prefs.getString('student_form') ?? '';
    if (formStr.isNotEmpty) {
      _formLevel = int.tryParse(formStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    }

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
      shell.setState(() => shell.currentIndex = 2); // Go to AI Tutor with this subject
    }
  }

  void _openLesson(dynamic lesson, [String? subject]) {
    final topic = lesson['topic']?.toString() ?? lesson['title']?.toString() ?? '';
    final subjName = subject ?? '';
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TopicIntroScreen(
        subject: subjName,
        topic: topic,
        lessonData: Map<String, dynamic>.from(lesson as Map),
        onStartAiTutor: () {
          Navigator.of(context).pop();
          context.findAncestorStateOfType<MainShellState>()?.startTopicWithPreRead(subjName, topic);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _formLevel > 0 && _formLevel <= 3
              ? _buildPT3Notice()
              : CustomScrollView(slivers: [
                  _buildHeroHeader(),
                  SliverToBoxAdapter(child: _buildFeaturedSubjects()),
                  SliverToBoxAdapter(child: const SizedBox(height: 12)),
                  ..._buildSubjectRows(),
                  SliverToBoxAdapter(child: const SizedBox(height: 100)),
                ]),
    );
  }

  Widget _buildPT3Notice() {
    return CustomScrollView(slivers: [
      _buildHeroHeader(),
      SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // Animated construction icon
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF59E0B).withOpacity(0.12),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.35), width: 2),
              ),
              child: const Icon(Icons.construction_rounded, color: Color(0xFFF59E0B), size: 48),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
              ),
              child: Text('PT3 · Form $_formLevel',
                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
            const SizedBox(height: 16),
            const Text('Bilik Darjah Sedang Disediakan',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.2)),
            const SizedBox(height: 14),
            const Text(
              'Kami sedang menyediakan modul pelajaran PT3 yang lengkap dan berkualiti untuk Form 1–3.\n\nSemak semula tidak lama lagi — kandungan akan dimuatkan dalam masa terdekat!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.7),
            ),
            const SizedBox(height: 36),
            // Students can still use AI Tutor
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPrimary.withOpacity(0.25)),
              ),
              child: Column(children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: kPrimary.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 20)),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('AI Tutor Masih Tersedia', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('Tanya apa-apa soalan PT3 kepada AI', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                  ])),
                ]),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: () {
                    final shell = context.findAncestorStateOfType<MainShellState>();
                    if (shell != null) shell.setState(() => shell.currentIndex = 2);
                  },
                  icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                  label: const Text('Buka AI Tutor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )),
              ]),
            ),
            const SizedBox(height: 100),
          ]),
        ),
      ),
    ]);
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
                  onTap: () => _openLesson(lesson, name),
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
