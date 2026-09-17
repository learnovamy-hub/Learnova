import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../widgets/speaking_orb.dart';
import '../widgets/session_intent_sheet.dart';
import 'main_shell.dart';
import 'lesson_screen.dart';
import 'quiz_subject_selector_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, dynamic>? _nextLesson;
  Map<String, dynamic>? _resumeData;
  bool _loading = true;
  String _name = '';
  String _token = '';
  String _studentId = '';
  String _firstSubject = '';
  String _teachingLang = 'bm';
  List<String> _activeSubjects = [];
  int _formLevel = 5;

  late AudioPlayer _audioPlayer;
  bool _greetingPlayed = false;

  // Welcome animation state
  bool _showWelcome = true;
  bool _showGreeting = false;
  bool _showKhabar = false;
  bool _showButtons = false;
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _qaMessages = [];
  bool _qaLoading = false;

  String _getNovaGreeting() {
    final resume    = _resumeData?['resume'] as Map<String, dynamic>?;
    final hasResume = _resumeData?['hasResume'] == true && resume != null;
    if (hasResume) {
      final title = resume!['lessonTitle'] as String? ?? '';
      if (title.isNotEmpty) return 'Kita sambung: $title. Siap?';
    }
    if (_nextLesson != null) {
      final title = _nextLesson!['lesson_title'] as String? ?? '';
      if (title.isNotEmpty) return 'Pelajaran seterusnya: $title.';
    }
    return 'Topik mana yang kamu nak kuasai hari ini?';
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _loadDashboard();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    _token        = prefs.getString('token') ?? '';
    _name         = prefs.getString('student_name') ?? prefs.getString('name') ?? '';
    _studentId    = prefs.getString('student_id') ?? '';
    _teachingLang = prefs.getString('teaching_language') ?? 'bm';
    final lvlStr  = prefs.getString('form_level') ?? '';
    _formLevel    = lvlStr.contains('4') ? 4 : lvlStr.contains('A') ? 6 : 5;

    final rawSubjects = prefs.getString('active_subjects');
    if (rawSubjects != null) {
      try {
        _activeSubjects = (jsonDecode(rawSubjects) as List)
            .map((e) => e.toString()).toList();
        if (_activeSubjects.isNotEmpty) _firstSubject = _activeSubjects.first;
      } catch (_) {}
    }
    if (_firstSubject.isEmpty) _firstSubject = 'MY-Mathematics';

    final cached   = prefs.getString('home_dash_cache');
    final cachedAt = prefs.getInt('home_dash_cached_at') ?? 0;
    if (cached != null &&
        (DateTime.now().millisecondsSinceEpoch - cachedAt) < 1800000) {
      setState(() => _loading = false);
      _loadNextLesson();
      _loadResumeData();
      return;
    }
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/home/dashboard'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200) {
        await prefs.setString('home_dash_cache', r.body);
        await prefs.setInt('home_dash_cached_at',
            DateTime.now().millisecondsSinceEpoch);
      }
    } catch (_) {}
    setState(() => _loading = false);
    _loadNextLesson();
    _loadResumeData();
    _startWelcomeSequence();
  }

  void _startWelcomeSequence() {
    Future.delayed(const Duration(milliseconds: 500),  () { if (mounted) setState(() => _showGreeting = true); });
    Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) setState(() => _showKhabar   = true); });
    Future.delayed(const Duration(milliseconds: 3000), () { if (mounted) setState(() => _showButtons  = true); });
  }

  void _dismissWelcome() {
    if (_showWelcome) setState(() => _showWelcome = false);
  }

  Future<void> _loadResumeData() async {
    if (_studentId.isEmpty) return;
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/progress/resume?studentId=$_studentId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200 && mounted) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _resumeData = d);
        _playHomeGreeting();
      }
    } catch (_) {}
  }

  Future<void> _playHomeGreeting() async {
    if (_greetingPlayed || _token.isEmpty || _firstName.isEmpty) return;
    _greetingPlayed = true;
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final greetWord = _greeting;
    final resume    = _resumeData?['resume'] as Map<String, dynamic>?;
    final hasResume = _resumeData?['hasResume'] == true && resume != null;
    String greetText;
    if (hasResume) {
      final title = resume!['lessonTitle'] as String? ?? '';
      greetText = title.isNotEmpty
          ? '$greetWord, $_firstName. Kita sambung $title hari ini.'
          : '$greetWord, $_firstName. Kita belajar ${_subjectDisplayName(_firstSubject)} hari ini.';
    } else if (_nextLesson != null) {
      final title = _nextLesson!['lesson_title'] as String? ?? '';
      greetText = title.isNotEmpty
          ? '$greetWord, $_firstName. Kita sambung $title hari ini.'
          : '$greetWord, $_firstName. Kita belajar ${_subjectDisplayName(_firstSubject)} hari ini.';
    } else {
      greetText = '$greetWord, $_firstName. Kita belajar ${_subjectDisplayName(_firstSubject)} hari ini.';
    }

    try {
      final response = await http.post(
        Uri.parse('$kApiUrl/api/tts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'text': greetText, 'voice': 'nova', 'language': 'bm'}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 && mounted) {
        await _audioPlayer.play(BytesSource(response.bodyBytes));
      }
    } catch (_) {}
  }

  Future<void> _loadNextLesson() async {
    if (_studentId.isEmpty) return;
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/lessons/next'
            '?studentId=$_studentId'
            '&subject=${Uri.encodeComponent(_firstSubject)}'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200 && mounted) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _nextLesson = d['nextLesson'] as Map<String, dynamic>?);
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('home_dash_cache');
    await prefs.remove('home_dash_cached_at');
    setState(() {
      _loading = true; _nextLesson = null; _resumeData = null;
    });
    await _loadDashboard();
  }

  // ── Smart greeting ─────────────────────────────────────────────────
  static const _muslimIndicators = [
    'muhammad', 'muhamad', 'mohd', 'mohamad', 'mohammad', 'ahmad', 'ahmed',
    'nur', 'nurul', 'siti', 'wan', 'nik', 'tengku',
    'sharifah', 'syed', 'said', 'abd', 'abdul', 'abu',
    'ali', 'umar', 'omar', 'osman', 'hassan', 'husain', 'hussain',
    'ibrahim', 'ismail', 'idris', 'izzat', 'izzah',
    'fatimah', 'khadijah', 'zainab', 'aisyah', 'aisha', 'aishah',
    'yusof', 'yusuf', 'yahya', 'zakaria', 'hafiz', 'hakim',
    'azman', 'azwan', 'azrul', 'azri', 'farid', 'farhan', 'faiz',
    'halim', 'irfan', 'luqman', 'razif', 'razak', 'zulkifli',
    'nazir', 'nazri', 'nazrin', 'nazrul', 'nazirul', 'nazhan', 'nazar',
    'aziz', 'azhar', 'azlan',
    'haziq', 'hazim', 'hazwan',
    'faris', 'farish',
    'anis', 'anas', 'aniq',
    'arif', 'ariff', 'aqil', 'aqeel',
    'rauf', 'rafi', 'rafiq',
    'wafi', 'wafiq', 'walid',
    'taqi', 'taqiy', 'taufiq',
    'zafir', 'zahir', 'zahran',
    'akmal', 'adli', 'ayaan', 'ammar', 'aadam', 'ayyash', 'aadil', 'ahsan', 'asraf',
    'badrul', 'basyir', 'bima', 'bahrin', 'bashir', 'basri', 'barzin', 'bariq', 'burhan',
    'daud', 'daniel', 'darma', 'dzulqarnain', 'dzakwan', 'dzulfiqar', 'daffa', 'damar',
    'ehsan', 'elias', 'eiman', 'ezzat', 'eman',
    'faiq', 'fikri', 'firdaus', 'fadhil', 'faz',
    'ghazali', 'gibran', 'ghani', 'ghaffar', 'ghazwan', 'ghaisan',
    'hilmi', 'hasan', 'hamzah', 'hafizh',
    'ikhwan', 'iskandar', 'izzuddin', 'ihsan',
    'jamal', 'jibril',
    'kamil', 'karim', 'khayr', 'khairul', 'kasyaf', 'khalis', 'khidir',
    'luthfi', 'lazim', 'lail', 'lami', 'lazhar', 'luth',
    'marwan', 'miqdad', 'muaz', 'muammar',
    'nashr', 'naim', 'najib', 'nashit', 'nashwan', 'nawfal', 'nizam',
    'othman', 'pasha',
    'qadir', 'qasim', 'qays', 'qamar', 'qawi', 'qudamah', 'qudus', 'qudrat', 'qamaruddin',
    'rahman', 'rashid', 'razi', 'rizqi', 'ruslan',
    'salim', 'sami', 'sani', 'saqib', 'sharif', 'siddiq', 'syakir', 'syazwan',
    'tariq', 'tahir', 'tamim', 'tarmizi',
    'uwais', 'ulwan', 'usamah', 'umair', 'ubay', 'ulfat',
    'wazir', 'wahab', 'wahid', 'wali', 'wajdi', 'wathiq', 'wajih',
    'yasir', 'yamin', 'yaqin', 'yazid', 'yunus', 'yumna',
    'zaid', 'zuhair', 'zamir', 'zuhdi', 'zainulabidin', 'zulqarnain',
    'balqis', 'baiduri', 'damia', 'dana', 'durrah', 'fatin', 'fiona', 'ghayda',
    'haura', 'haya', 'humaira', 'inara', 'imani', 'isya',
    'jauza', 'jihan', 'jannah', 'kamilia', 'khalishah',
    'lafifah', 'latifah', 'leena', 'liyana', 'lubna',
    'maisarah', 'malika', 'marwa', 'mawar',
    'nadhirah', 'nayla', 'naimah', 'nathifa', 'nisrina', 'nabihah', 'nadeera', 'najla',
    'qaila', 'qairina', 'rafidah', 'raidah', 'raihanah', 'rania',
    'safa', 'saidah', 'sakeena', 'salsabila', 'sameeha', 'sameera', 'samiyah',
    'suhayla', 'syafia', 'thahirah', 'talia',
    'ubaidah', 'ufairah', 'ulya', 'umaimah', 'uzma',
    'wafa', 'wardani', 'yasmeen', 'yusrina',
    'zaaimah', 'zafirah', 'zahidah', 'zahiya', 'zahra', 'zara',
    'zuhailin', 'zuhaira', 'zuyyin',
  ];

  static String getSmartGreeting(String name, {String teachingLang = 'bm'}) {
    final h = DateTime.now().hour;
    if (teachingLang == 'zh') {
      if (h < 12) return '早上好';
      if (h < 17) return '下午好';
      return '晚上好';
    }
    if (name.isNotEmpty) {
      final parts = name.toLowerCase().split(RegExp(r'\s+'));
      final isMuslim = parts.any((p) => _muslimIndicators.any(
          (ind) => p.startsWith(ind) || (ind.startsWith(p) && p.length >= 3)));
      if (isMuslim) return 'Assalamualaikum';
    }
    if (h < 12) return 'Selamat pagi';
    if (h < 17) return 'Selamat petang';
    return 'Selamat malam';
  }

  String get _greeting =>
      getSmartGreeting(_name, teachingLang: _teachingLang);

  String get _firstName {
    if (_name.isEmpty) return 'Pelajar';
    final capitalised = _name.split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
    return capitalised.split(' ').first;
  }

  String get _formLevelLabel =>
      _formLevel == 6 ? 'A-Level' : 'Tingkatan $_formLevel';

  // ── Navigation ────────────────────────────────────────────────────
  void _goToTutor({String? subject}) {
    final shell = context.findAncestorStateOfType<MainShellState>();
    if (shell == null) return;
    if (subject != null) shell.setSubject(subject);
    shell.setState(() => shell.currentIndex = 2);
  }

  void _goToLearnTab() {
    final shell = context.findAncestorStateOfType<MainShellState>();
    shell?.setState(() => shell.currentIndex = 1);
  }

  void _continueLesson() {
    final resume    = _resumeData?['resume'] as Map<String, dynamic>?;
    final hasResume = _resumeData?['hasResume'] == true && resume != null;
    if (hasResume) {
      final lessonId = resume!['lessonId'] as String? ?? '';
      final subject  = resume['subject']  as String? ?? _firstSubject;
      if (lessonId.isEmpty) { _goToLearnTab(); return; }
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => LessonScreen(lessonId: lessonId, subject: subject),
      )).then((_) { _loadResumeData(); _loadNextLesson(); });
    } else if (_nextLesson != null) {
      final lessonId = _nextLesson!['id'] as String? ?? '';
      if (lessonId.isEmpty) { _goToLearnTab(); return; }
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => LessonScreen(lessonId: lessonId, subject: _firstSubject),
      )).then((_) { _loadResumeData(); _loadNextLesson(); });
    } else {
      _goToLearnTab();
    }
  }

  void _openQuizScreen() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => QuizSubjectSelectorScreen(
        activeSubjects: _activeSubjects,
      ),
    ));
  }

  Future<void> _submitChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    _dismissWelcome();
    setState(() {
      _qaMessages.add({'role': 'user', 'text': text});
      _qaLoading = true;
    });
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/qa'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'message': text,
          'studentId': _studentId,
          'language': _teachingLang,
        }),
      );
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _qaMessages.add({'role': 'ai', 'text': data['reply'] as String? ?? 'Maaf, cuba lagi.'});
          _qaLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _qaMessages.add({'role': 'ai', 'text': 'Ralat sambungan. Cuba lagi.'});
          _qaLoading = false;
        });
      }
    }
  }

  // ── Subject helpers ───────────────────────────────────────────────
  String _subjectDisplayName(String key) {
    const keyToName = {
      'MY-Mathematics': 'Mathematics', 'MY-AddMaths': 'Add Maths',
      'MY-Physics': 'Physics',         'MY-Biology': 'Biology',
      'MY-Chemistry': 'Chemistry',     'MY-Sejarah': 'Sejarah',
      'MY-BahasaMalaysia': 'BM',       'MY-English': 'English',
      'AL-Mathematics': 'A-Level Math','AL-Physics': 'A-Level Physics',
      'AL-Chemistry': 'A-Level Chem',  'AL-Biology': 'A-Level Bio',
    };
    return keyToName[key] ?? key.replaceFirst('MY-', '').replaceFirst('AL-', '');
  }

  // ── BUILD ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: kBg,
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2))
              : _showWelcome
                  ? _buildWelcomeScreen(top)
                  : RefreshIndicator(
                      color: kPrimary,
                      backgroundColor: kSurface,
                      onRefresh: _refresh,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(20, top + 16, 20, 24),
                        children: [
                          _buildContextHeader(),
                          const SizedBox(height: 32),
                          _buildNovaOrbCenter(),
                          const SizedBox(height: 28),
                          _buildSecondaryPaths(),
                        ],
                      ),
                    ),
        ),
        if (_qaMessages.isNotEmpty || _qaLoading) _buildQaReplyArea(),
        _buildHomeChatInput(),
      ]),
    );
  }

  // ── Welcome screen ────────────────────────────────────────────────
  Widget _buildWelcomeScreen(double topPadding) {
    return Column(children: [
      SizedBox(height: topPadding),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Orb with glow — tap to dismiss
            GestureDetector(
              onTap: _dismissWelcome,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withOpacity(0.28),
                      blurRadius: 52,
                      spreadRadius: 16,
                    ),
                  ],
                ),
                child: SpeakingOrb(isSpeaking: _greetingPlayed, size: 140, onTap: _dismissWelcome),
              ),
            ),
            const SizedBox(height: 28),
            AnimatedOpacity(
              opacity: _showGreeting ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 700),
              child: Text(
                '$_greeting, $_firstName!',
                style: const TextStyle(
                  color: kText, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedOpacity(
              opacity: _showKhabar ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 700),
              child: const Text(
                'Apa khabar hari ini?',
                style: TextStyle(color: kMuted, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
      AnimatedSlide(
        offset: _showButtons ? Offset.zero : const Offset(0, 0.12),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _showButtons ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _buildSecondaryPaths(),
          ),
        ),
      ),
    ]);
  }

  // ── SECTION 1: Context header ─────────────────────────────────────
  Widget _buildContextHeader() {
    final subjectLabel = _firstSubject.isNotEmpty
        ? _subjectDisplayName(_firstSubject)
        : 'Pilih subjek';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$_greeting, $_firstName',
          style: const TextStyle(
            color: Color(0xFFE8ECF8),
            fontSize: 16,
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('$_formLevelLabel  •  $subjectLabel',
          style: const TextStyle(color: Color(0xFF4A5070), fontSize: 11)),
      ],
    );
  }

  // ── SECTION 2: Nova orb (hero, center) ───────────────────────────
  Widget _buildNovaOrbCenter() {
    return Center(
      child: Column(children: [
        SpeakingOrb(
          isSpeaking: false,
          size: 120,
          onTap: () async {
            final choice = await showSessionIntent(context);
            if (choice == null) return;
            switch (choice) {
              case SessionIntent.lessons:
                _continueLesson();
              case SessionIntent.revision:
                _goToTutor();
              case SessionIntent.quiz:
                _openQuizScreen();
            }
          },
        ),
        const SizedBox(height: 16),
        Text(_getNovaGreeting(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFE8ECF8),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.4)),
        const SizedBox(height: 10),
        const Text('Ketuk untuk mula',
          style: TextStyle(
            color: Color(0xFF6A7A9A),
            fontSize: 11,
            fontStyle: FontStyle.italic)),
      ]),
    );
  }

  // ── SECTION 3: Action buttons ─────────────────────────────────────
  Widget _buildSecondaryPaths() {
    final resume    = _resumeData?['resume'] as Map<String, dynamic>?;
    final hasResume = _resumeData?['hasResume'] == true && resume != null;

    return Column(children: [
      // Primary CTA — gradient + shadow + tap scale
      _TapScaleButton(
        onTap: () { _dismissWelcome(); _continueLesson(); },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kPrimary, kPrimary2],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withOpacity(0.38),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Text(
            hasResume ? 'Sambung Belajar' : 'Mula Belajar',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      const SizedBox(height: 12),
      // Secondary row — 3 coloured cards
      Row(children: [
        _buildActionCard(
          icon: Icons.history_edu_rounded,
          label: 'Ulang Kaji',
          subtitle: 'Balik ke topik lepas',
          gradientColors: [kGreen, const Color(0xFF059669)],
          onTap: () { _dismissWelcome(); _goToLearnTab(); },
        ),
        const SizedBox(width: 10),
        _buildActionCard(
          icon: Icons.school_rounded,
          label: 'Tutor Nova',
          subtitle: 'Belajar konsep baru',
          gradientColors: [kPrimary, kPrimary2],
          onTap: () { _dismissWelcome(); _goToTutor(); },
        ),
        const SizedBox(width: 10),
        _buildActionCard(
          icon: Icons.quiz_rounded,
          label: 'Kuiz',
          subtitle: 'Uji kemahiran',
          gradientColors: [kYellow, const Color(0xFFD97706)],
          onTap: () { _dismissWelcome(); _openQuizScreen(); },
        ),
      ]),
    ]);
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    final base  = gradientColors[0];
    final shade = gradientColors[1];
    return Expanded(
      child: _TapScaleButton(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [base.withOpacity(0.15), shade.withOpacity(0.07)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: base.withOpacity(0.28)),
            boxShadow: [
              BoxShadow(
                color: base.withOpacity(0.14),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: base.withOpacity(0.32), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 10),
            Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kText, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted, fontSize: 10, height: 1.3)),
          ]),
        ),
      ),
    );
  }

  // ── SECTION 4: Q&A reply area ─────────────────────────────────────
  Widget _buildQaReplyArea() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._qaMessages.map((m) {
              final isUser = m['role'] == 'user';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                  children: [
                    if (!isUser) ...[
                      const Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 14),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isUser ? kPrimary.withOpacity(0.15) : kSurface2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(m['text'] ?? '',
                          style: const TextStyle(color: kText, fontSize: 13, height: 1.4)),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_qaLoading)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 14),
                  SizedBox(width: 8),
                  SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  // ── SECTION 5: Persistent chat input ──────────────────────────────
  Widget _buildHomeChatInput() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottom + 10),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _chatController,
            style: const TextStyle(color: kText, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Tanya Nova sesuatu...',
              hintStyle: const TextStyle(color: kMuted, fontSize: 14),
              filled: true,
              fillColor: kSurface2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _submitChat(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _submitChat,
          child: Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(
              color: kPrimary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }
}

// ── Tap-scale press animation ────────────────────────────────────────
class _TapScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _TapScaleButton({required this.child, required this.onTap});
  @override
  State<_TapScaleButton> createState() => _TapScaleButtonState();
}

class _TapScaleButtonState extends State<_TapScaleButton> {
  double _scale = 1.0;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown:  (_) => setState(() => _scale = 0.97),
    onTapUp:    (_) { setState(() => _scale = 1.0); widget.onTap(); },
    onTapCancel: () => setState(() => _scale = 1.0),
    child: AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 100),
      child: widget.child,
    ),
  );
}
