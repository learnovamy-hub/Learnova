import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'auth.dart';
import 'landing.dart';

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
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    try {
      final r = await http.get(Uri.parse('$kApiUrl/api/student/profile'), headers: {'Authorization': 'Bearer $token'});
      if (r.statusCode == 200) setState(() => _profile = jsonDecode(r.body));
      final r2 = await http.get(Uri.parse('$kApiUrl/api/student/quiz-history'), headers: {'Authorization': 'Bearer $token'});
      if (r2.statusCode == 200) setState(() => _history = jsonDecode(r2.body));
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Preserve form cache across logout so WelcomeHome skips the form question
    // on next login — only remove auth credentials.
    final keysToKeep = prefs.getKeys()
        .where((k) => k.startsWith('student_form_'))
        .toList();
    final savedForms = { for (final k in keysToKeep) k: prefs.getString(k) };
    await prefs.clear();
    for (final entry in savedForms.entries) {
      if (entry.value != null) await prefs.setString(entry.key, entry.value!);
    }
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

