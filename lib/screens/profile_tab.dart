import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../config/disclaimers.dart';
import 'auth.dart';
import 'landing.dart';
import 'student_id_screen.dart';
import 'payment_screen.dart';
import 'god_mode_screen.dart';
import 'parent_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic>? _profile;
  List<dynamic> _history = [];
  List<dynamic> _mySubjects = [];
  bool _trialMode = false;
  bool _loading = true;
  String? _token;
  String? _studentId;
  Map<String, dynamic> _activitySummary = {};
  // Hidden God Mode tap counter
  int _logoBadgeTaps = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token') ?? '';
    _studentId = prefs.getString('student_id');
    try {
      final r = await http.get(Uri.parse('$kApiUrl/api/student/profile'), headers: {'Authorization': 'Bearer $_token'});
      if (r.statusCode == 200) setState(() => _profile = jsonDecode(r.body));
      final r2 = await http.get(Uri.parse('$kApiUrl/api/student/quiz-history'), headers: {'Authorization': 'Bearer $_token'});
      if (r2.statusCode == 200) setState(() => _history = jsonDecode(r2.body));
      final r3 = await http.get(Uri.parse('$kApiUrl/api/payment/my-subjects'), headers: {'Authorization': 'Bearer $_token'})
          .timeout(const Duration(seconds: 8));
      if (r3.statusCode == 200) {
        final d = jsonDecode(r3.body);
        setState(() { _mySubjects = d['subjects'] ?? []; _trialMode = d['trial_mode'] == true; });
      }
      await _fetchActivitySummary();
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _fetchActivitySummary() async {
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/student/activity-summary?days=7'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        if (mounted) setState(() => _activitySummary = (d['summary'] as Map?)?.cast<String, dynamic>() ?? {});
      }
    } catch (_) {}
  }

  void _showFullDisclaimer() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Tentang Learnova AI', style: TextStyle(color: kText, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(child: Text(LearnovaDisclaimers.fullNotice, style: const TextStyle(color: kText, fontSize: 13, height: 1.6))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Faham', style: TextStyle(color: kPrimary)))],
    ));
  }

  void _showPrivacyNotice() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Privasi & Data', style: TextStyle(color: kText, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(child: Text(LearnovaDisclaimers.privacyNotice, style: const TextStyle(color: kText, fontSize: 13, height: 1.6))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Faham', style: TextStyle(color: kPrimary)))],
    ));
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingScreen()), (_) => false);
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
                    ((_profile?['student']?['name']?.toString().isNotEmpty ?? false) ? _profile!['student']['name'].toString().substring(0, 1).toUpperCase() : 'S'),
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
                // Student ID card — shows LRN ID inline + link to full card
                _buildStudentIdCard(),
                // Aktiviti 7 Hari
                _buildActivitySummary(),
                // Subjek Saya
                _subjectSection(),
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
                const SizedBox(height: 24),
                const Divider(color: kBorder),
                const SizedBox(height: 8),
                // About & Privacy
                Container(
                  decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded, color: kPrimary, size: 20),
                      title: const Text('Tentang Learnova', style: TextStyle(color: kText, fontSize: 14)),
                      subtitle: const Text('Notis platform dan terma penggunaan', style: TextStyle(color: kMuted, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: kMuted, size: 18),
                      onTap: _showFullDisclaimer,
                    ),
                    Divider(color: kBorder, height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined, color: kPrimary, size: 20),
                      title: const Text('Privasi & Data', style: TextStyle(color: kText, fontSize: 14)),
                      subtitle: const Text('Cara kami menggunakan data perbualan', style: TextStyle(color: kMuted, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: kMuted, size: 18),
                      onTap: _showPrivacyNotice,
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                // Hidden God Mode trigger — triple-tap the divider area
                GestureDetector(
                  onTap: () {
                    _logoBadgeTaps++;
                    if (_logoBadgeTaps >= 7) {
                      _logoBadgeTaps = 0;
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const GodModeScreen()));
                    }
                  },
                  child: const SizedBox(height: 20, width: double.infinity),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentScreen())),
                  child: const Text('Ibu Bapa? Pantau di sini →', style: TextStyle(color: kMuted, fontSize: 12)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
                    label: const Text(
                      'Log Out',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 60),
              ]),
            ),
    );
  }

  Widget _buildStudentIdCard() {
    final lrnId = _profile?['student']?['learnova_id']?.toString() ?? '';
    final displayId = lrnId.isNotEmpty ? lrnId : (_profile?['student']?['student_code']?.toString() ?? '');
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [kPrimary.withOpacity(0.12), kPrimary2.withOpacity(0.08)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPrimary.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.badge_rounded, color: kPrimary, size: 18),
          const SizedBox(width: 8),
          const Text('ID Pelajar', style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentIdScreen())),
            child: const Text('Lihat Kad →', style: TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 10),
        if (displayId.isNotEmpty) ...[
          Row(children: [
            Text(displayId, style: const TextStyle(color: kText, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2, fontFamily: 'monospace')),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: displayId));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Disalin: $displayId'),
                  backgroundColor: kGreen,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  duration: const Duration(seconds: 2),
                ));
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.copy_rounded, color: kPrimary, size: 16),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('Kongsi ID ini dengan ibu bapa untuk pantauan pembelajaran', style: TextStyle(color: kMuted, fontSize: 11)),
        ] else
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentIdScreen())),
            child: const Text('Lihat Student ID Card →', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  Widget _buildActivitySummary() {
    final s = _activitySummary;
    if (s.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Aktiviti 7 Hari',
          style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Row(children: [
        _activityCard('Sesi', '${s['total_sessions'] ?? 0}', Icons.school_rounded, kPrimary),
        const SizedBox(width: 10),
        _activityCard('Topik', '${s['topics_studied'] ?? 0}', Icons.menu_book_rounded, const Color(0xFF10B981)),
        const SizedBox(width: 10),
        _activityCard('Streak', '${s['study_streak'] ?? 0}🔥', Icons.local_fire_department_rounded, const Color(0xFFFF6B35)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _activityCard('Kuiz', '${s['quiz_attempts'] ?? 0}', Icons.quiz_rounded, const Color(0xFFF59E0B)),
        const SizedBox(width: 10),
        _activityCard('Tepat', '${s['quiz_accuracy'] ?? 0}%', Icons.check_circle_rounded, const Color(0xFF6366F1)),
        const SizedBox(width: 10),
        _activityCard('Selesai', '${s['topics_completed'] ?? 0}', Icons.emoji_events_rounded, const Color(0xFFEC4899)),
      ]),
      const SizedBox(height: 20),
    ]);
  }

  Widget _activityCard(String label, String value, IconData icon, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: kMuted, fontSize: 10)),
      ]),
    ));
  }

  Widget _subjectSection() {
    final activeSubjects = _mySubjects.where((s) => s['active'] == true).toList();
    final lockedSubjects = kSubjects
        .map((s) => s['name'] as String)
        .where((name) => !activeSubjects.any((a) => a['subject'] == name))
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Subjek Saya', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (_trialMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: kGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kGreen.withOpacity(0.3)),
            ),
            child: const Text('God Mode', style: TextStyle(color: kGreen, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentScreen()))
              .then((_) => _load()),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kPrimary.withOpacity(0.3)),
            ),
            child: const Text('+ Tambah', style: TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      if (activeSubjects.isEmpty && !_trialMode)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
          child: const Center(child: Text('Tiada subjek aktif. Tekan "+ Tambah" untuk mulakan percubaan percuma.',
              style: TextStyle(color: kMuted, fontSize: 13), textAlign: TextAlign.center)),
        )
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          ...(_trialMode ? kSubjects.map((s) => s['name'] as String) : activeSubjects.map((a) => a['subject'] as String))
              .map((subject) {
            final subjectInfo = kSubjects.firstWhere(
              (s) => s['name'] == subject, orElse: () => kSubjects.first);
            final color = Color(subjectInfo['color'] as int);
            final access = _trialMode ? {'access_type': 'god_mode', 'expires_at': null}
                : _mySubjects.firstWhere((a) => a['subject'] == subject, orElse: () => {});
            final type = access['access_type'] as String? ?? '';
            final exp = access['expires_at'] as String?;
            String badge = '';
            if (type == 'trial') badge = 'Trial';
            else if (type == 'god_mode') badge = '';
            else if (type == 'paid') badge = 'Berbayar';
            else if (type == 'admin_grant') badge = 'Diberi';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Column(children: [
                Text(subject, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                if (badge.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(badge, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10)),
                ],
                if (exp != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Hingga ${exp.substring(0, 10)}',
                    style: TextStyle(color: color.withOpacity(0.6), fontSize: 9),
                  ),
                ],
              ]),
            );
          }).toList(),
          // Locked subjects
          if (!_trialMode)
            ...lockedSubjects.map((subject) => GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentScreen()))
                  .then((_) => _load()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kSurface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: Column(children: [
                  Text(subject, style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  const Icon(Icons.lock_outline_rounded, color: kMuted, size: 10),
                ]),
              ),
            )).take(4).toList(), // show max 4 locked to keep it tidy
        ]),

    ]);
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

