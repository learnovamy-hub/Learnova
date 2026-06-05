import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class TopicIntroScreen extends StatefulWidget {
  final String subject;
  final String topic;
  final Map<String, dynamic> lessonData;
  final VoidCallback? onStartAiTutor;

  const TopicIntroScreen({
    super.key,
    required this.subject,
    required this.topic,
    required this.lessonData,
    this.onStartAiTutor,
  });

  @override
  State<TopicIntroScreen> createState() => _TopicIntroScreenState();
}

class _TopicIntroScreenState extends State<TopicIntroScreen> {
  final ScrollController _scroll = ScrollController();
  List<Map<String, dynamic>> _chunks = [];
  bool _readMarked = false;
  String? _studentId;

  // Maps either lessons or concept_chunks fields
  String get _intro => (widget.lessonData['concept_explanation'] ?? widget.lessonData['introduction'] ?? '').toString();
  String get _examples => (widget.lessonData['worked_example'] ?? widget.lessonData['worked_examples'] ?? '').toString();
  String get _mistakes => (widget.lessonData['common_mistakes'] ?? '').toString();
  String get _summary => (widget.lessonData['summary'] ?? '').toString();
  String get _checkIn => (widget.lessonData['check_in_question'] ?? '').toString();

  List<String> get _keywords {
    final kw = widget.lessonData['keywords'];
    if (kw is List) return kw.map((k) => k.toString()).where((k) => k.isNotEmpty).toList();
    if (kw is String && kw.isNotEmpty) return kw.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    return [];
  }

  bool get _hasContent => _intro.isNotEmpty || _examples.isNotEmpty || _mistakes.isNotEmpty || _chunks.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadStudentId();
    _fetchChunks();
    _scroll.addListener(_trackScroll);
  }

  Future<void> _loadStudentId() async {
    final prefs = await SharedPreferences.getInstance();
    _studentId = prefs.getString('student_id') ?? prefs.getString('userId');
  }

  Future<void> _fetchChunks() async {
    try {
      final r = await http.get(Uri.parse(
        '$kApiUrl/api/tutor/content-chunks?subject=${Uri.encodeComponent(widget.subject)}&topic=${Uri.encodeComponent(widget.topic)}',
      )).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200 && mounted) {
        final data = jsonDecode(r.body);
        final list = (data['chunks'] as List?) ?? [];
        setState(() => _chunks = list.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
  }

  void _trackScroll() {
    if (_readMarked) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    if (_scroll.position.pixels >= max * 0.75) {
      _readMarked = true;
      _markRead();
    }
  }

  Future<void> _markRead() async {
    if (_studentId == null || _studentId!.isEmpty) return;
    try {
      await http.post(
        Uri.parse('$kApiUrl/api/student/topic-read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'student_id': _studentId, 'subject': widget.subject, 'topic': widget.topic}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subjectInfo = kSubjects.firstWhere(
      (s) => s['name'] == widget.subject,
      orElse: () => kSubjects.first,
    );
    final subjectColor = Color(subjectInfo['color'] as int);
    final icon = subjectInfo['icon'] as String? ?? '📚';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(widget.topic, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: subjectColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: subjectColor.withOpacity(0.4)),
            ),
            child: Text(widget.subject, style: TextStyle(color: subjectColor, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Column(children: [
        // Progress step indicator
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(children: [
            _stepChip('1', 'Baca', true),
            Expanded(child: Container(height: 1, color: kBorder)),
            _stepChip('2', 'AI Tutor', false),
          ]),
        ),

        Expanded(child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Hero header
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: subjectColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: subjectColor.withOpacity(0.4)),
                ),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 24))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.topic, style: const TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                const Text('Baca pengenalan ini sebelum bermula dengan AI Tutor', style: TextStyle(color: kMuted, fontSize: 11)),
              ])),
            ]),
            const SizedBox(height: 24),

            if (!_hasContent) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
                child: const Column(children: [
                  Icon(Icons.menu_book_rounded, color: kMuted, size: 48),
                  SizedBox(height: 12),
                  Text('Kandungan sedang disediakan', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text('Mulakan dengan AI Tutor — Nova akan ajar topik ini secara interaktif.', style: TextStyle(color: kMuted, fontSize: 13), textAlign: TextAlign.center),
                ]),
              ),
              const SizedBox(height: 24),
            ] else ...[

              // Section 1: Introduction (from lessonData)
              if (_intro.isNotEmpty) ...[
                _sectionHeader('Pengenalan', Icons.lightbulb_outline_rounded, kPrimary),
                const SizedBox(height: 10),
                _textBlock(_intro),
                const SizedBox(height: 22),
              ],

              // Section 2: Concept chunks (additional detail from concept_chunks table)
              if (_chunks.isNotEmpty) ...[
                _sectionHeader('Konsep Utama', Icons.school_rounded, subjectColor),
                const SizedBox(height: 10),
                ..._chunks.where((c) => (c['concept_explanation'] as String? ?? '').isNotEmpty).map((c) =>
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: subjectColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: subjectColor.withOpacity(0.2)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((c['concept_title'] as String? ?? '').isNotEmpty)
                        Text(c['concept_title'] as String,
                          style: TextStyle(color: subjectColor, fontSize: 13, fontWeight: FontWeight.w700)),
                      if ((c['concept_title'] as String? ?? '').isNotEmpty) const SizedBox(height: 6),
                      Text(c['concept_explanation'] as String,
                        style: const TextStyle(color: kText, fontSize: 13, height: 1.7)),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Section 3: Worked Examples
              if (_examples.isNotEmpty || _chunks.any((c) => (c['worked_example'] as String? ?? '').isNotEmpty)) ...[
                _sectionHeader('Contoh Penyelesaian', Icons.calculate_rounded, kGreen),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kGreen.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kGreen.withOpacity(0.25)),
                  ),
                  child: Text(
                    _examples.isNotEmpty ? _examples
                      : (_chunks.firstWhere((c) => (c['worked_example'] as String? ?? '').isNotEmpty, orElse: () => {})['worked_example'] ?? ''),
                    style: const TextStyle(color: kText, fontSize: 14, height: 1.75)),
                ),
                const SizedBox(height: 22),
              ],

              // Section 4: Common Mistakes
              if (_mistakes.isNotEmpty || _chunks.any((c) => (c['common_mistakes'] as String? ?? '').isNotEmpty)) ...[
                _sectionHeader('Kesilapan Lazim', Icons.warning_amber_rounded, kRed),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kRed.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kRed.withOpacity(0.25)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.info_outline_rounded, color: kRed, size: 13),
                      SizedBox(width: 6),
                      Text('Elakkan kesilapan ini dalam peperiksaan!', style: TextStyle(color: kRed, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      _mistakes.isNotEmpty ? _mistakes
                        : (_chunks.firstWhere((c) => (c['common_mistakes'] as String? ?? '').isNotEmpty, orElse: () => {})['common_mistakes'] ?? ''),
                      style: const TextStyle(color: kText, fontSize: 13, height: 1.7)),
                  ]),
                ),
                const SizedBox(height: 22),
              ],

              // Section 5: Keywords
              if (_keywords.isNotEmpty) ...[
                _sectionHeader('Kata Kunci', Icons.key_rounded, kYellow),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8, runSpacing: 6,
                  children: _keywords.map((k) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: kYellow.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kYellow.withOpacity(0.4)),
                    ),
                    child: Text(k, style: const TextStyle(color: kYellow, fontSize: 12, fontWeight: FontWeight.w600)),
                  )).toList(),
                ),
                const SizedBox(height: 22),
              ],

              // Section 6: Summary
              if (_summary.isNotEmpty && _summary != _intro) ...[
                _sectionHeader('Ringkasan', Icons.summarize_rounded, kPrimary2),
                const SizedBox(height: 10),
                _textBlock(_summary),
                const SizedBox(height: 22),
              ],

              // Section 7: Check-in question preview
              if (_checkIn.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.quiz_rounded, color: kPrimary, size: 14),
                      SizedBox(width: 6),
                      Text('Cuba Fikir:', style: TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 8),
                    Text(_checkIn, style: const TextStyle(color: kText, fontSize: 13, height: 1.55)),
                    const SizedBox(height: 6),
                    const Text('Jawab bersama AI Tutor Nova selepas ini.', style: TextStyle(color: kMuted, fontSize: 11, fontStyle: FontStyle.italic)),
                  ]),
                ),
                const SizedBox(height: 22),
              ],
            ],

            const SizedBox(height: 32),
          ]),
        )),

        // Bottom CTA
        Container(
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
          decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: kBorder))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Dah baca? Nova siap ajar kamu secara interaktif!',
              textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: widget.onStartAiTutor,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Saya dah baca — Mula dengan AI Tutor ✦'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _stepChip(String num, String label, bool active) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: active ? kPrimary : kSurface2,
          shape: BoxShape.circle,
          border: Border.all(color: active ? kPrimary : kBorder),
        ),
        child: Center(child: Text(num, style: TextStyle(color: active ? Colors.white : kMuted, fontSize: 11, fontWeight: FontWeight.w800))),
      ),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: active ? kText : kMuted, fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
    ]);
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 17),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
    ]);
  }

  Widget _textBlock(String text) {
    final paras = text.split('\n\n').where((p) => p.trim().isNotEmpty).toList();
    if (paras.length <= 1) return Text(text.trim(), style: const TextStyle(color: kText, fontSize: 14, height: 1.75));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paras.map((p) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(p.trim(), style: const TextStyle(color: kText, fontSize: 14, height: 1.75)),
      )).toList(),
    );
  }
}
