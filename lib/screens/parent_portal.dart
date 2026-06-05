import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../config/disclaimers.dart';
import 'landing.dart';
import 'parent_connect_screen.dart';

class ParentPortal extends StatefulWidget {
  const ParentPortal({super.key});
  @override
  State<ParentPortal> createState() => _ParentPortalState();
}

class _ParentPortalState extends State<ParentPortal> {
  String _parentName = 'Ibu Bapa';
  bool _loading = true;
  List<dynamic> _children = [];
  int _selectedIdx = 0;
  int _pendingCount = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _parentName = prefs.getString('name') ?? prefs.getString('student_name') ?? 'Ibu Bapa';
    final token = prefs.getString('token') ?? '';
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/parent/dashboard'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        _parentName = data['parent_name'] ?? _parentName;
        _children = (data['children'] as List?) ?? [];
        _pendingCount = data['pending_count'] ?? 0;
        if (_selectedIdx >= _children.length) _selectedIdx = 0;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LandingScreen()));
  }

  Map<String, dynamic> get _child => _children.isNotEmpty ? (_children[_selectedIdx] as Map<String, dynamic>) : {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(child: Column(children: [
        _buildHeader(),
        if (_children.length > 1) _buildChildSelector(),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: kYellow))
          : _children.isEmpty ? _buildNoChildren() : _buildDashboard()),
      ])),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      color: kSurface,
      child: Row(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(color: kYellow.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.family_restroom_rounded, color: kYellow)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_parentName', style: const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
          _pendingCount > 0
            ? Text('$_pendingCount permintaan sambungan', style: const TextStyle(color: kYellow, fontSize: 11, fontWeight: FontWeight.w600))
            : const Text('Dashboard Ibu Bapa', style: TextStyle(color: kMuted, fontSize: 11)),
        ])),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentConnectScreen())).then((_) => _load()),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: kPrimary.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: kPrimary.withOpacity(0.3))),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.person_add_rounded, color: kPrimary, size: 14),
              SizedBox(width: 4),
              Text('Sambung', style: TextStyle(color: kPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        GestureDetector(onTap: _logout, child: const Icon(Icons.logout_rounded, color: kMuted, size: 20)),
      ]),
    );
  }

  // ── Child selector ─────────────────────────────────────────────────────────

  Widget _buildChildSelector() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: List.generate(_children.length, (i) {
        final c = _children[i] as Map<String, dynamic>;
        final sel = i == _selectedIdx;
        return GestureDetector(
          onTap: () => setState(() => _selectedIdx = i),
          child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: sel ? kYellow.withOpacity(0.15) : kSurface2, border: Border.all(color: sel ? kYellow : kBorder), borderRadius: BorderRadius.circular(20)),
            child: Text(c['name'] ?? '—', style: TextStyle(color: sel ? kYellow : kMuted, fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500))),
        );
      }))),
    );
  }

  // ── Main dashboard scroll ──────────────────────────────────────────────────

  Widget _buildDashboard() {
    final child = _child;
    return RefreshIndicator(
      color: kYellow,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildDisclaimer(),
          const SizedBox(height: 12),
          _buildOverview(child),
          const SizedBox(height: 12),
          _buildSpmCountdown(child),
          const SizedBox(height: 12),
          _buildAlerts(child),
          const SizedBox(height: 12),
          _buildSubjectPerformance(child),
          const SizedBox(height: 12),
          _buildLearnovaComparison(child),
          const SizedBox(height: 12),
          _buildBehaviour(child),
          const SizedBox(height: 12),
          _buildActivityFeed(child),
          const SizedBox(height: 12),
          _buildRecommendations(child),
          const SizedBox(height: 12),
          _buildWellbeing(child),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1E3A5F), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3))),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFF60A5FA), size: 14),
        SizedBox(width: 8),
        Expanded(child: Text(LearnovaDisclaimers.parentNotice, style: TextStyle(fontSize: 11, color: Color(0xFFBFDBFE), height: 1.4))),
      ]),
    );
  }

  // ── Section 1: Child Overview ──────────────────────────────────────────────

  Widget _buildOverview(Map<String, dynamic> child) {
    final formLevel = child['form_level'] as int? ?? 0;
    final isActive  = child['is_active_now'] as bool? ?? false;
    final subjects  = (child['subjects'] as List?)?.cast<String>() ?? [];
    final streak    = child['streak'] as int? ?? 0;

    return _card(
      title: child['name'] ?? '—',
      icon: Icons.person_rounded, iconColor: kPrimary,
      trailing: isActive ? _activeBadge() : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, children: [
          _chip('Form $formLevel', kPrimary),
          if (child['student_code'] != null) _chip(child['student_code'].toString(), kMuted),
          if (child['enrolled_at'] != null) _chip('Daftar: ${child['enrolled_at']}', kMuted),
          _chip('🔥 $streak hari streak', kYellow),
        ]),
        if (subjects.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Subjek', style: TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: subjects.map((s) => _chip(s, kPrimary2)).toList()),
        ],
      ]),
    );
  }

  Widget _activeBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: kGreen.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: kGreen.withOpacity(0.4))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 5), decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle)),
      const Text('Aktif', style: TextStyle(color: kGreen, fontSize: 10, fontWeight: FontWeight.w700)),
    ]),
  );

  // ── Section 2: SPM Countdown ───────────────────────────────────────────────

  Widget _buildSpmCountdown(Map<String, dynamic> child) {
    final spm      = child['spm_countdown'] as Map<String, dynamic>? ?? {};
    final days     = spm['days_remaining'] as int? ?? 0;
    final coverage = ((spm['projected_coverage_pct'] as int?) ?? 0).clamp(0, 100);
    final urgency  = days < 60 ? kRed : days < 120 ? kYellow : kGreen;

    return _card(
      title: 'Kiraan Masa SPM 2026', icon: Icons.timer_rounded, iconColor: urgency,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('$days', style: TextStyle(color: urgency, fontSize: 42, fontWeight: FontWeight.w800, height: 1)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('hari', style: TextStyle(color: urgency.withOpacity(0.7), fontSize: 14)),
            Text('lagi', style: TextStyle(color: urgency.withOpacity(0.7), fontSize: 14)),
          ]),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$coverage%', style: const TextStyle(color: kGreen, fontSize: 24, fontWeight: FontWeight.w800)),
            const Text('silibus dianggar', style: TextStyle(color: kMuted, fontSize: 10)),
          ]),
        ]),
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: coverage / 100, backgroundColor: kSurface2, color: kGreen, minHeight: 8)),
        const SizedBox(height: 6),
        const Text('Anggaran berdasarkan topik yang telah dipelajari', style: TextStyle(color: kMuted, fontSize: 10)),
      ]),
    );
  }

  // ── Section 3: Smart Alerts ────────────────────────────────────────────────

  Widget _buildAlerts(Map<String, dynamic> child) {
    final alerts = (child['alerts'] as List?) ?? [];
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('Notifikasi Penting', Icons.notifications_active_rounded, kYellow),
      const SizedBox(height: 8),
      ...alerts.map((a) {
        final alert = a as Map<String, dynamic>;
        final sev = alert['severity'] as String? ?? 'info';
        late Color bg, border, fg; late IconData ic;
        switch (sev) {
          case 'danger':  bg = kRed.withOpacity(0.08);    border = kRed.withOpacity(0.3);    fg = const Color(0xFFFC8181); ic = Icons.warning_rounded; break;
          case 'warning': bg = kYellow.withOpacity(0.08); border = kYellow.withOpacity(0.3); fg = kYellow; ic = Icons.info_rounded; break;
          case 'success': bg = kGreen.withOpacity(0.08);  border = kGreen.withOpacity(0.3);  fg = kGreen; ic = Icons.star_rounded; break;
          case 'amber':   bg = const Color(0xFFF97316).withOpacity(0.08); border = const Color(0xFFF97316).withOpacity(0.3); fg = const Color(0xFFFB923C); ic = Icons.bolt_rounded; break;
          default:        bg = kPrimary.withOpacity(0.08); border = kPrimary.withOpacity(0.3); fg = kPrimary; ic = Icons.lightbulb_rounded;
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
          child: Row(children: [
            Icon(ic, color: fg, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(alert['message'] ?? '', style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
        );
      }),
    ]);
  }

  // ── Section 4: Subject Performance ────────────────────────────────────────

  Widget _buildSubjectPerformance(Map<String, dynamic> child) {
    final perfs = (child['subject_performance'] as List?) ?? [];
    if (perfs.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('Prestasi Mengikut Subjek', Icons.bar_chart_rounded, kPrimary),
      const SizedBox(height: 8),
      ...perfs.map((p) {
        final perf  = p as Map<String, dynamic>;
        final score = perf['avg_score'] as int?;
        final trend = perf['trend'] as String? ?? 'stable';
        final done  = perf['topics_done'] as int? ?? 0;
        final total = perf['topics_total'] as int? ?? 20;
        final weak  = (perf['weakest_concepts'] as List?)?.cast<String>() ?? [];

        final scoreColor = score == null ? kMuted : score >= 70 ? kGreen : score >= 50 ? kYellow : kRed;
        final trendColor = trend == 'up' ? kGreen : trend == 'down' ? kRed : kMuted;
        final trendIcon  = trend == 'up' ? Icons.trending_up_rounded : trend == 'down' ? Icons.trending_down_rounded : Icons.trending_flat_rounded;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(perf['subject'] ?? '—', style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w700))),
              if (score != null) ...[
                Text('$score%', style: TextStyle(color: scoreColor, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Icon(trendIcon, color: trendColor, size: 18),
              ] else
                const Text('—', style: TextStyle(color: kMuted, fontSize: 16)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Text('${perf['sessions'] ?? 0} sesi', style: const TextStyle(color: kMuted, fontSize: 11)),
              const SizedBox(width: 12),
              Expanded(child: Row(children: [
                Text('$done/$total topik  ', style: const TextStyle(color: kMuted, fontSize: 11)),
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: total > 0 ? (done / total).clamp(0.0, 1.0) : 0, backgroundColor: kSurface2, color: kPrimary, minHeight: 4))),
              ])),
            ]),
            if (weak.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.flag_rounded, color: kRed, size: 12),
                const SizedBox(width: 4),
                Expanded(child: Text('Lemah: ${weak.join(', ')}', style: const TextStyle(color: Color(0xFFFC8181), fontSize: 11))),
              ]),
            ],
          ]),
        );
      }),
    ]);
  }

  // ── Section 5: Learnova Average Comparison ────────────────────────────────

  Widget _buildLearnovaComparison(Map<String, dynamic> child) {
    final comp = child['learnova_comparison'] as Map<String, dynamic>? ?? {};
    if (comp.isEmpty) return const SizedBox.shrink();
    return _card(
      title: 'Perbandingan dengan Pelajar Learnova', icon: Icons.people_rounded, iconColor: kPrimary2,
      child: Column(children: comp.entries.map((e) {
        final d = e.value as Map<String, dynamic>;
        final yours = d['your_score'] as int? ?? 0;
        final avg   = d['learnova_avg'] as int? ?? 0;
        final diff  = d['diff'] as int? ?? 0;
        final above = diff >= 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(e.key, style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: above ? kGreen.withOpacity(0.15) : kRed.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text('${above ? '+' : ''}$diff%', style: TextStyle(color: above ? kGreen : kRed, fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const SizedBox(width: 36, child: Text('Kamu', style: TextStyle(color: kMuted, fontSize: 10))),
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: yours / 100, backgroundColor: kSurface2, color: kPrimary, minHeight: 6))),
              const SizedBox(width: 6),
              SizedBox(width: 32, child: Text('$yours%', textAlign: TextAlign.right, style: const TextStyle(color: kPrimary, fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const SizedBox(width: 36, child: Text('Avg', style: TextStyle(color: kMuted, fontSize: 10))),
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: avg / 100, backgroundColor: kSurface2, color: kMuted, minHeight: 6))),
              const SizedBox(width: 6),
              SizedBox(width: 32, child: Text('$avg%', textAlign: TextAlign.right, style: const TextStyle(color: kMuted, fontSize: 11))),
            ]),
          ]),
        );
      }).toList()),
    );
  }

  // ── Section 6: Behaviour Patterns ─────────────────────────────────────────

  Widget _buildBehaviour(Map<String, dynamic> child) {
    final beh     = child['behaviour'] as Map<String, dynamic>? ?? {};
    final hourRaw = beh['peak_study_hour'];
    final avgMins = beh['avg_session_minutes'] as int? ?? 0;
    final topics  = (beh['most_reviewed_topics'] as List?)?.cast<String>() ?? [];
    final days    = (beh['productive_days'] as List?)?.cast<String>() ?? [];
    if (hourRaw == null && avgMins == 0 && topics.isEmpty) return const SizedBox.shrink();

    String peakLabel = '—';
    if (hourRaw != null) {
      final h = hourRaw as int;
      peakLabel = h == 0 ? '12 Malam' : h < 12 ? '$h Pagi' : h == 12 ? 'Tengah Hari' : '${h - 12} Petang';
    }

    return _card(
      title: 'Tabiat Pembelajaran', icon: Icons.psychology_rounded, iconColor: const Color(0xFF9C27B0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _statTile(Icons.schedule_rounded, 'Waktu Puncak', peakLabel, kPrimary),
          const SizedBox(width: 10),
          _statTile(Icons.av_timer_rounded, 'Purata Sesi', '$avgMins min', kGreen),
        ]),
        if (days.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Hari Paling Produktif', style: TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: days.map((d) => _chip(d, kYellow)).toList()),
        ],
        if (topics.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Topik Sering Dikaji', style: TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: topics.map((t) => _chip(t, kPrimary2)).toList()),
        ],
      ]),
    );
  }

  Widget _statTile(IconData icon, String label, String value, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: kMuted, fontSize: 10)),
      ]),
    ));
  }

  // ── Section 7: Activity Feed ───────────────────────────────────────────────

  Widget _buildActivityFeed(Map<String, dynamic> child) {
    final feed = (child['activity_feed'] as List?) ?? [];
    if (feed.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('Aktiviti Terkini', Icons.timeline_rounded, kGreen),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
        child: Column(children: feed.take(8).map((a) {
          final act = a as Map<String, dynamic>;
          final isSess = act['type'] == 'session';
          final topics = (act['topics'] as List?)?.cast<String>() ?? [];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 32, height: 32,
                decoration: BoxDecoration(color: isSess ? kPrimary.withOpacity(0.12) : kGreen.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(isSess ? Icons.menu_book_rounded : Icons.quiz_rounded, color: isSess ? kPrimary : kGreen, size: 16)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  isSess
                    ? '${act['subject'] ?? ''}${topics.isNotEmpty ? " — ${topics.first}" : ""}'
                    : 'Kuiz ${act['subject'] ?? ''}${act['topic'] != null ? " (${act['topic']})" : ""}',
                  style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  isSess
                    ? '${act['minutes'] ?? 0} min${act['quiz_score'] != null ? " · Kuiz: ${act['quiz_score']}%" : ""}'
                    : '${act['score'] ?? 0}/${act['total'] ?? 0} betul · ${act['percentage'] ?? 0}%',
                  style: const TextStyle(color: kMuted, fontSize: 11)),
              ])),
              Text(_fmtDateTime(act['at']?.toString()), style: const TextStyle(color: kMuted, fontSize: 10)),
            ]),
          );
        }).toList()),
      ),
    ]);
  }

  // ── Section 8: AI Recommendations ─────────────────────────────────────────

  Widget _buildRecommendations(Map<String, dynamic> child) {
    final recs = (child['recommendations'] as List?)?.cast<String>() ?? [];
    if (recs.isEmpty) return const SizedBox.shrink();
    const purple = Color(0xFF6C5CE7);
    return _card(
      title: 'Cadangan AI untuk Ibu Bapa', icon: Icons.auto_awesome_rounded, iconColor: purple,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Dihasilkan oleh AI Learnova berdasarkan prestasi terkini', style: TextStyle(color: kMuted, fontSize: 10)),
        const SizedBox(height: 12),
        ...recs.asMap().entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: purple.withOpacity(0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: purple.withOpacity(0.2))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 22, height: 22,
              decoration: BoxDecoration(color: purple.withOpacity(0.2), shape: BoxShape.circle),
              child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: purple, fontSize: 11, fontWeight: FontWeight.w800)))),
            const SizedBox(width: 10),
            Expanded(child: Text(e.value, style: const TextStyle(color: kText, fontSize: 12, height: 1.5))),
          ]),
        )),
      ]),
    );
  }

  // ── Section 9: Wellbeing ───────────────────────────────────────────────────

  Widget _buildWellbeing(Map<String, dynamic> child) {
    final wb     = child['wellbeing'] as Map<String, dynamic>? ?? {};
    final trend  = wb['confidence_trend'] as String? ?? 'stable';
    final mAvg   = wb['mastery_avg'] as int?;
    final lowTop = (wb['low_mastery_topics'] as List?)?.cast<String>() ?? [];
    if (mAvg == null && lowTop.isEmpty) return const SizedBox.shrink();

    Color tColor; String tLabel; IconData tIcon;
    switch (trend) {
      case 'improving': tColor = kGreen; tLabel = 'Meningkat';  tIcon = Icons.trending_up_rounded; break;
      case 'declining': tColor = kRed;   tLabel = 'Menurun';    tIcon = Icons.trending_down_rounded; break;
      default:          tColor = kMuted; tLabel = 'Stabil';     tIcon = Icons.trending_flat_rounded;
    }

    return _card(
      title: 'Keyakinan & Kesejahteraan', icon: Icons.favorite_rounded, iconColor: const Color(0xFFEC4899),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(tIcon, color: tColor, size: 20),
          const SizedBox(width: 8),
          Text('Trend Keyakinan: $tLabel', style: TextStyle(color: tColor, fontSize: 13, fontWeight: FontWeight.w700)),
          if (mAvg != null) ...[
            const Spacer(),
            Text('Penguasaan: $mAvg%', style: const TextStyle(color: kMuted, fontSize: 12)),
          ],
        ]),
        if (mAvg != null) ...[
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: mAvg / 100, backgroundColor: kSurface2, color: tColor, minHeight: 6)),
        ],
        if (lowTop.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Topik yang Memerlukan Sokongan', style: TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: lowTop.map((t) => _chip(t, kRed)).toList()),
        ],
      ]),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _card({required String title, required IconData icon, required Color iconColor, required Widget child, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(color: iconColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 16)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w700))),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildNoChildren() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.family_restroom_rounded, color: kMuted, size: 64),
      const SizedBox(height: 16),
      const Text('Tiada anak yang dihubungkan', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Gunakan butang "Sambung" di atas untuk menghubungkan dengan anak anda', style: TextStyle(color: kMuted, fontSize: 13), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentConnectScreen())).then((_) => _load()),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Sambung dengan Anak'),
        style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
      ),
    ]),
  ));

  String _fmtDateTime(String? ts) {
    if (ts == null) return '';
    try {
      final d = DateTime.parse(ts).toLocal();
      final diff = DateTime.now().difference(d);
      if (diff.inDays == 0) return '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
      if (diff.inDays == 1) return 'Semalam';
      return '${d.day}/${d.month}';
    } catch (_) { return ''; }
  }
}
