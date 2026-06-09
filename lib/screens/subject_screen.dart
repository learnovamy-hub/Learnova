import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/constants.dart';
import 'topic_list_screen.dart';

class SubjectScreen extends StatefulWidget {
  const SubjectScreen({super.key});
  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  List<String> _activeSubjects = [];
  bool _loading = true;

  static const _nameToKey = {
    // BM display names (shown in UI)
    'Matematik':       'MY-Mathematics',
    'Fizik':           'MY-Physics',
    'Biologi':         'MY-Biology',
    'Kimia':           'MY-Chemistry',
    // English fallbacks (accepted from stored data)
    'Mathematics':     'MY-Mathematics',
    'Physics':         'MY-Physics',
    'Biology':         'MY-Biology',
    'Chemistry':       'MY-Chemistry',
    // Common to both
    'Add Maths':       'MY-AddMaths',
    'Sejarah':         'MY-Sejarah',
    'Bahasa Malaysia': 'MY-BahasaMalaysia',
    'English':         'MY-English',
  };
  static const _freeKeys = {'MY-BahasaMalaysia', 'MY-English'};

  // Subject descriptions shown under the name
  static const _subjectDesc = {
    'MY-Mathematics':     'Algebra, geometri, statistik & lebih',
    'MY-AddMaths':        'Fungsi, kalkulus & koordinat',
    'MY-Physics':         'Mekanik, elektrik, gelombang & lebih',
    'MY-Biology':         'Sel, ekosistem, genetik & lebih',
    'MY-Chemistry':       'Atom, tindak balas, organik & lebih',
    'MY-Sejarah':         'Sejarah Malaysia & dunia',
    'MY-BahasaMalaysia':  'Bahasa, sastera & tatabahasa',
    'MY-English':         'Grammar, writing & comprehension',
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('active_subjects');
    List<String> keys = [];
    if (raw != null) {
      try { keys = (jsonDecode(raw) as List).map((e) => e.toString()).toList(); } catch (_) {}
    }
    // Normalize display names to API keys (handles old stored data like 'Matematik', 'Fizik')
    keys = keys.map((k) => _nameToKey[k] ?? k).toSet().toList();
    for (final k in _freeKeys) {
      if (!keys.contains(k)) keys.add(k);
    }
    if (keys.isEmpty) keys = _nameToKey.values.toList();
    if (mounted) setState(() { _activeSubjects = keys; _loading = false; });
  }

  String _displayName(String key) =>
    _nameToKey.entries.firstWhere((e) => e.value == key, orElse: () => MapEntry(key, key)).key;

  Color _subjectColor(String key) {
    for (final s in kSubjects) {
      final k = _nameToKey[s['name'] as String] ?? '';
      if (k == key) return Color(s['color'] as int);
    }
    return kPrimary;
  }

  IconData _subjectIcon(String key) {
    switch (key) {
      case 'MY-Mathematics':    return Icons.calculate_outlined;
      case 'MY-AddMaths':       return Icons.functions_outlined;
      case 'MY-Physics':        return Icons.science_outlined;
      case 'MY-Biology':        return Icons.eco_outlined;
      case 'MY-Chemistry':      return Icons.biotech_outlined;
      case 'MY-Sejarah':        return Icons.history_edu_outlined;
      case 'MY-BahasaMalaysia': return Icons.translate_outlined;
      case 'MY-English':        return Icons.menu_book_outlined;
      default:                  return Icons.school_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: kBg,
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2))
        : Column(children: [
            SizedBox(height: top + 56),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Belajar', style: TextStyle(color: kText, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                const Text('Pilih subjek untuk mulakan pelajaran berstruktur',
                  style: TextStyle(color: kMuted, fontSize: 13)),
              ]),
            ),
            // Subject grid
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _activeSubjects.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final key = _activeSubjects[i];
                  return _buildSubjectCard(key);
                },
              ),
            ),
          ]),
    );
  }

  Widget _buildSubjectCard(String key) {
    final color = _subjectColor(key);
    final name  = _displayName(key);
    final desc  = _subjectDesc[key] ?? '';
    final icon  = _subjectIcon(key);

    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TopicListScreen(subjectKey: key, subjectName: name, subjectColor: color),
        )),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder),
          ),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(desc, style: const TextStyle(color: kMuted, fontSize: 12)),
            ])),
            Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.6), size: 22),
          ]),
        ),
      ),
    );
  }
}
