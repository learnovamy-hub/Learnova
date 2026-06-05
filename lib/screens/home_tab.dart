import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'main_shell.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, dynamic>? _dash;
  bool _loading = true;
  String _name = '';
  String _token = '';

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token') ?? '';
    _name  = prefs.getString('student_name') ?? prefs.getString('name') ?? '';

    final cached   = prefs.getString('home_dash_cache');
    final cachedAt = prefs.getInt('home_dash_cached_at') ?? 0;
    if (cached != null && (DateTime.now().millisecondsSinceEpoch - cachedAt) < 1800000) {
      setState(() { _dash = jsonDecode(cached); _loading = false; });
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
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('home_dash_cache');
    await prefs.remove('home_dash_cached_at');
    setState(() { _loading = true; _dash = null; });
    await _loadDashboard();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Selamat pagi';
    if (h < 17) return 'Selamat petang';
    return 'Selamat malam';
  }

  String get _firstName {
    if (_name.isEmpty) return 'Pelajar';
    return _name.split(' ').first;
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
                  const SizedBox(height: 20),
                  _buildOutcomeRow(),
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
    final resume = _dash?['resume_session'] as Map<String, dynamic>?;
    final subject = resume?['subject'] as String? ?? 'Mathematics';
    final topic   = resume?['topic']   as String? ?? 'Topik Terkini';
    final chapter = resume?['chapter'] as String? ?? subject;
    final pct     = (resume?['progress_percent'] as num?)?.toDouble() ?? 0.45;
    final mins    = (resume?['estimated_minutes'] as num?)?.toInt() ?? 12;

    final subjectColor = () {
      for (final s in kSubjects) {
        if (s['name'] == subject) return Color(s['color'] as int);
      }
      return kPrimary;
    }();

    return GestureDetector(
      onTap: () => _goToTutor(subject: subject),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$chapter',
            style: const TextStyle(color: kMuted, fontSize: 11)),
          const SizedBox(height: 6),
          Text(topic,
            style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: kSurface2,
              valueColor: AlwaysStoppedAnimation<Color>(subjectColor),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text('${(pct * 100).round()}% selesai · ~$mins minit lagi',
            style: const TextStyle(color: kMuted, fontSize: 11)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _goToTutor(subject: subject),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Teruskan belajar →',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 3. STATS LINE ─────────────────────────────────────────────────
  Widget _buildStatsLine() {
    final ws     = _dash?['weekly_stats'] as Map<String, dynamic>? ?? {};
    final mins   = (ws['study_minutes'] as num?)?.toInt() ?? 0;
    final topics = (ws['topics_completed'] as num?)?.toInt() ?? 0;
    final streak = (_dash?['streak'] as num?)?.toInt() ?? 0;

    final label = '${_fmtMins(mins)} belajar · $topics topik · $streak streak 🔥';
    return Center(
      child: Text(label,
        style: const TextStyle(color: kMuted, fontSize: 12)),
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
    final raw     = _dash?['daily_missions'] as List<dynamic>?;
    final missions = raw != null && raw.isNotEmpty
        ? raw
        : [
            {'label': 'Semak semula Algebra',       'done': true,  'locked': false},
            {'label': 'Habiskan Consumer Mathematics','done': false, 'locked': false},
            {'label': 'Kuiz 10 soalan',              'done': false, 'locked': true},
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
