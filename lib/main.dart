import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const String API_URL = 'https://attractive-contentment-production-146b.up.railway.app';

// ── SUBJECTS ─────────────────────────────────────────────────────
const List<Map<String, dynamic>> kSubjects = [
  {'name': 'Mathematics', 'emoji': '📐', 'color': 0xFF6366F1},
  {'name': 'Add Maths', 'emoji': '➕', 'color': 0xFF8B5CF6},
  {'name': 'Physics', 'emoji': '⚡', 'color': 0xFFF59E0B},
  {'name': 'Biology', 'emoji': '🧬', 'color': 0xFF10B981},
  {'name': 'Chemistry', 'emoji': '🧪', 'color': 0xFFEF4444},
  {'name': 'Geography', 'emoji': '🌍', 'color': 0xFF06B6D4},
  {'name': 'Sejarah', 'emoji': '📜', 'color': 0xFFD97706},
  {'name': 'Bahasa Malaysia', 'emoji': '🇲🇾', 'color': 0xFFEC4899},
  {'name': 'English', 'emoji': '📝', 'color': 0xFF14B8A6},
];

// ── THEME ─────────────────────────────────────────────────────────
const Color kPrimary = Color(0xFF6366F1);
const Color kPrimary2 = Color(0xFF8B5CF6);
const Color kGreen = Color(0xFF10B981);
const Color kYellow = Color(0xFFF59E0B);
const Color kRed = Color(0xFFEF4444);
const Color kBg = Color(0xFF0F1117);
const Color kSurface = Color(0xFF1A1D27);
const Color kSurface2 = Color(0xFF242736);
const Color kBorder = Color(0xFF2E3347);
const Color kText = Color(0xFFE2E8F0);
const Color kMuted = Color(0xFF94A3B8);

void main() {
  runApp(const LearnovaApp());
}

class LearnovaApp extends StatelessWidget {
  const LearnovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Learnova',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        primaryColor: kPrimary,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: kPrimary,
          secondary: kPrimary2,
          surface: kSurface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kSurface,
          elevation: 0,
          titleTextStyle: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700),
          iconTheme: IconThemeData(color: kText),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSurface2,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPrimary)),
          labelStyle: const TextStyle(color: kMuted),
          hintStyle: const TextStyle(color: kMuted),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ── SPLASH ────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => token != null ? const MainShell() : const AuthScreen(),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kPrimary, kPrimary2]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.school_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 20),
            const Text('Learnova', style: TextStyle(color: kText, fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('AI-Powered Tutoring', style: TextStyle(color: kMuted, fontSize: 15)),
            const SizedBox(height: 40),
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
          ],
        ),
      ),
    );
  }
}

// ── AUTH ──────────────────────────────────────────────────────────
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _parentEmailCtrl = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _submit() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final endpoint = _isLogin ? '/api/student/login' : '/api/student/signup';
      final body = _isLogin
          ? {'email': _emailCtrl.text.trim(), 'password': _passwordCtrl.text}
          : {
              'email': _emailCtrl.text.trim(),
              'password': _passwordCtrl.text,
              'name': _nameCtrl.text.isEmpty ? 'Student' : _nameCtrl.text,
              'parent_email': _parentEmailCtrl.text.trim(),
            };

      final response = await http.post(
        Uri.parse('$API_URL$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('student_id', data['student_id'] ?? '');
        await prefs.setString('student_name', data['name'] ?? 'Student');
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
        }
      } else {
        _showSnack(data['error'] ?? 'Authentication failed');
      }
    } catch (e) {
      _showSnack('Connection error. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: kSurface2));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-0.5, -0.5), radius: 1.2, colors: [Color(0xFF1E1B4B), kBg]),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.school_rounded, color: Colors.white, size: 24)),
                  const SizedBox(width: 12),
                  const Text('Learnova', style: TextStyle(color: kText, fontSize: 24, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 40),
                Text(_isLogin ? 'Welcome back 👋' : 'Join Learnova 🚀', style: const TextStyle(color: kText, fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(_isLogin ? 'Sign in to continue learning' : 'Create your student account', style: const TextStyle(color: kMuted, fontSize: 14)),
                const SizedBox(height: 32),
                if (!_isLogin) ...[
                  _field(_nameCtrl, 'Full Name', Icons.person_outline),
                  const SizedBox(height: 14),
                  _field(_parentEmailCtrl, 'Parent Email (optional)', Icons.family_restroom),
                  const SizedBox(height: 14),
                ],
                _field(_emailCtrl, 'Email Address', Icons.email_outlined, type: TextInputType.emailAddress),
                const SizedBox(height: 14),
                _field(_passwordCtrl, 'Password', Icons.lock_outline, obscure: true),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isLogin ? 'Sign In' : 'Create Account'),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _isLogin = !_isLogin),
                    child: Text(
                      _isLogin ? "Don't have an account? Sign Up" : 'Already have an account? Sign In',
                      style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {bool obscure = false, TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: type,
      style: const TextStyle(color: kText),
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: kMuted, size: 20)),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _parentEmailCtrl.dispose();
    super.dispose();
  }
}

// ── MAIN SHELL ────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  String _selectedSubject = 'Mathematics';

  void setSubject(String s) => setState(() => _selectedSubject = s);

  List<Widget> get _screens => [
    HomeTab(selectedSubject: _selectedSubject, onSubjectChanged: setSubject),
    AITutorTab(selectedSubject: _selectedSubject),
    QuizzesTab(selectedSubject: _selectedSubject),
    const ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: kBorder)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: kPrimary,
          unselectedItemColor: kMuted,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded), label: 'AI Tutor'),
            BottomNavigationBarItem(icon: Icon(Icons.quiz_rounded), label: 'Quizzes'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

// ── SUBJECT SELECTOR WIDGET ───────────────────────────────────────
class SubjectSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const SubjectSelector({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: kSubjects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final s = kSubjects[i];
          final isSelected = s['name'] == selected;
          final color = Color(s['color'] as int);
          return GestureDetector(
            onTap: () => onChanged(s['name'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.2) : kSurface2,
                border: Border.all(color: isSelected ? color : kBorder, width: isSelected ? 1.5 : 1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(children: [
                Text(s['emoji'] as String, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(s['name'] as String, style: TextStyle(color: isSelected ? color : kMuted, fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── HOME TAB ──────────────────────────────────────────────────────
class HomeTab extends StatefulWidget {
  final String selectedSubject;
  final ValueChanged<String> onSubjectChanged;
  const HomeTab({super.key, required this.selectedSubject, required this.onSubjectChanged});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String _name = 'Student';
  List<dynamic> _lessons = [];
  List<String> _faqQuestions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubject != widget.selectedSubject) {
      _loadSubjectData();
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('student_name') ?? 'Student';
    await _loadSubjectData();
    setState(() => _loading = false);
  }

  Future<void> _loadSubjectData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    try {
      // Load lessons for subject
      final r = await http.get(
        Uri.parse('$API_URL/api/lessons?subject=${Uri.encodeComponent(widget.selectedSubject)}&form_level=4'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (r.statusCode == 200) setState(() => _lessons = jsonDecode(r.body));

      // Load FAQ questions dynamically from backend
      final faqR = await http.get(
        Uri.parse('$API_URL/api/ai/faq?subject=${Uri.encodeComponent(widget.selectedSubject)}'),
      );
      if (faqR.statusCode == 200) {
        final faqData = jsonDecode(faqR.body);
        final topics = faqData['topics'] as Map<String, dynamic>? ?? {};
        final questions = <String>[];
        topics.forEach((topic, qList) {
          if (qList is List) {
            for (final q in qList.take(2)) {
              final question = q['question'] as String? ?? '';
              if (question.isNotEmpty) {
                // Capitalise first letter
                questions.add(question[0].toUpperCase() + question.substring(1) + '?');
              }
            }
          }
          if (questions.length >= 6) return;
        });
        setState(() => _faqQuestions = questions.take(6).toList());
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _goToTab(int i) {
    final shell = context.findAncestorStateOfType<_MainShellState>();
    shell?.setState(() => shell._currentIndex = i);
  }

  Map<String, dynamic> get _subjectInfo {
    return kSubjects.firstWhere((s) => s['name'] == widget.selectedSubject, orElse: () => kSubjects.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : RefreshIndicator(
                onRefresh: _load,
                color: kPrimary,
                child: CustomScrollView(slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  SliverToBoxAdapter(child: _buildSubjectSelector()),
                  SliverToBoxAdapter(child: _buildQuickActions()),
                  SliverToBoxAdapter(child: _buildFAQSection()),
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text('📖 Lessons', style: _sectionTitle()),
                  )),
                  _lessons.isEmpty
                      ? SliverToBoxAdapter(child: _emptyState('No lessons yet', 'Your teacher will upload lessons soon'))
                      : SliverList(delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _lessonCard(_lessons[i]),
                          childCount: _lessons.length,
                        )),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ]),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final subj = _subjectInfo;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: const BoxDecoration(color: kSurface, border: Border(bottom: BorderSide(color: kBorder))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$greeting 👋', style: const TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 2),
          Text(_name, style: const TextStyle(color: kText, fontSize: 22, fontWeight: FontWeight.w800)),
          Text('${subj['emoji']} ${widget.selectedSubject}', style: const TextStyle(color: kMuted, fontSize: 13)),
        ])),
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(_name.isNotEmpty ? _name[0].toUpperCase() : 'S', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))),
        ),
      ]),
    );
  }

  Widget _buildSubjectSelector() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Text('📚 Subject', style: _sectionTitle()),
      ),
      SubjectSelector(
        selected: widget.selectedSubject,
        onChanged: (s) {
          widget.onSubjectChanged(s);
        },
      ),
      const SizedBox(height: 4),
    ]);
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(children: [
        _actionCard('🤖', 'Ask AI', 'Get instant answers', kPrimary, () => _goToTab(1)),
        const SizedBox(width: 12),
        _actionCard('🧠', 'Take Quiz', 'Test your knowledge', kGreen, () => _goToTab(2)),
      ]),
    );
  }

  Widget _actionCard(String emoji, String title, String sub, Color color, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color.withOpacity(0.15), color.withOpacity(0.05)]),
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
          Text(sub, style: const TextStyle(color: kMuted, fontSize: 12)),
        ]),
      ),
    ));
  }

  Widget _buildFAQSection() {
    final faqs = _faqQuestions.isNotEmpty ? _faqQuestions : [
      'What is a function?', 'How to use quadratic formula?',
      'What is the discriminant?', 'Sum of arithmetic progression?'
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12), child: Text('⚡ Quick Questions', style: _sectionTitle())),
      SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: faqs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) => GestureDetector(
            onTap: () {
              // Send question to AI tutor tab
              final shell = context.findAncestorStateOfType<_MainShellState>();
              shell?.setState(() => shell._currentIndex = 1);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: kSurface2, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(20)),
              child: Text(faqs[i], style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _lessonCard(dynamic lesson) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: kPrimary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.book_rounded, color: kPrimary, size: 22)),
        title: Text(lesson['title'] ?? 'Lesson', style: const TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${lesson['topic'] ?? ''} · Form ${lesson['form_level'] ?? 4}', style: const TextStyle(color: kMuted, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: kMuted, size: 14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson: lesson))),
      ),
    );
  }

  Widget _emptyState(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(children: [
        const Icon(Icons.book_outlined, color: kMuted, size: 48),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(sub, style: const TextStyle(color: kMuted, fontSize: 13), textAlign: TextAlign.center),
      ]),
    );
  }

  TextStyle _sectionTitle() => const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700);
}

// ── LESSON SCREEN ─────────────────────────────────────────────────
class LessonScreen extends StatefulWidget {
  final dynamic lesson;
  const LessonScreen({super.key, required this.lesson});
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  Map<String, dynamic>? _fullLesson;
  bool _loading = true;
  int _currentSection = 0;

  final List<Map<String, String>> _sections = [
    {'key': 'introduction', 'title': '📖 Introduction', 'emoji': '📖'},
    {'key': 'objectives', 'title': '🎯 Learning Objectives', 'emoji': '🎯'},
    {'key': 'content', 'title': '📚 Explanation', 'emoji': '📚'},
    {'key': 'worked_examples', 'title': '✏️ Worked Examples', 'emoji': '✏️'},
    {'key': 'common_mistakes', 'title': '⚠️ Common Mistakes', 'emoji': '⚠️'},
    {'key': 'summary', 'title': '📝 Summary & Key Points', 'emoji': '📝'},
  ];

  @override
  void initState() {
    super.initState();
    _loading = false;
  }

  dynamic get _lesson => widget.lesson;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text((_lesson['topic'] ?? 'Lesson').toString()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('${_currentSection + 1}/${_sections.length}',
                style: const TextStyle(color: kMuted, fontSize: 13)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : Column(children: [
              // Section tab bar
              Container(
                color: kSurface,
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: _sections.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final isSelected = _currentSection == i;
                    return GestureDetector(
                      onTap: () => setState(() => _currentSection = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? kPrimary : kSurface2,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelected ? kPrimary : kBorder),
                        ),
                        child: Text(
                          _sections[i]['title']!,
                          style: TextStyle(
                            color: isSelected ? Colors.white : kMuted,
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Section content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildCurrentSection(),
                ),
              ),
              // Navigation buttons
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: const BoxDecoration(
                  color: kSurface,
                  border: Border(top: BorderSide(color: kBorder)),
                ),
                child: Row(children: [
                  if (_currentSection > 0)
                    Expanded(child: OutlinedButton(
                      onPressed: () => setState(() => _currentSection--),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kText,
                        side: const BorderSide(color: kBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('← Previous'),
                    )),
                  if (_currentSection > 0) const SizedBox(width: 12),
                  if (_currentSection < _sections.length - 1)
                    Expanded(child: ElevatedButton(
                      onPressed: () => setState(() => _currentSection++),
                      child: const Text('Next →'),
                    )),
                  if (_currentSection == _sections.length - 1)
                    Expanded(child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(backgroundColor: kGreen),
                      child: const Text('✓ Complete'),
                    )),
                ]),
              ),
            ]),
    );
  }

  Widget _buildCurrentSection() {
    final section = _sections[_currentSection];
    final key = section['key']!;

    switch (key) {
      case 'introduction':
        final intro = _lesson['introduction']?.toString() ?? '';
        return _buildTextSection('📖 Introduction', intro, kPrimary);

      case 'objectives':
        final objs = _lesson['learning_objectives'];
        if (objs == null) return _emptySection('No objectives available');
        final list = objs is List ? objs : [];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader('🎯 Learning Objectives'),
          const SizedBox(height: 16),
          ...list.asMap().entries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kGreen.withOpacity(0.08),
              border: Border.all(color: kGreen.withOpacity(0.25)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text('${e.key + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(e.value.toString(),
                style: const TextStyle(color: kText, fontSize: 14, height: 1.5))),
            ]),
          )),
        ]);

      case 'content':
        final content = _lesson['content']?.toString() ?? '';
        return _buildTextSection('📚 Full Explanation', content, kPrimary);

      case 'worked_examples':
        final examples = _lesson['worked_examples']?.toString() ?? '';
        if (examples.isEmpty) return _emptySection('Worked examples coming soon');
        return _buildExamplesSection(examples);

      case 'common_mistakes':
        final mistakes = _lesson['common_mistakes']?.toString() ?? '';
        if (mistakes.isEmpty) return _emptySection('Common mistakes coming soon');
        return _buildMistakesSection(mistakes);

      case 'summary':
        final summary = _lesson['summary']?.toString() ?? '';
        if (summary.isEmpty) return _emptySection('Summary coming soon');
        return _buildTextSection('📝 Summary & Key Points', summary, kYellow);

      default:
        return _emptySection('Content coming soon');
    }
  }

  Widget _buildTextSection(String title, String content, Color color) {
    if (content.isEmpty) return _emptySection('Content coming soon');
    // Split by double newlines for paragraphs
    final paragraphs = content.split('\n\n').where((p) => p.trim().isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(title),
      const SizedBox(height: 16),
      ...paragraphs.map((para) {
        final trimmed = para.trim();
        // Check if it's a header (ALL CAPS or starts with PART)
        final isHeader = trimmed == trimmed.toUpperCase() && trimmed.length > 3 && trimmed.length < 60
            || trimmed.startsWith('PART ') || trimmed.startsWith('Law ');
        if (isHeader) {
          return Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Text(trimmed,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(trimmed,
            style: const TextStyle(color: kText, fontSize: 14, height: 1.75)),
        );
      }),
    ]);
  }

  Widget _buildExamplesSection(String examples) {
    final parts = examples.split('───────────────────────────────────────────')
        .where((p) => p.trim().isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('✏️ Worked Examples'),
      const SizedBox(height: 16),
      ...parts.asMap().entries.map((e) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text('${e.key + 1}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
              ),
              const SizedBox(width: 10),
              Text('Example ${e.key + 1}',
                style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(e.value.trim(),
              style: const TextStyle(color: kText, fontSize: 13, height: 1.75,
                fontFamily: 'monospace')),
          ),
        ]),
      )),
    ]);
  }

  Widget _buildMistakesSection(String mistakes) {
    final lines = mistakes.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('⚠️ Common Mistakes'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kRed.withOpacity(0.08),
          border: Border.all(color: kRed.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, color: kRed, size: 18),
          const SizedBox(width: 8),
          const Expanded(child: Text('Study these carefully — these exact mistakes cost marks in SPM!',
            style: TextStyle(color: kRed, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      ),
      const SizedBox(height: 16),
      ...lines.map((line) {
        final trimmed = line.trim();
        if (trimmed.startsWith('❌')) {
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kRed.withOpacity(0.08),
              border: Border.all(color: kRed.withOpacity(0.2)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(trimmed, style: const TextStyle(color: kRed, fontSize: 13, height: 1.5)),
          );
        } else if (trimmed.startsWith('✅')) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kGreen.withOpacity(0.08),
              border: Border.all(color: kGreen.withOpacity(0.2)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(trimmed, style: const TextStyle(color: kGreen, fontSize: 13, height: 1.5)),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(trimmed, style: const TextStyle(color: kText, fontSize: 13, height: 1.6)),
        );
      }),
    ]);
  }

  Widget _sectionHeader(String title) {
    return Text(title,
      style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w800));
  }

  Widget _emptySection(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          const Icon(Icons.hourglass_empty, color: kMuted, size: 48),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: kMuted, fontSize: 14)),
        ]),
      ),
    );
  }
}

// ── AI TUTOR TAB ──────────────────────────────────────────────────
class AITutorTab extends StatefulWidget {
  final String selectedSubject;
  const AITutorTab({super.key, required this.selectedSubject});
  @override
  State<AITutorTab> createState() => _AITutorTabState();
}

class _AITutorTabState extends State<AITutorTab> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  String _currentSubject = 'Mathematics';
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _currentSubject = widget.selectedSubject;
    _loadSuggestions();
  }

  @override
  void didUpdateWidget(AITutorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubject != widget.selectedSubject) {
      setState(() => _currentSubject = widget.selectedSubject);
      _loadSuggestions();
    }
  }

  Future<void> _loadSuggestions() async {
    try {
      final r = await http.get(
        Uri.parse('$API_URL/api/ai/faq?subject=${Uri.encodeComponent(_currentSubject)}'),
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final topics = data['topics'] as Map<String, dynamic>? ?? {};
        final questions = <String>[];
        topics.forEach((topic, qList) {
          if (qList is List && questions.length < 6) {
            for (final q in qList.take(1)) {
              final question = q['question'] as String? ?? '';
              if (question.isNotEmpty) {
                questions.add(question[0].toUpperCase() + question.substring(1) + '?');
              }
            }
          }
        });
        if (mounted) setState(() => _suggestions = questions.take(6).toList());
      }
    } catch (_) {
      setState(() => _suggestions = [
        'What is a function?', 'How to factorise quadratic?',
        'Laws of indices?', 'Sum to infinity GP?',
      ]);
    }
  }

  Future<void> _ask(String question) async {
    if (question.trim().isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'text': question});
      _loading = true;
    });
    _ctrl.clear();
    _scrollToBottom();

    try {
      final r = await http.post(
        Uri.parse('$API_URL/api/ai/ask'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': question, 'subject': _currentSubject}),
      );
      final data = jsonDecode(r.body);
      setState(() {
        _messages.add({
          'role': 'ai',
          'text': data['answer'] ?? 'Sorry, I could not answer that.',
          'example': data['example'],
          'topic': data['topic'],
          'source': data['source'],
          'subject': data['subject'],
        });
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _messages.add({'role': 'ai', 'text': 'Connection error. Please try again.'});
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Map<String, dynamic> get _subjectInfo {
    return kSubjects.firstWhere((s) => s['name'] == _currentSubject, orElse: () => kSubjects.first);
  }

  @override
  Widget build(BuildContext context) {
    final subj = _subjectInfo;
    final subjectColor = Color(subj['color'] as int);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Row(children: [
          Text(subj['emoji'] as String, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text('AI Tutor · $_currentSubject'),
        ]),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => setState(() => _messages.clear())),
        ],
      ),
      body: Column(children: [
        // Subject selector strip
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SubjectSelector(
            selected: _currentSubject,
            onChanged: (s) {
              setState(() => _currentSubject = s);
              _loadSuggestions();
              // Sync back to shell
              final shell = context.findAncestorStateOfType<_MainShellState>();
              shell?.setSubject(s);
            },
          ),
        ),
        if (_messages.isEmpty) _buildWelcome(subjectColor),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_loading ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i == _messages.length) return _typingIndicator();
              return _buildMessage(_messages[i]);
            },
          ),
        ),
        if (_messages.isEmpty) _buildSuggestions(),
        _buildInput(),
      ]),
    );
  }

  Widget _buildWelcome(Color color) {
    final subj = _subjectInfo;
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: color.withOpacity(0.15), border: Border.all(color: color.withOpacity(0.4)), borderRadius: BorderRadius.circular(16)),
          child: Center(child: Text(subj['emoji'] as String, style: const TextStyle(fontSize: 30))),
        ),
        const SizedBox(height: 12),
        Text('$_currentSubject AI Tutor', style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Ask me anything about Form 4-5 $_currentSubject', style: const TextStyle(color: kMuted, fontSize: 13), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildSuggestions() {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => GestureDetector(
          onTap: () => _ask(_suggestions[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: kSurface2, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(20)),
            child: Text(_suggestions[i], style: const TextStyle(color: kText, fontSize: 12)),
          ),
        ),
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    final source = msg['source'] as String?;
    String sourceLabel = '';
    if (source == 'faq' || source == 'faq_cache') sourceLabel = '⚡ Instant answer';
    else if (source == 'claude') sourceLabel = '🤖 AI generated';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(width: 32, height: 32, decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isUser ? kPrimary : kSurface,
                  border: Border.all(color: isUser ? kPrimary : kBorder),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(msg['text'], style: const TextStyle(color: kText, fontSize: 14, height: 1.6)),
              ),
              if (!isUser && msg['example'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: kGreen.withOpacity(0.1), border: Border.all(color: kGreen.withOpacity(0.3)), borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Example:', style: TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(msg['example'], style: const TextStyle(color: kText, fontSize: 13)),
                  ]),
                ),
              ],
              if (!isUser && sourceLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(sourceLabel, style: const TextStyle(color: kMuted, fontSize: 11)),
              ],
            ]),
          ),
          if (isUser) const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _typingIndicator() {
    return Row(children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16)),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
        child: const Row(children: [
          SizedBox(width: 6, height: 6, child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
          SizedBox(width: 8),
          Text('Thinking...', style: TextStyle(color: kMuted, fontSize: 13)),
        ]),
      ),
    ]);
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: kBorder))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: kText, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Ask about $_currentSubject...',
              hintStyle: const TextStyle(color: kMuted),
              filled: true,
              fillColor: kSurface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: kPrimary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            onSubmitted: _ask,
            textInputAction: TextInputAction.send,
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => _ask(_ctrl.text),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(22)),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}

// ── QUIZZES TAB ───────────────────────────────────────────────────
class QuizzesTab extends StatefulWidget {
  final String selectedSubject;
  const QuizzesTab({super.key, required this.selectedSubject});
  @override
  State<QuizzesTab> createState() => _QuizzesTabState();
}

class _QuizzesTabState extends State<QuizzesTab> {
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
      final r = await http.get(Uri.parse('$API_URL/api/quiz/list/${Uri.encodeComponent(_currentSubject)}'));
      if (r.statusCode == 200) setState(() => _quizzes = jsonDecode(r.body));
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: Text('Quizzes · $_currentSubject')),
      body: Column(children: [
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SubjectSelector(
            selected: _currentSubject,
            onChanged: (s) {
              setState(() => _currentSubject = s);
              _load();
              final shell = context.findAncestorStateOfType<_MainShellState>();
              shell?.setSubject(s);
            },
          ),
        ),
        Expanded(
          child: _loading
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
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(quizId: q['id'], title: q['title'] ?? 'Quiz'))),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ── QUIZ SCREEN ───────────────────────────────────────────────────
class QuizScreen extends StatefulWidget {
  final String quizId;
  final String title;
  const QuizScreen({super.key, required this.quizId, required this.title});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<dynamic> _questions = [];
  Map<String, String> _answers = {};
  bool _loading = true;
  bool _submitted = false;
  Map<String, dynamic>? _results;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse('$API_URL/api/quiz/${widget.quizId}'));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        setState(() => _questions = data['questions'] ?? []);
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _submit() async {
    if (_answers.length < _questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please answer all questions'), backgroundColor: kSurface2));
      return;
    }
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final r = await http.post(
        Uri.parse('$API_URL/api/quiz/${widget.quizId}/submit'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'answers': _answers}),
      );
      if (r.statusCode == 200) {
        setState(() { _results = jsonDecode(r.body); _submitted = true; });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: kBg, body: Center(child: CircularProgressIndicator(color: kPrimary)));
    if (_submitted && _results != null) return _buildResults();
    if (_questions.isEmpty) return Scaffold(appBar: AppBar(title: Text(widget.title)), body: const Center(child: Text('No questions found', style: TextStyle(color: kMuted))));
    return _buildQuiz();
  }

  Widget _buildQuiz() {
    final q = _questions[_current];
    final options = (q['options'] as List? ?? []);
    final progress = (_current + 1) / _questions.length;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Text('${_current + 1}/${_questions.length}', style: const TextStyle(color: kMuted, fontSize: 13))))],
      ),
      body: Column(children: [
        LinearProgressIndicator(value: progress, backgroundColor: kSurface2, color: kPrimary, minHeight: 3),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            Text('Question ${_current + 1}', style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(q['question'] ?? '', style: const TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w600, height: 1.5)),
            const SizedBox(height: 24),
            ...options.map((opt) {
              final selected = _answers[q['id']] == opt.toString();
              return GestureDetector(
                onTap: () => setState(() => _answers[q['id']] = opt.toString()),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: selected ? kPrimary.withOpacity(0.15) : kSurface,
                    border: Border.all(color: selected ? kPrimary : kBorder, width: selected ? 2 : 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? kPrimary : kSurface2, border: Border.all(color: selected ? kPrimary : kBorder)), child: selected ? const Icon(Icons.check, color: Colors.white, size: 14) : null),
                    const SizedBox(width: 12),
                    Expanded(child: Text(opt.toString(), style: TextStyle(color: kText, fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w400))),
                  ]),
                ),
              );
            }),
          ]),
        )),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            if (_current > 0) ...[
              Expanded(child: OutlinedButton(
                onPressed: () => setState(() => _current--),
                style: OutlinedButton.styleFrom(foregroundColor: kText, side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Back'),
              )),
              const SizedBox(width: 12),
            ],
            Expanded(child: ElevatedButton(
              onPressed: _current < _questions.length - 1 ? () => setState(() => _current++) : _submit,
              child: Text(_current < _questions.length - 1 ? 'Next' : 'Submit Quiz'),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _buildResults() {
    final score = _results!['score'] ?? 0;
    final total = _results!['total'] ?? 0;
    final pct = _results!['percentage'] ?? 0;
    final feedback = _results!['feedback'] as List? ?? [];
    final color = pct >= 70 ? kGreen : pct >= 50 ? kYellow : kRed;
    final emoji = pct >= 70 ? '🎉' : pct >= 50 ? '👍' : '💪';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text('Results')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Text(emoji, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('$pct%', style: TextStyle(color: color, fontSize: 48, fontWeight: FontWeight.w800)),
              Text('$score out of $total correct', style: const TextStyle(color: kMuted, fontSize: 15)),
              const SizedBox(height: 16),
              Container(height: 8, decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(4)),
                child: FractionallySizedBox(widthFactor: pct / 100, alignment: Alignment.centerLeft,
                  child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))))),
            ]),
          ),
          const SizedBox(height: 24),
          const Align(alignment: Alignment.centerLeft, child: Text('Review Answers', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          ...feedback.asMap().entries.map((e) {
            final f = e.value;
            final correct = f['correct'] == true;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kSurface, border: Border.all(color: correct ? kGreen.withOpacity(0.4) : kRed.withOpacity(0.4)), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: correct ? kGreen : kRed, size: 18),
                  const SizedBox(width: 8),
                  Text('Question ${e.key + 1}', style: TextStyle(color: correct ? kGreen : kRed, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
                if (!correct && f['correct_answer'] != null) ...[
                  const SizedBox(height: 6),
                  Text('Correct: ${f['correct_answer']}', style: const TextStyle(color: kGreen, fontSize: 13)),
                  if (f['explanation'] != null && f['explanation'].toString().isNotEmpty)
                    Text(f['explanation'], style: const TextStyle(color: kMuted, fontSize: 12, height: 1.5)),
                ],
              ]),
            );
          }),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            child: const Text('Back to Quizzes'),
          ),
        ]),
      ),
    );
  }
}

// ── PROFILE TAB ───────────────────────────────────────────────────
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic>? _profile;
  List<dynamic> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    try {
      final r = await http.get(Uri.parse('$API_URL/api/student/profile'), headers: {'Authorization': 'Bearer $token'});
      if (r.statusCode == 200) setState(() => _profile = jsonDecode(r.body));
      final r2 = await http.get(Uri.parse('$API_URL/api/student/quiz-history'), headers: {'Authorization': 'Bearer $token'});
      if (r2.statusCode == 200) setState(() => _history = jsonDecode(r2.body));
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text('Profile'), actions: [
        IconButton(icon: const Icon(Icons.logout_rounded), onPressed: _logout),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(20)),
                  child: Center(child: Text(
                    (_profile?['student']?['name'] ?? 'S').substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
                  )),
                ),
                const SizedBox(height: 12),
                Text(_profile?['student']?['name'] ?? 'Student', style: const TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w800)),
                Text(_profile?['student']?['email'] ?? '', style: const TextStyle(color: kMuted, fontSize: 13)),
                const SizedBox(height: 24),
                Row(children: [
                  _statCard('Quizzes', '${_profile?['stats']?['totalQuizzes'] ?? 0}', Icons.quiz_rounded, kPrimary),
                  const SizedBox(width: 12),
                  _statCard('Avg Score', '${_profile?['stats']?['avgScore'] ?? 0}%', Icons.star_rounded, kYellow),
                  const SizedBox(width: 12),
                  _statCard('Study Time', '${_profile?['stats']?['totalStudyTime'] ?? 0}m', Icons.timer_rounded, kGreen),
                ]),
                const SizedBox(height: 24),
                if (_history.isNotEmpty) ...[
                  const Align(alignment: Alignment.centerLeft, child: Text('Recent Quizzes', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700))),
                  const SizedBox(height: 12),
                  ..._history.take(5).map((h) {
                    final pct = h['percentage'] ?? 0;
                    final color = pct >= 70 ? kGreen : pct >= 50 ? kYellow : kRed;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(h['quizzes']?['title'] ?? 'Quiz', style: const TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 14)),
                          Text(h['quizzes']?['topic'] ?? '', style: const TextStyle(color: kMuted, fontSize: 12)),
                        ])),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Text('$pct%', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14))),
                      ]),
                    );
                  }),
                ],
              ]),
            ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
      ]),
    ));
  }
}
