import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'main_shell.dart';
import 'lesson_screen.dart';
import 'ai_tutor_tab.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, dynamic>? _dash;
  Map<String, dynamic>? _nextLesson;
  Map<String, dynamic>? _resumeData;
  int _streak = 0;
  int _todayMinutes = 0;
  bool _loading = true;
  String _name = '';
  String _token = '';
  String _studentId = '';
  String _firstSubject = '';
  String _teachingLang = 'bm';

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    _token       = prefs.getString('token') ?? '';
    _name        = prefs.getString('student_name') ?? prefs.getString('name') ?? '';
    _studentId   = prefs.getString('student_id') ?? '';
    _teachingLang = prefs.getString('teaching_language') ?? 'bm';

    // Load active subjects to pick first one for next lesson
    final rawSubjects = prefs.getString('active_subjects');
    if (rawSubjects != null) {
      try {
        final list = (jsonDecode(rawSubjects) as List).map((e) => e.toString()).toList();
        if (list.isNotEmpty) _firstSubject = list.first;
      } catch (_) {}
    }
    if (_firstSubject.isEmpty) _firstSubject = 'MY-Mathematics';

    final cached   = prefs.getString('home_dash_cache');
    final cachedAt = prefs.getInt('home_dash_cached_at') ?? 0;
    if (cached != null && (DateTime.now().millisecondsSinceEpoch - cachedAt) < 1800000) {
      setState(() { _dash = jsonDecode(cached); _loading = false; });
      _loadNextLesson();
      return;
    }
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/home/dashboard'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        await prefs.setString('home_dash_cache', r.body);
        await prefs.setInt('home_dash_cached_at', DateTime.now().millisecondsSinceEpoch);
        setState(() => _dash = d);
      }
    } catch (_) {}
    setState(() => _loading = false);
    _loadNextLesson();
    _loadResumeData();
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
        setState(() {
          _resumeData    = d;
          _streak        = (d['streak']       as num?)?.toInt() ?? 0;
          _todayMinutes  = (d['todayMinutes'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadNextLesson() async {
    if (_studentId.isEmpty) return;
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/lessons/next?studentId=$_studentId&subject=${Uri.encodeComponent(_firstSubject)}'),
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
      _loading = true; _dash = null; _nextLesson = null;
      _resumeData = null; _streak = 0; _todayMinutes = 0;
    });
    await _loadDashboard();
  }

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
    // Additional male names
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
    'othman',
    'pasha',
    'qadir', 'qasim', 'qays', 'qamar', 'qawi', 'qudamah', 'qudus', 'qudrat', 'qamaruddin',
    'rahman', 'rashid', 'razi', 'rizqi', 'ruslan',
    'salim', 'sami', 'sani', 'saqib', 'sharif', 'siddiq', 'syakir', 'syazwan',
    'tariq', 'tahir', 'tamim', 'tarmizi',
    'uwais', 'ulwan', 'usamah', 'umair', 'ubay', 'ulfat',
    'wazir', 'wahab', 'wahid', 'wali', 'wajdi', 'wathiq', 'wajih',
    'yasir', 'yamin', 'yaqin', 'yazid', 'yunus', 'yumna',
    'zaid', 'zuhair', 'zamir', 'zuhdi', 'zainulabidin', 'zulqarnain',
    // Additional female names
    'balqis', 'baiduri',
    'damia', 'dana', 'durrah',
    'fatin', 'fiona',
    'ghayda',
    'haura', 'haya', 'humaira',
    'inara', 'imani', 'isya',
    'jauza', 'jihan', 'jannah',
    'kamilia', 'khalishah',
    'lafifah', 'latifah', 'leena', 'liyana', 'lubna',
    'maisarah', 'malika', 'marwa', 'mawar',
    'nadhirah', 'nayla', 'naimah', 'nathifa', 'nisrina', 'nabihah', 'nadeera', 'najla',
    'qaila', 'qairina',
    'rafidah', 'raidah', 'raihanah', 'rania',
    'safa', 'saidah', 'sakeena', 'salsabila', 'sameeha', 'sameera', 'samiyah', 'suhayla', 'syafia',
    'thahirah', 'talia',
    'ubaidah', 'ufairah', 'ulya', 'umaimah', 'uzma',
    'wafa', 'wardani',
    'yasmeen', 'yusrina',
    'zaaimah', 'zafirah', 'zahidah', 'zahiya', 'zahra', 'zara', 'zuhailin', 'zuhaira', 'zuyyin',
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
      final isMuslim = parts.any((p) =>
          _muslimIndicators.any((ind) =>
              p.startsWith(ind) || (ind.startsWith(p) && p.length >= 3)));
      if (isMuslim) return 'Assalamualaikum';
    }
    if (h < 12) return 'Selamat pagi';
    if (h < 17) return 'Selamat petang';
    return 'Selamat malam';
  }

  String get _greeting => getSmartGreeting(_name, teachingLang: _teachingLang);

  String get _firstName {
    if (_name.isEmpty) return 'Pelajar';
    final capitalised = _name.split(' ')
      .map((w) => w.isEmpty ? w :
        w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
    return capitalised.split(' ').first;
  }

  void _goToTutor({String? subject}) {
    final shell = context.findAncestorStateOfType<MainShellState>();
    if (shell == null) return;
    if (subject != null) shell.setSubject(subject);
    shell.setState(() => shell.currentIndex = 2);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: kBg,
      body: RefreshIndicator(
        color: kPrimary,
        backgroundColor: kSurface,
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2))
            : ListView(
                padding: EdgeInsets.fromLTRB(20, top + 60, 20, 100),
                children: [
                  _buildGreeting(),
                  const SizedBox(height: 24),
                  _buildContinueCard(),
                  const SizedBox(height: 20),
                  _buildStatsLine(),
                  const SizedBox(height: 28),
                  _buildMissions(),
                ],
              ),
      ),
    );
  }

  // ── 1. GREETING ROW ───────────────────────────────────────────────
  Widget _buildGreeting() {
    final days = (_dash?['spm_days_remaining'] as num?)?.toInt() ?? 142;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_greeting, style: const TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 2),
            Text(_firstName,
              style: const TextStyle(color: kText, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: kSurface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder),
          ),
          child: Text('SPM 2026 · $days hari',
            style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  // ── 2. CONTINUE LEARNING CARD ─────────────────────────────────────
  Widget _buildContinueCard() {
    final resume    = _resumeData?['resume'] as Map<String, dynamic>?;
    final hasResume = _resumeData?['hasResume'] == true && resume != null;

    if (hasResume) return _buildResumeCard(resume!);
    if (_nextLesson != null) return _buildNextLessonCard(_nextLesson!);
    return _buildStartCard();
  }

  Widget _buildResumeCard(Map<String, dynamic> resume) {
    final lessonId    = resume['lessonId']    as String? ?? '';
    final subject     = resume['subject']     as String? ?? '';
    final topic       = resume['topic']       as String? ?? '';
    final title       = resume['lessonTitle'] as String? ?? topic;
    final lastSection = resume['lastSection'] as String? ?? 'concept';
    final lastAccessed = resume['lastAccessed'] as String? ?? '';
    final minutesSpent = (resume['minutesSpent'] as num?)?.toInt() ?? 0;

    const sectionLabels = <String, String>{
      'concept':  'Bahagian Konsep',
      'example':  'Bahagian Contoh',
      'try_it':   'Soalan Cuba Kamu',
      'mistakes': 'Kesilapan Lazim',
      'exam_tip': 'Teknik SPM',
    };
    final sectionLabel = sectionLabels[lastSection] ?? 'Pelajaran';

    String timeAgo = '';
    if (lastAccessed.isNotEmpty) {
      try {
        final diff = DateTime.now().difference(DateTime.parse(lastAccessed));
        if (diff.inMinutes < 60) timeAgo = '${diff.inMinutes}m lepas';
        else if (diff.inHours < 24) timeAgo = '${diff.inHours}j lepas';
        else timeAgo = '${diff.inDays} hari lepas';
      } catch (_) {}
    }

    final subjectColor = _subjectColor(subject);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: subjectColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_subjectDisplayName(subject),
              style: TextStyle(color: subjectColor, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          if (timeAgo.isNotEmpty)
            Text(timeAgo, style: const TextStyle(color: kMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        Text(topic, style: const TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(title,
          style: const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.bookmark_outline_rounded, size: 12, color: kPrimary),
          const SizedBox(width: 4),
          Text('Berhenti di $sectionLabel',
            style: const TextStyle(color: kMuted, fontSize: 11)),
          if (minutesSpent > 0) ...[
            const Text(' · ', style: TextStyle(color: kMuted)),
            Text('${minutesSpent}m diluangkan',
              style: const TextStyle(color: kMuted, fontSize: 11)),
          ],
        ]),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (lessonId.isEmpty) { _goToLearnTab(); return; }
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => LessonScreen(lessonId: lessonId, subject: subject),
              )).then((_) { _loadResumeData(); _loadNextLesson(); });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Sambung semula →',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _buildNextLessonCard(Map<String, dynamic> nl) {
    final lessonId     = nl['id']                as String? ?? '';
    final topic        = nl['topic']             as String? ?? 'Topik Terkini';
    final title        = nl['lesson_title']      as String? ?? topic;
    final mins         = (nl['estimated_minutes'] as num?)?.toInt() ?? 15;
    final subjectColor = _subjectColor(_firstSubject);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: subjectColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_subjectDisplayName(_firstSubject),
              style: TextStyle(color: subjectColor, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          Text('~$mins min', style: const TextStyle(color: kMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        Text(topic, style: const TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(title,
          style: const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (lessonId.isNotEmpty) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => LessonScreen(lessonId: lessonId, subject: _firstSubject),
                )).then((_) { _loadResumeData(); _loadNextLesson(); });
              } else {
                _goToLearnTab();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Mula Pelajaran →',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _buildStartCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('MULAKAN PERJALANAN',
          style: TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        const Text('Pilih subjek untuk mula belajar',
          style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _goToLearnTab,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Pergi ke Learn →',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Color _subjectColor(String key) {
    const nameToKey = {
      'Mathematics': 'MY-Mathematics', 'Add Maths': 'MY-AddMaths',
      'Physics': 'MY-Physics', 'Biology': 'MY-Biology',
      'Chemistry': 'MY-Chemistry', 'Sejarah': 'MY-Sejarah',
      'Bahasa Malaysia': 'MY-BahasaMalaysia', 'English': 'MY-English',
    };
    for (final s in kSubjects) {
      final k = nameToKey[s['name'] as String] ?? '';
      if (k == key) return Color(s['color'] as int);
    }
    return kPrimary;
  }

  String _subjectDisplayName(String key) {
    const keyToName = {
      'MY-Mathematics': 'Mathematics', 'MY-AddMaths': 'Add Maths',
      'MY-Physics': 'Physics', 'MY-Biology': 'Biology',
      'MY-Chemistry': 'Chemistry', 'MY-Sejarah': 'Sejarah',
      'MY-BahasaMalaysia': 'Bahasa Malaysia', 'MY-English': 'English',
    };
    return keyToName[key] ?? key;
  }

  void _goToLearnTab() {
    final shell = context.findAncestorStateOfType<MainShellState>();
    shell?.setState(() => shell.currentIndex = 1);
  }

  // ── 2b. NOVA BANNER ──────────────────────────────────────────────
  Widget _buildNovaBanner() {
    final nl    = _nextLesson!;
    final topic = nl['topic'] as String? ?? nl['lesson_title'] as String? ?? 'pelajaran ini';
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => AITutorTab(
            selectedSubject: _firstSubject,
            lessonContext: {
              'lesson_id':           nl['id'] ?? '',
              'lesson_title':        nl['lesson_title'] ?? topic,
              'topic':               topic,
              'concept_explanation': nl['concept_explanation'] ?? '',
              'worked_example':      nl['worked_example'] ?? '',
              'try_it_question':     nl['try_it_question'] ?? '',
            },
          ),
        ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Sambung belajar $topic?',
              style: const TextStyle(color: kMuted, fontSize: 12),
              overflow: TextOverflow.ellipsis),
          ),
          const Text('Tanya Nova →',
            style: TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── 3. STATS LINE ─────────────────────────────────────────────────
  Widget _buildStatsLine() {
    final label = '${_fmtMins(_todayMinutes)} belajar · $_streak streak';
    return Center(
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(width: 2),
        const Icon(Icons.local_fire_department_rounded,
          color: Color(0xFFF59E0B), size: 13),
      ]),
    );
  }

  String _fmtMins(int mins) {
    if (mins < 60) return '${mins}m';
    return '${mins ~/ 60}j ${mins % 60}m';
  }

  // ── 4. OUTCOME ROW ────────────────────────────────────────────────
  Widget _buildOutcomeRow() {
    final hoursLeft = (_dash?['hours_to_complete'] as num?)?.toInt() ?? 78;
    final grade     = _dash?['predicted_grade'] as String? ?? 'B+';

    return Row(
      children: [
        Expanded(
          child: Text('Silabus selesai dalam $hoursLeft jam lagi',
            style: const TextStyle(color: kMuted, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kGreen.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kGreen.withOpacity(0.3)),
            ),
            child: Text(grade,
              style: const TextStyle(color: kGreen, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          const Text('SPM dijangka', style: TextStyle(color: kMuted, fontSize: 10)),
        ]),
      ],
    );
  }

  // ── 5. MISI HARI INI ──────────────────────────────────────────────
  Widget _buildMissions() {
    final resume      = _resumeData?['resume'] as Map<String, dynamic>?;
    final hasResume   = resume != null;
    final lastSection = hasResume ? resume['lastSection'] as String? ?? 'concept' : 'concept';

    final topic = hasResume
        ? resume['topic'] as String? ?? 'topik semasa'
        : _nextLesson?['topic'] as String? ?? 'topik semasa';
    final title = hasResume
        ? resume['lessonTitle'] as String? ?? topic
        : _nextLesson?['lesson_title'] as String? ?? topic;

    final bool mission1Done = _todayMinutes > 0 || hasResume;
    final bool mission2Done = lastSection == 'completed';

    final missions = [
      {'label': 'Buka Learnova hari ini',                'done': true,         'locked': false},
      {'label': hasResume ? 'Sambung: $title' : title,   'done': mission2Done, 'locked': false},
      {'label': 'Jawab soalan Cuba Kamu',                'done': false,        'locked': !mission1Done},
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('MISI HARI INI',
        style: TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 12),
      ...missions.map((m) {
        final label  = m['label'] as String? ?? '';
        final done   = m['done']   as bool? ?? false;
        final locked = m['locked'] as bool? ?? false;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            Icon(
              done   ? Icons.check_circle_rounded :
              locked ? Icons.radio_button_unchecked :
                       Icons.radio_button_unchecked,
              size: 16,
              color: done   ? kGreen  :
                     locked ? kBorder :
                              kPrimary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                style: TextStyle(
                  color:  done ? kMuted : locked ? kBorder : kText,
                  fontSize: 13,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: kMuted,
                )),
            ),
          ]),
        );
      }),
    ]);
  }
}
