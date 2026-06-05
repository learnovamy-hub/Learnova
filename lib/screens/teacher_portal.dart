import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../screens/landing.dart';

class TeacherPortal extends StatefulWidget {
  const TeacherPortal({super.key});
  @override
  State<TeacherPortal> createState() => _TeacherPortalState();
}

class _TeacherPortalState extends State<TeacherPortal> {
  String _name = 'Teacher';
  bool _loading = true;
  bool _onboardingDone = false;
  Map<String, dynamic> _stats = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('student_name') ?? 'Teacher';
    final token = prefs.getString('token') ?? '';
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/teacher/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        setState(() => _onboardingDone = data['teacher']?['school'] != null);
      }
      if (_onboardingDone) {
        final r2 = await http.get(
          Uri.parse('$kApiUrl/api/teacher/dashboard'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (r2.statusCode == 200) setState(() => _stats = jsonDecode(r2.body));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LandingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: kBg, body: Center(child: CircularProgressIndicator(color: kGreen)));
    }
    if (!_onboardingDone) {
      return TeacherOnboardingScreen(onComplete: () => setState(() { _onboardingDone = true; _load(); }));
    }
    return _buildDashboard();
  }

  Widget _buildDashboard() {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          color: kSurface,
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: kGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.person_rounded, color: kGreen)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Welcome, $_name', style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
              const Text('Teacher Dashboard', style: TextStyle(color: kGreen, fontSize: 12)),
            ])),
            GestureDetector(onTap: _logout, child: const Icon(Icons.logout_rounded, color: kMuted)),
          ]),
        ),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
          Row(children: [
            _statCard('Lessons', '${_stats['lessons_uploaded'] ?? 0}', kPrimary),
            const SizedBox(width: 12),
            _statCard('Published', '${_stats['lessons_published'] ?? 0}', kGreen),
            const SizedBox(width: 12),
            _statCard('Quizzes', '${_stats['quizzes_created'] ?? 0}', kYellow),
          ]),
          const SizedBox(height: 16),
          if ((_stats['school'] ?? '').isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('My School', style: TextStyle(color: kMuted, fontSize: 11)),
                Text(_stats['school'] ?? '', style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          _actionBtn(context, Icons.upload_rounded, 'Upload Lesson / Pedagogy', 'Share your teaching approach and content', kGreen,
            () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload feature coming soon!')))),
          const SizedBox(height: 12),
          _actionBtn(context, Icons.topic_rounded, 'Choose Topics', 'Select curriculum topics to teach', kPrimary,
            () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Topic selection coming soon!')))),
          const SizedBox(height: 12),
          _actionBtn(context, Icons.rate_review_rounded, 'Audit Content', 'Review AI-generated lessons', kYellow,
            () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audit feature coming soon!')))),
          const SizedBox(height: 12),
          _actionBtn(context, Icons.people_rounded, 'View Students', 'See who is learning from you', kPrimary2,
            () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student view coming soon!')))),
        ]))),
      ])),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
      ]),
    ));
  }

  Widget _actionBtn(BuildContext ctx, IconData icon, String label, String sub, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kSurface, border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
            Text(sub, style: const TextStyle(color: kMuted, fontSize: 12)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, color: color, size: 14),
        ]),
      ),
    );
  }
}

class TeacherOnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const TeacherOnboardingScreen({super.key, required this.onComplete});
  @override
  State<TeacherOnboardingScreen> createState() => _TeacherOnboardingScreenState();
}

class _TeacherOnboardingScreenState extends State<TeacherOnboardingScreen> {
  final _schoolCtrl     = TextEditingController();
  final _qualCtrl       = TextEditingController();
  final _philosophyCtrl = TextEditingController();
  int _years = 1;
  List<String> _selectedSubjects = [];
  bool _loading = false;
  String _error = '';

  final List<String> _allSubjects = ['Mathematics', 'Add Maths', 'Physics', 'Biology', 'Chemistry', 'Geography', 'Sejarah', 'Bahasa Malaysia', 'English'];

  Future<void> _submit() async {
    if (_schoolCtrl.text.isEmpty || _selectedSubjects.isEmpty) {
      setState(() => _error = 'Please fill in school name and select at least one subject.');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final r = await http.post(
        Uri.parse('$kApiUrl/api/teacher/profile'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'school_name': _schoolCtrl.text.trim(),
          'subjects': _selectedSubjects,
          'years_experience': _years,
          'qualifications': _qualCtrl.text.trim(),
          'teaching_philosophy': _philosophyCtrl.text.trim(),
        }),
      );
      if (r.statusCode == 200) {
        widget.onComplete();
      } else {
        setState(() => _error = 'Failed to save profile. Please try again.');
      }
    } catch (_) {
      setState(() => _error = 'Connection error. Please try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: kText),
          onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LandingScreen())),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: kGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.school_rounded, color: kGreen, size: 26)),
            const SizedBox(height: 16),
            const Text('Welcome to Learnova!', style: TextStyle(color: kText, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Complete your teacher profile to get started.', style: TextStyle(color: kMuted, fontSize: 14, height: 1.5)),
            const SizedBox(height: 28),
            const Text('School Name', style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(controller: _schoolCtrl, style: const TextStyle(color: kText), decoration: const InputDecoration(hintText: 'e.g. SMK Taman Jaya', prefixIcon: Icon(Icons.business_rounded, color: kMuted, size: 20))),
            const SizedBox(height: 16),
            const Text('Subjects You Teach', style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: _allSubjects.map((s) {
              final selected = _selectedSubjects.contains(s);
              return GestureDetector(
                onTap: () => setState(() => selected ? _selectedSubjects.remove(s) : _selectedSubjects.add(s)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? kGreen.withOpacity(0.15) : kSurface,
                    border: Border.all(color: selected ? kGreen : kBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(s, style: TextStyle(color: selected ? kGreen : kMuted, fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
                ),
              );
            }).toList()),
            const SizedBox(height: 16),
            const Text('Years of Teaching Experience', style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              GestureDetector(onTap: () => setState(() => _years = (_years - 1).clamp(1, 40)), child: Container(width: 36, height: 36, decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.remove, color: kMuted, size: 18))),
              const SizedBox(width: 16),
              Text('$_years year${_years == 1 ? '' : 's'}', style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 16),
              GestureDetector(onTap: () => setState(() => _years = (_years + 1).clamp(1, 40)), child: Container(width: 36, height: 36, decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.add, color: kGreen, size: 18))),
            ]),
            const SizedBox(height: 16),
            const Text('Qualifications (optional)', style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(controller: _qualCtrl, style: const TextStyle(color: kText), decoration: const InputDecoration(hintText: 'e.g. B.Ed Mathematics, UTM', prefixIcon: Icon(Icons.workspace_premium_rounded, color: kMuted, size: 20))),
            const SizedBox(height: 16),
            const Text('Teaching Philosophy (optional)', style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(controller: _philosophyCtrl, style: const TextStyle(color: kText), maxLines: 3, decoration: const InputDecoration(hintText: 'What makes your teaching style unique?', alignLabelWithHint: true)),
            const SizedBox(height: 24),
            if (_error.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kRed.withOpacity(0.1), border: Border.all(color: kRed.withOpacity(0.3)), borderRadius: BorderRadius.circular(10)),
                child: Text(_error, style: const TextStyle(color: kRed, fontSize: 13)),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: kGreen, padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Complete Registration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _schoolCtrl.dispose();
    _qualCtrl.dispose();
    _philosophyCtrl.dispose();
    super.dispose();
  }
}
