import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'landing.dart';

class ParentPortal extends StatefulWidget {
  const ParentPortal({super.key});
  @override
  State<ParentPortal> createState() => _ParentPortalState();
}

class _ParentPortalState extends State<ParentPortal> {
  String _name = 'Parent';
  String _token = '';
  bool _loading = true;

  List<dynamic> _children = [];
  String? _selectedChildId;
  String _selectedChildName = '';

  // Session activity data (existing endpoint)
  Map<String, dynamic>? _sessionData;
  int _selectedDays = 7;

  // Quiz + AI summaries (new endpoint)
  List<dynamic> _quizResults = [];
  List<dynamic> _notifications = [];
  bool _quizLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('student_name') ?? 'Parent';
    _token = prefs.getString('token') ?? '';

    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/parent/dashboard'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        _children = (data['children'] as List?) ?? [];
        if (_children.isNotEmpty) {
          _selectedChildId = _children[0]['id']?.toString();
          _selectedChildName = _children[0]['name'] ?? 'Student';
          await Future.wait([
            _loadSessionData(),
            _loadQuizReports(),
          ]);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSessionData() async {
    if (_selectedChildId == null) return;
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/sessions/parent/$_selectedChildId?days=$_selectedDays'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200 && mounted) {
        setState(() => _sessionData = jsonDecode(r.body));
      }
    } catch (_) {}
  }

  Future<void> _loadQuizReports() async {
    if (_selectedChildId == null) return;
    if (mounted) setState(() => _quizLoading = true);
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/parent/session-reports/$_selectedChildId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200 && mounted) {
        final data = jsonDecode(r.body);
        setState(() {
          _quizResults   = (data['quiz_results']  as List?) ?? [];
          _notifications = (data['notifications'] as List?) ?? [];
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _quizLoading = false);
  }

  Future<void> _switchChild(String childId, String childName) async {
    setState(() {
      _selectedChildId   = childId;
      _selectedChildName = childName;
      _loading           = true;
      _quizResults       = [];
      _notifications     = [];
      _sessionData       = null;
    });
    await Future.wait([_loadSessionData(), _loadQuizReports()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _changeDays(int days) async {
    setState(() { _selectedDays = days; _loading = true; });
    await _loadSessionData();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LandingScreen()));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Map<String, dynamic> get _selectedChild {
    if (_selectedChildId == null) return {};
    return _children.firstWhere(
      (c) => c['id']?.toString() == _selectedChildId,
      orElse: () => {},
    ) as Map<String, dynamic>;
  }

  Color _scoreColor(int? pct) {
    if (pct == null) return kMuted;
    if (pct >= 80) return kGreen;
    if (pct >= 60) return kYellow;
    return kRed;
  }

  String _scoreLabel(int? pct) {
    if (pct == null) return 'No quizzes yet';
    if (pct >= 80) return 'Excellent';
    if (pct >= 60) return 'Good';
    if (pct >= 40) return 'Needs work';
    return 'Struggling';
  }

  String _formatDate(String? ts) {
    if (ts == null) return '';
    try {
      final d = DateTime.parse(ts).toLocal();
      return '${d.day}/${d.month}/${d.year.toString().substring(2)}';
    } catch (_) { return ''; }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(child: Column(children: [
        _buildHeader(),
        if (_children.length > 1) _buildChildSelector(),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: kYellow))
          : _children.isEmpty
            ? _buildNoChildren()
            : _buildDashboard()),
      ])),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      color: kSurface,
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: kYellow.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.family_restroom_rounded, color: kYellow),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Welcome, $_name',
              style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
          const Text('Parent Dashboard',
              style: TextStyle(color: kYellow, fontSize: 12)),
        ])),
        GestureDetector(
          onTap: _logout,
          child: const Icon(Icons.logout_rounded, color: kMuted),
        ),
      ]),
    );
  }

  Widget _buildChildSelector() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: _children.map((c) {
          final id       = c['id']?.toString() ?? '';
          final name     = c['name'] ?? 'Student';
          final selected = id == _selectedChildId;
          return GestureDetector(
            onTap: () => _switchChild(id, name),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? kYellow.withOpacity(0.15) : kSurface2,
                border: Border.all(color: selected ? kYellow : kBorder),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(name,
                style: TextStyle(
                  color: selected ? kYellow : kMuted, fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
            ),
          );
        }).toList()),
      ),
    );
  }

  Widget _buildDashboard() {
    final summary    = _sessionData?['summary']          as Map<String, dynamic>? ?? {};
    final bySubject  = _sessionData?['bySubject']        as Map<String, dynamic>? ?? {};
    final sessions   = _sessionData?['sessions']         as List? ?? [];

    final child       = _selectedChild;
    final avgScore    = child['avg_score'] as int?;
    final quizCount   = child['quiz_count'] as int? ?? 0;
    final latestSumm  = child['latest_summary'] as Map<String, dynamic>?;

    return RefreshIndicator(
      color: kYellow,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Child name + period selector ────────────────────────────────
          Row(children: [
            Text(_selectedChildName,
                style: const TextStyle(
                    color: kText, fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            ...[7, 14, 30].map((d) => GestureDetector(
              onTap: () => _changeDays(d),
              child: Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _selectedDays == d ? kYellow.withOpacity(0.15) : kSurface2,
                  border: Border.all(color: _selectedDays == d ? kYellow : kBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${d}d',
                  style: TextStyle(
                    color: _selectedDays == d ? kYellow : kMuted,
                    fontSize: 12,
                    fontWeight: _selectedDays == d ? FontWeight.w700 : FontWeight.w400)),
              ),
            )),
          ]),
          const SizedBox(height: 16),

          // ── Top stat row ────────────────────────────────────────────────
          Row(children: [
            _statCard('Study Time',
                '${summary['totalHours'] ?? 0}h',
                Icons.timer_rounded, kPrimary),
            const SizedBox(width: 10),
            _statCard('Sessions',
                '${summary['totalSessions'] ?? 0}',
                Icons.book_rounded, kGreen),
            const SizedBox(width: 10),
            _statCard('Avg Score',
                avgScore != null ? '$avgScore%' : '—',
                Icons.quiz_rounded,
                _scoreColor(avgScore)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _statCard('Quizzes Taken', '$quizCount',
                Icons.fact_check_rounded, kPrimary2),
            const SizedBox(width: 10),
            _statCard('Distractions',
                '${summary['totalStoppages'] ?? 0}',
                Icons.warning_rounded, kYellow),
            const SizedBox(width: 10),
            _statCard('Performance', _scoreLabel(avgScore),
                Icons.emoji_events_rounded, _scoreColor(avgScore)),
          ]),
          const SizedBox(height: 24),

          // ── Latest AI tutor summary ─────────────────────────────────────
          if (latestSumm != null) ...[
            _sectionTitle('Latest AI Report', Icons.auto_awesome_rounded, kPrimary),
            const SizedBox(height: 10),
            _buildLatestSummaryCard(latestSumm),
            const SizedBox(height: 24),
          ],

          // ── Quiz results ────────────────────────────────────────────────
          _sectionTitle('Quiz Results', Icons.quiz_rounded, kGreen),
          const SizedBox(height: 10),
          _buildQuizSection(),
          const SizedBox(height: 24),

          // ── AI summaries history ────────────────────────────────────────
          if (_notifications.isNotEmpty) ...[
            _sectionTitle('Tutor Updates', Icons.chat_bubble_outline_rounded, kPrimary),
            const SizedBox(height: 10),
            _buildNotificationsSection(),
            const SizedBox(height: 24),
          ],

          // ── Study time by subject ───────────────────────────────────────
          if (bySubject.isNotEmpty) ...[
            _sectionTitle('Time by Subject', Icons.bar_chart_rounded, kPrimary),
            const SizedBox(height: 8),
            ...bySubject.entries.map((e) => _progressBar(
              e.key, e.value as int,
              bySubject.values.fold(0, (s, v) => s + (v as int)),
              kPrimary)),
            const SizedBox(height: 24),
          ],

          // ── Recent sessions ─────────────────────────────────────────────
          if (sessions.isNotEmpty) ...[
            _sectionTitle('Recent Sessions', Icons.menu_book_rounded, kMuted),
            const SizedBox(height: 8),
            ...sessions.take(5).map((s) => _buildSessionRow(s)),
          ],

          if (sessions.isEmpty && _quizResults.isEmpty)
            _buildNoData(),

          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  // ── Latest summary card ──────────────────────────────────────────────────
  Widget _buildLatestSummaryCard(Map<String, dynamic> notif) {
    final pct     = notif['percentage'] as int?;
    final subject = notif['subject']    as String? ?? '';
    final topic   = notif['topic']      as String? ?? '';
    final summary = notif['summary']    as String? ?? '';
    final date    = _formatDate(notif['notified_at'] as String?);
    final color   = _scoreColor(pct);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimary.withOpacity(0.3)),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [kSurface, kPrimary.withOpacity(0.04)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(pct != null ? '$pct%' : '—',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(topic.isNotEmpty ? topic : subject,
              style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(subject, style: const TextStyle(color: kMuted, fontSize: 11)),
          ])),
          Text(date, style: const TextStyle(color: kMuted, fontSize: 11)),
        ]),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 14),
              const SizedBox(width: 8),
              Expanded(child: Text(summary,
                style: const TextStyle(
                    color: kText, fontSize: 13, height: 1.5))),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Quiz results section ─────────────────────────────────────────────────
  Widget _buildQuizSection() {
    if (_quizLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(color: kGreen, strokeWidth: 2),
        ),
      );
    }

    if (_quizResults.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(children: [
          Icon(Icons.hourglass_empty_rounded, color: kMuted, size: 20),
          SizedBox(width: 10),
          Text('No quizzes completed yet',
              style: TextStyle(color: kMuted, fontSize: 13)),
        ]),
      );
    }

    return Column(children: _quizResults.take(6).map((q) {
      final pct     = q['percentage'] as int? ?? 0;
      final score   = q['score']      as int? ?? 0;
      final total   = q['total']      as int? ?? 0;
      final subject = q['subject']    as String? ?? '';
      final topic   = q['topic']      as String? ?? subject;
      final date    = _formatDate(q['completed_at'] as String?);
      final color   = _scoreColor(pct);

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: color.withOpacity(0.25)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          // Score circle
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.1),
              border: Border.all(color: color.withOpacity(0.5), width: 2),
            ),
            child: Center(child: Text('$pct%',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(topic, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text('$subject  ·  $score/$total correct',
              style: const TextStyle(color: kMuted, fontSize: 11)),
          ])),
          // Date + bar
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(date, style: const TextStyle(color: kMuted, fontSize: 10)),
            const SizedBox(height: 6),
            SizedBox(
              width: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  backgroundColor: kSurface2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 5,
                ),
              ),
            ),
          ]),
        ]),
      );
    }).toList());
  }

  // ── AI notifications history ──────────────────────────────────────────────
  Widget _buildNotificationsSection() {
    return Column(children: _notifications.take(5).map((n) {
      final summary = n['summary']    as String? ?? '';
      final subject = n['subject']    as String? ?? '';
      final topic   = n['topic']      as String? ?? subject;
      final pct     = n['percentage'] as int?;
      final date    = _formatDate(n['notified_at'] as String?);
      final weakArr = n['weak_areas'] as List?;
      final weak    = weakArr?.isNotEmpty == true ? weakArr!.first.toString() : null;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text(
              topic.isNotEmpty ? '$topic · $subject' : subject,
              style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (pct != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _scoreColor(pct).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('$pct%',
                  style: TextStyle(
                    color: _scoreColor(pct), fontSize: 11,
                    fontWeight: FontWeight.w700)),
              ),
            ],
            const SizedBox(width: 6),
            Text(date, style: const TextStyle(color: kMuted, fontSize: 10)),
          ]),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(summary,
              style: const TextStyle(color: kMuted, fontSize: 12, height: 1.4)),
          ],
          if (weak != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  color: kYellow, size: 12),
              const SizedBox(width: 4),
              Expanded(child: Text(
                'Focus area: $weak',
                style: const TextStyle(color: kYellow, fontSize: 11),
                maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
          ],
        ]),
      );
    }).toList());
  }

  // ── Shared widgets ────────────────────────────────────────────────────────
  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 8),
        Text(value,
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label,
          style: const TextStyle(color: kMuted, fontSize: 10)),
      ]),
    ));
  }

  Widget _sectionTitle(String title, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 8),
      Text(title,
        style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _progressBar(String label, int value, int total, Color color) {
    final pct = total > 0 ? value / total : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface, border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label,
              style: const TextStyle(color: kText, fontSize: 12))),
          Text('$value min', style: const TextStyle(color: kMuted, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            backgroundColor: kSurface2, color: color, minHeight: 6)),
      ]),
    );
  }

  Widget _buildSessionRow(dynamic s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface, border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.menu_book_rounded, color: kPrimary, size: 16)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['topic'] ?? 'Unknown',
            style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${s['subject'] ?? ''}  ·  ${s['duration_minutes'] ?? 0} min',
            style: const TextStyle(color: kMuted, fontSize: 11)),
        ])),
        Text(_formatDate(s['created_at']?.toString()),
          style: const TextStyle(color: kMuted, fontSize: 10)),
      ]),
    );
  }

  Widget _buildNoChildren() {
    return const Center(child: Padding(
      padding: EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.family_restroom_rounded, color: kMuted, size: 64),
        SizedBox(height: 16),
        Text('No children linked yet',
          style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        Text(
          'Ask your child to add your email when signing up,\nor use their student ID to send a link request.',
          style: TextStyle(color: kMuted, fontSize: 13), textAlign: TextAlign.center),
      ]),
    ));
  }

  Widget _buildNoData() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kSurface, border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(14)),
      child: const Column(children: [
        Icon(Icons.bar_chart_rounded, color: kMuted, size: 48),
        SizedBox(height: 12),
        Text('No activity yet',
          style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('Data will appear once your child starts learning sessions',
          style: TextStyle(color: kMuted, fontSize: 12), textAlign: TextAlign.center),
      ]),
    );
  }
}
