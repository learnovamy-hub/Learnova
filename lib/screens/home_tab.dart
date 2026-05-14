import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'lesson_screen.dart';
import 'main_shell.dart';

class HomeTab extends StatefulWidget {
  final String selectedSubject;
  final void Function(String)? onSubjectChanged;
  const HomeTab({super.key, required this.selectedSubject, this.onSubjectChanged});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String _studentName = 'Student';
  String _studentId = '';
  String _currentSubject = 'Mathematics';
  List<dynamic> _lessons = [];
  dynamic _lastLesson;
  bool _loading = true;
  int _streak = 0;
  double _lessonProgress = 0.0;
  bool _completedLesson = false;
  bool _completedQuiz = false;

  @override
  void initState() {
    super.initState();
    _currentSubject = widget.selectedSubject;
    _loadData();
  }

  @override
  void didUpdateWidget(HomeTab old) {
    super.didUpdateWidget(old);
    if (old.selectedSubject != widget.selectedSubject) {
      setState(() => _currentSubject = widget.selectedSubject);
      _loadLessons();
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _studentId = prefs.getString('userId') ?? '';
    setState(() => _studentName = prefs.getString('student_name') ?? prefs.getString('name') ?? 'Student');
    await Future.wait([_loadProfile(), _loadLessons(), _loadTodayActivity()]);
  }

  Future<void> _loadProfile() async {
    if (_studentId.isEmpty) return;
    try {
      final r = await http.get(Uri.parse('$kApiUrl/api/student/profile?studentId=$_studentId'));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final student = data['student'] ?? data;
        setState(() {
          _streak = (student['streak'] ?? student['current_streak'] ?? 0) as int;
          if (student['name'] != null) _studentName = student['name'];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadTodayActivity() async {
    if (_studentId.isEmpty) return;
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final r = await http.get(Uri.parse('$kApiUrl/api/student/activity?studentId=$_studentId&date=$today'));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        setState(() {
          _completedLesson = (data['lessons_today'] ?? 0) > 0;
          _completedQuiz = (data['quizzes_today'] ?? 0) > 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadLessons() async {
    setState(() => _loading = true);
    try {
      final r = await http.get(Uri.parse('$kApiUrl/api/lessons?subject=${Uri.encodeComponent(_currentSubject)}&status=published&limit=10'));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as List;
        setState(() {
          _lessons = data;
          if (data.isNotEmpty) _lastLesson = data[0];
        });
        if (_studentId.isNotEmpty && data.isNotEmpty) await _loadLessonProgress(data[0]);
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _loadLessonProgress(dynamic lesson) async {
    try {
      final lessonId = lesson['id'] ?? lesson['lesson_id'];
      if (lessonId == null) return;
      final r = await http.get(Uri.parse('$kApiUrl/api/student/lesson-progress?studentId=$_studentId&lessonId=$lessonId'));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        setState(() => _lessonProgress = ((data['progress'] ?? 0) as num).toDouble().clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  void _goToTutor() {
    final shell = context.findAncestorStateOfType<MainShellState>();
    if (shell != null) shell.setState(() => shell.currentIndex = 1);
  }

  void _goToQuizzes() {
    final shell = context.findAncestorStateOfType<MainShellState>();
    if (shell != null) shell.setState(() => shell.currentIndex = 2);
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName => _studentName.split(' ').first;

  int get _missionsDone => [_completedLesson, _completedQuiz, _streak > 0].where((b) => b).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SingleChildScrollView(
        child: Column(children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (_lastLesson != null) _buildContinueLearning(),
          if (_lastLesson != null) const SizedBox(height: 12),
          _buildTodaysMission(),
          const SizedBox(height: 16),
          _buildQuickActions(),
          const SizedBox(height: 16),
          _buildLessonsSection(),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 52, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), Color(0xFF0D1B2A)])),
      child: Column(children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_greeting, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
            Text(_firstName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
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
        const SizedBox(height: 14),
        _buildSubjectBar(),
      ]),
    );
  }

  Widget _buildSubjectBar() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kSubjects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final s = kSubjects[i];
          final name = s['name'] as String;
          final isSelected = name == _currentSubject;
          final color = Color(s['color'] as int);
          return GestureDetector(
            onTap: () {
              setState(() => _currentSubject = name);
              _loadLessons();
              context.findAncestorStateOfType<MainShellState>()?.setSubject(name);
              widget.onSubjectChanged?.call(name);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? color : Colors.white.withOpacity(0.2))),
              child: Text(name, style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContinueLearning() {
    final title = _lastLesson['title'] as String? ?? _lastLesson['topic'] as String? ?? 'Lesson';
    final pct = (_lessonProgress * 100).round();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF1E88E5)]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: Text(_lessonProgress > 0 ? 'CONTINUE LEARNING' : 'START LEARNING',
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson: _lastLesson))),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18))),
        ]),
        const SizedBox(height: 14),
        Text(_currentSubject, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _lessonProgress,
            backgroundColor: const Color(0x33FFFFFF),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 5)),
        const SizedBox(height: 8),
        Row(children: [
          Text('$pct% complete', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11)),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson: _lastLesson))),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Text(_lessonProgress > 0 ? 'Resume' : 'Start',
                style: const TextStyle(color: Color(0xFF1E3A8A), fontSize: 12, fontWeight: FontWeight.w800)))),
        ]),
      ]),
    );
  }

  Widget _buildTodaysMission() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text("Today's Mission", style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
          const Spacer(),
          const Icon(Icons.flag_rounded, color: kMuted, size: 18),
        ]),
        const SizedBox(height: 14),
        _missionItem('Complete 1 lesson', _completedLesson, Icons.menu_book_rounded),
        const SizedBox(height: 10),
        _missionItem('Answer 5 questions', _completedQuiz, Icons.edit_rounded),
        const SizedBox(height: 10),
        _missionItem('Maintain streak', _streak > 0, Icons.local_fire_department_rounded),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _missionsDone / 3,
            backgroundColor: kSurface2,
            valueColor: const AlwaysStoppedAnimation<Color>(kGreen),
            minHeight: 4)),
        const SizedBox(height: 6),
        Text('$_missionsDone/3 tasks done', style: const TextStyle(color: kMuted, fontSize: 11)),
      ]),
    );
  }

  Widget _missionItem(String label, bool done, IconData icon) {
    return Row(children: [
      Icon(icon, color: done ? kGreen : kMuted, size: 16),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(color: done ? kMuted : kText, fontSize: 13, decoration: done ? TextDecoration.lineThrough : null))),
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(color: done ? kGreen : Colors.transparent, shape: BoxShape.circle, border: Border.all(color: done ? kGreen : kBorder, width: 2)),
        child: done ? const Icon(Icons.check, color: Colors.white, size: 12) : null),
    ]);
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Quick Actions', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: _goToTutor,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kPrimary, kPrimary2]),
                borderRadius: BorderRadius.circular(14)),
              child: const Column(children: [
                Icon(Icons.smart_toy_rounded, color: Colors.white, size: 26),
                SizedBox(height: 8),
                Text('AI Tutor', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                Text('Start learning', style: TextStyle(color: Colors.white70, fontSize: 10)),
              ]),
            ),
          )),
          const SizedBox(width: 12),
          Expanded(child: GestureDetector(
            onTap: _goToQuizzes,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF43A047)]),
                borderRadius: BorderRadius.circular(14)),
              child: const Column(children: [
                Icon(Icons.quiz_rounded, color: Colors.white, size: 26),
                SizedBox(height: 8),
                Text('Practice', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                Text('SPM questions', style: TextStyle(color: Colors.white70, fontSize: 10)),
              ]),
            ),
          )),
        ]),
      ]),
    );
  }

  Widget _buildLessonsSection() {
    if (_loading) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: kPrimary)));
    if (_lessons.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No lessons available', style: TextStyle(color: kMuted))));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          const Text('Your Lessons', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${_lessons.length} available', style: const TextStyle(color: kMuted, fontSize: 12)),
        ])),
      ...(_lessons.take(8).toList().asMap().entries.map((e) {
        final lesson = e.value;
        final index = e.key;
        final topic = lesson['topic'] as String? ?? '';
        final title = lesson['title'] as String? ?? topic;
        final form = lesson['form_level'];
        final isFirst = index == 0;
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson: lesson))),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isFirst ? kPrimary.withOpacity(0.08) : kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isFirst ? kPrimary.withOpacity(0.3) : kBorder, width: isFirst ? 1.5 : 1)),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: isFirst ? kPrimary : kSurface2, borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text('${index + 1}', style: TextStyle(color: isFirst ? Colors.white : kMuted, fontSize: 14, fontWeight: FontWeight.w800)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: kText, fontSize: 13, fontWeight: isFirst ? FontWeight.w700 : FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [
                  if (form != null) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text('Form $form', style: const TextStyle(color: kPrimary, fontSize: 10, fontWeight: FontWeight.w700))),
                  if (form != null) const SizedBox(width: 6),
                  Flexible(child: Text(topic, style: const TextStyle(color: kMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ])),
              const SizedBox(width: 8),
              Column(children: [
                const Icon(Icons.arrow_forward_ios_rounded, color: kMuted, size: 12),
                if (isFirst) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: kGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                    child: const Text('START', style: TextStyle(color: kGreen, fontSize: 9, fontWeight: FontWeight.w800))),
                ],
              ]),
            ]),
          ),
        );
      })),
    ]);
  }
}
