import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

const _kBg     = Color(0xFF07080C);
const _kCard   = Color(0xFF0D1018);
const _kBorder = Color(0xFF181C28);
const _kBlue   = Color(0xFF4A7AFA);
const _kText   = Color(0xFFE8ECF8);
const _kMuted  = Color(0xFF4A5070);
const _kMuted2 = Color(0xFF8B949E);
const _kGreen  = Color(0xFF10B981);
const _kAmber  = Color(0xFFF59E0B);
const _kRed    = Color(0xFFEF4444);

class ParentScreen extends StatefulWidget {
  const ParentScreen({super.key});
  @override
  State<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends State<ParentScreen> {
  final _idCtrl = TextEditingController();
  bool _linking = false;
  String? _linkError;

  String? _studentId;
  Map<String, dynamic>? _data;
  bool _loadingDash = false;

  @override
  void initState() {
    super.initState();
    _checkSaved();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('parent_student_id');
    if (saved != null && saved.isNotEmpty) {
      setState(() => _studentId = saved);
      _loadDashboard(saved);
    }
  }

  Future<void> _link() async {
    final code = _idCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _linking = true; _linkError = null; });
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/parent/link'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'learnovaId': code}),
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final sid = d['studentId'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('parent_student_id', sid);
        setState(() { _studentId = sid; _linking = false; });
        await _loadDashboard(sid);
      } else {
        final e = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() { _linkError = e['error'] as String? ?? 'ID tidak dijumpai'; _linking = false; });
      }
    } catch (_) {
      setState(() { _linkError = 'Gagal menyambung. Cuba semula.'; _linking = false; });
    }
  }

  Future<void> _loadDashboard(String studentId) async {
    setState(() => _loadingDash = true);
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/parent/child-progress?studentId=$studentId'),
      ).timeout(const Duration(seconds: 25));
      if (r.statusCode == 200) {
        setState(() {
          _data = jsonDecode(r.body) as Map<String, dynamic>;
          _loadingDash = false;
        });
      } else {
        setState(() => _loadingDash = false);
      }
    } catch (_) {
      setState(() => _loadingDash = false);
    }
  }

  Future<void> _disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('parent_student_id');
    setState(() { _studentId = null; _data = null; _idCtrl.clear(); });
  }

  @override
  Widget build(BuildContext context) {
    if (_studentId == null) return _buildLinkScreen();
    if (_loadingDash || _data == null) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: CircularProgressIndicator(color: _kBlue, strokeWidth: 2)),
      );
    }
    return _buildDashboard();
  }

  // ── STATE A — linking screen ──────────────────────────────────────────────

  Widget _buildLinkScreen() {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.family_restroom_outlined, color: _kBlue, size: 32),
              const SizedBox(height: 16),
              const Text(
                'Pantau Pembelajaran Anak Kamu',
                style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Masukkan ID Pelajar anak kamu',
                style: TextStyle(color: _kMuted, fontSize: 12),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _idCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 10,
                style: const TextStyle(
                  color: _kText, fontSize: 16,
                  fontFamily: 'monospace', letterSpacing: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Contoh: LRN-123456',
                  hintStyle: const TextStyle(color: _kMuted, fontSize: 14, letterSpacing: 0.5),
                  counterText: '',
                  filled: true,
                  fillColor: _kCard,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorder, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBlue, width: 1),
                  ),
                ),
                onSubmitted: (_) => _link(),
              ),
              if (_linkError != null) ...[
                const SizedBox(height: 8),
                Text(_linkError!, style: const TextStyle(color: _kRed, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _linking ? null : _link,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _kBorder,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: _linking
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Hubungkan',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── STATE B — dashboard ───────────────────────────────────────────────────

  Widget _buildDashboard() {
    final d        = _data!;
    final child    = (d['child']   as Map?)?.cast<String, dynamic>() ?? {};
    final today    = (d['today']   as Map?)?.cast<String, dynamic>() ?? {};
    final thisWeek = (d['thisWeek'] as Map?)?.cast<String, dynamic>() ?? {};
    final spm      = (d['spmReadiness'] as Map?)?.cast<String, dynamic>() ?? {};
    final subjs    = ((d['subjects'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    final recent   = ((d['recentActivity'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    final summaryBm = (d['summary'] as Map?)?['bm'] as String?
        ?? d['summary'] as String? ?? '';

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: RefreshIndicator(
          color: _kBlue,
          backgroundColor: _kCard,
          onRefresh: () => _loadDashboard(_studentId!),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _buildChildInfo(child, today['isActiveToday'] as bool? ?? false),
              const SizedBox(height: 16),
              _buildTodayStats(today),
              const SizedBox(height: 12),
              _buildThisWeek(thisWeek),
              if (spm.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildSpmReadiness(spm),
              ],
              if (subjs.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildSubjectProgress(subjs),
              ],
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildRecentActivity(recent),
              ],
              const SizedBox(height: 12),
              _buildSummary(summaryBm),
              const SizedBox(height: 24),
              _buildDisconnect(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChildInfo(Map<String, dynamic> child, bool isActiveToday) {
    final name  = child['name']      as String? ?? 'Pelajar';
    final level = child['level']     as String? ?? '';
    final lrnId = child['studentId'] as String? ?? '';
    final subs  = (child['subjects'] as List?)?.length ?? 0;
    final days  = child['joinedDays'] as int? ?? 0;
    return Row(children: [
      Stack(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: _kCard, shape: BoxShape.circle,
            border: Border.all(color: _kBorder, width: 0.5),
          ),
          child: const Icon(Icons.person_outline_rounded, color: _kMuted, size: 18),
        ),
        Positioned(
          right: 0, bottom: 0,
          child: Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: isActiveToday ? _kGreen : _kMuted,
              shape: BoxShape.circle,
              border: Border.all(color: _kBg, width: 1.5),
            ),
          ),
        ),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(color: _kText, fontSize: 15, fontWeight: FontWeight.w600)),
        Text('$level · $subs subjek · $days hari',
          style: const TextStyle(color: _kMuted, fontSize: 11)),
      ])),
      Text('ID: $lrnId',
        style: const TextStyle(color: _kMuted, fontSize: 10, fontFamily: 'monospace')),
    ]);
  }

  Widget _buildTodayStats(Map<String, dynamic> today) {
    final mins    = today['studyMinutes']    as int? ?? 0;
    final lessons = today['lessonsCompleted'] as int? ?? today['topicsCompleted'] as int? ?? 0;
    final streak  = today['streak']           as int? ?? 0;
    final active  = today['isActiveToday']    as bool? ?? false;
    return Row(children: [
      _statBox('${mins}m', 'Belajar', active ? _kGreen : _kMuted),
      const SizedBox(width: 8),
      _statBox('$lessons', 'Pelajaran', _kBlue),
      const SizedBox(width: 8),
      _statBox('$streak', 'Streak', _kAmber, showFlame: true),
    ]);
  }

  Widget _statBox(String value, String label, Color color, {bool showFlame = false}) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          if (showFlame) ...[
            const SizedBox(width: 4),
            Icon(Icons.local_fire_department_rounded, color: color, size: 14),
          ],
        ]),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _kMuted, fontSize: 10)),
      ]),
    ));
  }

  Widget _buildThisWeek(Map<String, dynamic> thisWeek) {
    final totalMins = thisWeek['totalMinutes'] as int? ?? 0;
    final vsLast    = (thisWeek['vsLastWeek'] as Map?)?.cast<String, dynamic>() ?? {};
    final trend     = vsLast['trend'] as String? ?? 'same';
    final minDiff   = vsLast['minutesDiff'] as int? ?? 0;
    final daily     = ((thisWeek['dailyActivity'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();

    const labels = ['Is', 'Se', 'Ra', 'Kh', 'Ju', 'Sa', 'Ah'];
    final todayIdx = DateTime.now().weekday - 1; // Mon=0..Sun=6

    final trendColor = trend == 'up' ? _kGreen : trend == 'down' ? _kRed : _kMuted;
    final trendIcon  = trend == 'up' ? Icons.trending_up_rounded
        : trend == 'down' ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;
    final diffText = minDiff == 0 ? 'sama' : '${minDiff > 0 ? '+' : ''}$minDiff min';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('MINGGU INI',
            style: TextStyle(color: _kMuted, fontSize: 10, letterSpacing: 1.2)),
          const Spacer(),
          Icon(trendIcon, color: trendColor, size: 14),
          const SizedBox(width: 4),
          Text(diffText, style: TextStyle(color: trendColor, fontSize: 11)),
          Text(' vs minggu lalu', style: const TextStyle(color: _kMuted, fontSize: 10)),
        ]),
        const SizedBox(height: 8),
        Text('${totalMins}m belajar',
          style: const TextStyle(color: _kText, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: List.generate(7, (i) {
          final dayData = i < daily.length ? daily[i] : <String, dynamic>{};
          final studied = dayData['studied'] == true;
          final mins    = dayData['minutes'] as int? ?? 0;
          final isToday = i == todayIdx;
          final opacity = studied ? (mins > 30 ? 1.0 : mins > 10 ? 0.6 : 0.35) : 0.0;
          return Expanded(child: Column(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: studied ? _kBlue.withOpacity(opacity) : const Color(0xFF1E2230),
                border: isToday ? Border.all(color: _kBlue, width: 1.5) : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(labels[i], style: const TextStyle(color: _kMuted, fontSize: 9)),
          ]));
        })),
      ]),
    );
  }

  Widget _buildSpmReadiness(Map<String, dynamic> spm) {
    final days    = spm['daysRemaining']  as int? ?? 0;
    final pct     = spm['overallPercent'] as int? ?? 0;
    final grade   = spm['predictedGrade'] as String? ?? '-';
    final hours   = spm['hoursNeededToComplete'] as int? ?? 0;

    final gradeColor = grade.startsWith('A') ? _kGreen
        : grade.startsWith('B') ? _kAmber : _kRed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('KESEDIAAN SPM',
          style: TextStyle(color: _kMuted, fontSize: 10, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$pct%',
              style: const TextStyle(color: _kText, fontSize: 32, fontWeight: FontWeight.w800)),
            Text('$days hari lagi ke SPM',
              style: const TextStyle(color: _kMuted, fontSize: 12)),
            const SizedBox(height: 4),
            Text('Perlu ~${hours}j untuk siap',
              style: const TextStyle(color: _kMuted, fontSize: 11)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: gradeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: gradeColor.withOpacity(0.3)),
            ),
            child: Column(children: [
              Text(grade, style: TextStyle(color: gradeColor, fontSize: 24, fontWeight: FontWeight.w900)),
              Text('Jangkaan', style: TextStyle(color: gradeColor.withOpacity(0.7), fontSize: 9)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: const Color(0xFF12141A),
            valueColor: AlwaysStoppedAnimation<Color>(
              pct >= 60 ? _kGreen : pct >= 30 ? _kAmber : _kRed),
            minHeight: 4,
          ),
        ),
      ]),
    );
  }

  Widget _buildSubjectProgress(List<Map<String, dynamic>> subjects) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('SUBJEK',
        style: TextStyle(color: _kMuted, fontSize: 10, letterSpacing: 1.2)),
      const SizedBox(height: 10),
      ...subjects.map((s) {
        final name      = s['displayName'] as String? ?? s['subject'] as String? ?? '';
        final pct       = ((s['percentComplete'] as int?) ?? 0).clamp(0, 100);
        final mins      = s['minutesThisWeek'] as int? ?? 0;
        final completed = s['topicsCompleted'] as int? ?? 0;
        final total     = s['topicsTotal'] as int? ?? 0;
        final subLabel  = '$completed/$total pelajaran${mins > 0 ? ' · ${mins}m' : ''}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: _kText, fontSize: 12)),
              const SizedBox(height: 2),
              Text(subLabel, style: const TextStyle(color: _kMuted, fontSize: 9)),
            ])),
            Expanded(flex: 4, child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct / 100,
                backgroundColor: const Color(0xFF12141A),
                valueColor: const AlwaysStoppedAnimation<Color>(_kBlue),
                minHeight: 3,
              ),
            )),
            const SizedBox(width: 8),
            SizedBox(width: 35, child: Text('$pct%',
              textAlign: TextAlign.right,
              style: const TextStyle(color: _kMuted, fontSize: 11))),
          ]),
        );
      }),
    ]);
  }

  Widget _buildRecentActivity(List<Map<String, dynamic>> activities) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('AKTIVITI TERKINI',
        style: TextStyle(color: _kMuted, fontSize: 10, letterSpacing: 1.2)),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: _kCard, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder, width: 0.5),
        ),
        child: Column(
          children: activities.asMap().entries.map((entry) {
            final i = entry.key;
            final a = entry.value;
            final type    = a['type'] as String? ?? 'lesson';
            final subject = a['subject'] as String? ?? '';
            final topic   = a['topic'] as String? ?? '';
            final title   = a['title'] as String? ?? '';
            final ago     = a['minutesAgo'] as int? ?? 0;
            final score   = a['score'] as int?;

            final icon = type == 'nova' ? Icons.auto_awesome_outlined
                : type == 'quiz' ? Icons.quiz_outlined
                : Icons.menu_book_outlined;
            final iconColor = type == 'nova' ? const Color(0xFF8B5CF6)
                : type == 'quiz' ? _kAmber
                : _kBlue;

            String agoText = ago < 60 ? '${ago}m lepas'
                : ago < 1440 ? '${(ago / 60).floor()}j lepas'
                : '${(ago / 1440).floor()}h lepas';

            return Column(children: [
              if (i > 0) Divider(color: _kBorder, height: 1, indent: 48),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor, size: 14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (subject.isNotEmpty)
                      Text(subject,
                        style: const TextStyle(color: _kMuted, fontSize: 10)),
                    Text(
                      title.isNotEmpty ? title : topic.isNotEmpty ? topic : type,
                      style: const TextStyle(color: _kText, fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(agoText, style: const TextStyle(color: _kMuted, fontSize: 10)),
                    if (score != null) ...[
                      const SizedBox(height: 2),
                      Text('$score%',
                        style: TextStyle(
                          color: score >= 70 ? _kGreen : score >= 50 ? _kAmber : _kRed,
                          fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ]),
              ),
            ]);
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _buildSummary(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('RINGKASAN',
            style: TextStyle(color: _kMuted, fontSize: 10, letterSpacing: 1.2)),
          const Spacer(),
          GestureDetector(
            onTap: () => _loadDashboard(_studentId!),
            child: const Icon(Icons.refresh_rounded, color: _kMuted, size: 14),
          ),
        ]),
        const SizedBox(height: 8),
        Text(text,
          style: const TextStyle(color: _kMuted2, fontSize: 13, height: 1.6)),
      ]),
    );
  }

  Widget _buildDisconnect() {
    return Center(
      child: TextButton(
        onPressed: _disconnect,
        child: const Text(
          'Nyahsambung akaun ini',
          style: TextStyle(color: Color(0xFF3A4055), fontSize: 12),
        ),
      ),
    );
  }
}
