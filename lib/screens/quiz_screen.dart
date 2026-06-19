import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../widgets/workspace_panel.dart';

class QuizScreen extends StatefulWidget {
  final String subject;
  final String topic;
  const QuizScreen({super.key, required this.subject, required this.topic});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  // Workspace ("Show your working") is hidden until /api/workspace/assess
  // is built (Part B). Flip to true to re-enable the UI entry points.
  static const bool _workspaceEnabled = false;
  List<dynamic> _questions = [];
  Map<String, String> _answers = {};
  bool _loading = true;
  bool _submitted = false;
  bool _submitting = false;
  bool _showWorkspace = false;
  bool _assessingWorkspace = false;
  Map<String, dynamic>? _results;
  Map<String, dynamic>? _workspaceResult;
  int _current = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final r = await http.get(
        Uri.parse('$kApiUrl/api/quizzes/questions/${Uri.encodeComponent(widget.subject)}/${Uri.encodeComponent(widget.topic)}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (r.statusCode == 200) {
        setState(() => _questions = List<dynamic>.from(jsonDecode(r.body)));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  List<Map<String, String>> _getOptions(dynamic q) {
    final raw = q['options'];
    if (raw is Map) {
      return raw.entries.map((e) => {'key': e.key.toString(), 'value': e.value.toString()}).toList();
    }
    final opts = <Map<String, String>>[];
    for (final k in ['A', 'B', 'C', 'D']) {
      final v = q['option_${k.toLowerCase()}'];
      if (v != null) opts.add({'key': k, 'value': v.toString()});
    }
    return opts;
  }

  Future<void> _submit() async {
    if (_answers.length < _questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer all questions'), backgroundColor: kSurface2));
      return;
    }
    setState(() => _submitting = true);
    int score = 0;
    final details = <Map<String, dynamic>>[];
    for (final q in _questions) {
      final qId = q['id']?.toString() ?? '';
      final correct = (_answers[qId] ?? '') == (q['correct_answer'] ?? '');
      if (correct) score++;
      details.add({'question': q['question_text'] ?? q['question'] ?? '', 'correct': correct});
    }
    setState(() {
      _results = {'score': score, 'total': _questions.length, 'details': details};
      _submitted = true;
      _submitting = false;
    });
    _recordAttempt(score, _questions.length);
  }

  void _recordAttempt(int score, int total) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      await http.post(
        Uri.parse('$kApiUrl/api/quizzes/attempt'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'subject': widget.subject, 'topic': widget.topic, 'score': score, 'total': total}),
      );
    } catch (_) {}
  }

  Future<void> _assessWorkspace(WorkspaceResult result) async {
    final q = _questions[_current];
    setState(() { _assessingWorkspace = true; _showWorkspace = false; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final studentId = prefs.getString('student_id') ?? '';
      final body = {
        'student_id': studentId,
        'subject': 'Mathematics',
        'topic': widget.topic,
        'question': q['question'] ?? q['question_text'] ?? '',
        'correct_answer': q['correct_answer'] ?? '',
        'input_mode': result.mode,
        if (result.typedAnswer != null) 'student_answer': result.typedAnswer,
        if (result.imageBase64 != null) 'image_base64': result.imageBase64,
      };
      final r = await http.post(
        Uri.parse('$kApiUrl/api/workspace/assess'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        setState(() { _workspaceResult = data; });
        // Auto-select correct answer if student got it right
        if (data['is_correct'] == true) {
          setState(() => _answers[q['id']] = q['correct_answer'] ?? 'A');
        }
      }
    } catch (_) {}
    setState(() => _assessingWorkspace = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: kBg, body: Center(child: CircularProgressIndicator(color: kPrimary)));
    if (_submitted && _results != null) return _buildResults();
    if (_questions.isEmpty) return Scaffold(appBar: AppBar(title: Text(widget.topic)), body: const Center(child: Text('No questions found', style: TextStyle(color: kMuted))));
    return _buildQuiz();
  }

  Widget _buildQuiz() {
    final q = _questions[_current];
    final options = _getOptions(q);
    final progress = (_current + 1) / _questions.length;
    final questionText = q['question'] ?? q['question_text'] ?? '';
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(widget.topic, style: const TextStyle(fontSize: 15)),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${_current + 1} / ${_questions.length}',
              style: const TextStyle(color: kMuted, fontSize: 13)))),
        ],
      ),
      body: Column(children: [
        // Progress bar
        LinearProgressIndicator(value: progress, backgroundColor: kSurface2, color: kPrimary, minHeight: 3),

        // Main content — responsive layout
        Expanded(child: isWide
          // DESKTOP: side by side
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Question + options (left)
              Expanded(flex: 3, child: _buildQuestionPanel(q, questionText, options)),
              // Workspace (right) — hidden until /api/workspace/assess is built (Part B)
              if (_workspaceEnabled)
                Expanded(flex: 2, child: _buildDesktopWorkspace(q, questionText)),
            ])
          // MOBILE: stacked
          : Stack(children: [
              _buildQuestionPanel(q, questionText, options),
              if (_workspaceEnabled && _showWorkspace)
                Positioned(bottom: 0, left: 0, right: 0,
                  child: WorkspacePanel(
                    subject: 'Mathematics',
                    question: questionText,
                    isSubmitting: _assessingWorkspace,
                    onSubmit: _assessWorkspace,
                    onClose: () => setState(() => _showWorkspace = false),
                  )),
            ]),
        ),

        // Workspace result banner
        if (_workspaceEnabled && _workspaceResult != null) _buildWorkspaceBanner(),

        // Bottom navigation
        _buildBottomNav(q),
      ]),
    );
  }

  Widget _buildQuestionPanel(dynamic q, String questionText, List<Map<String, String>> options) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Question number badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: kPrimary.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
          child: Text('Question ${_current + 1}', style: const TextStyle(color: kPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 14),
        // Question text
        Text(questionText, style: const TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w600, height: 1.5)),
        const SizedBox(height: 24),
        // MCQ options
        ...options.map((opt) {
          final selected = _answers[q['id']] == opt['key'];
          return GestureDetector(
            onTap: () => setState(() { _answers[q['id']] = opt['key']!; _workspaceResult = null; }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: selected ? kPrimary.withOpacity(0.15) : kSurface,
                border: Border.all(color: selected ? kPrimary : kBorder, width: selected ? 2 : 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: selected ? kPrimary : kSurface2,
                    border: Border.all(color: selected ? kPrimary : kBorder)),
                  child: Center(child: Text(opt['key']!,
                    style: TextStyle(color: selected ? Colors.white : kMuted, fontSize: 12, fontWeight: FontWeight.w700))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(opt['value']!,
                  style: TextStyle(color: kText, fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w400))),
              ]),
            ),
          );
        }),
        const SizedBox(height: 80), // space for bottom nav
      ]),
    );
  }

  Widget _buildDesktopWorkspace(dynamic q, String questionText) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            const Icon(Icons.edit_note_rounded, color: kPrimary, size: 18),
            const SizedBox(width: 8),
            const Text('Show your working', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
        Expanded(child: WorkspacePanel(
          subject: 'Mathematics',
          question: questionText,
          isSubmitting: _assessingWorkspace,
          onSubmit: _assessWorkspace,
        )),
      ]),
    );
  }

  Widget _buildWorkspaceBanner() {
    final result = _workspaceResult!;
    final isCorrect = result['is_correct'] == true;
    final score = result['score'] ?? 0;
    final max = result['max_marks'] ?? 4;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCorrect ? kGreen.withOpacity(0.1) : kRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isCorrect ? kGreen : kRed),
      ),
      child: Row(children: [
        Icon(isCorrect ? Icons.check_circle : Icons.info_outline, color: isCorrect ? kGreen : kRed, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(
          isCorrect ? 'Correct! $score/$max marks' : 'Score: $score/$max — ${result['encouragement'] ?? "Keep trying!"}',
          style: TextStyle(color: isCorrect ? kGreen : kRed, fontSize: 12, fontWeight: FontWeight.w600))),
        GestureDetector(onTap: () => setState(() => _workspaceResult = null), child: const Icon(Icons.close, size: 16, color: kMuted)),
      ]),
    );
  }

  Widget _buildBottomNav(dynamic q) {
    final isMobile = MediaQuery.of(context).size.width <= 700;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: kBorder))),
      child: Row(children: [
        // Workspace toggle (mobile only) — hidden until /api/workspace/assess is built (Part B)
        if (isMobile && _workspaceEnabled) ...[
          GestureDetector(
            onTap: () => setState(() => _showWorkspace = !_showWorkspace),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _showWorkspace ? kPrimary.withOpacity(0.15) : kSurface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _showWorkspace ? kPrimary : kBorder)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_note_rounded, size: 16, color: _showWorkspace ? kPrimary : kMuted),
                const SizedBox(width: 4),
                Text('Workings', style: TextStyle(fontSize: 12, color: _showWorkspace ? kPrimary : kMuted, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
        ],
        // Previous
        if (_current > 0) ...[
          OutlinedButton(
            onPressed: () => setState(() { _current--; _workspaceResult = null; _showWorkspace = false; }),
            style: OutlinedButton.styleFrom(foregroundColor: kText, side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Back'),
          ),
          const SizedBox(width: 8),
        ],
        const Spacer(),
        // Next or Submit
        if (_current < _questions.length - 1)
          ElevatedButton(
            onPressed: _answers[q['id']] == null ? null : () => setState(() { _current++; _workspaceResult = null; _showWorkspace = false; }),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Next'),
          )
        else
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: kGreen, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Submit Quiz'),
          ),
      ]),
    );
  }

  Widget _buildResults() {
    final score = _results?['score'] ?? 0;
    final total = _results?['total'] ?? _questions.length;
    final pct = total > 0 ? (score / total * 100).round() : 0;
    final color = pct >= 80 ? kGreen : pct >= 60 ? kYellow : kRed;
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: Text(widget.topic)),
      body: Center(child: Container(
        constraints: BoxConstraints(maxWidth: isWide ? 600 : double.infinity),
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.15), border: Border.all(color: color, width: 3)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$pct%', style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900)),
              Text('$score/$total', style: TextStyle(color: color.withOpacity(0.8), fontSize: 14)),
            ]),
          ),
          const SizedBox(height: 24),
          Text(pct >= 80 ? 'Excellent work!' : pct >= 60 ? 'Good effort!' : 'Keep practising!',
            style: const TextStyle(color: kText, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(pct >= 80 ? 'You have mastered this topic!' : 'Review the questions you got wrong and try again.',
            style: const TextStyle(color: kMuted, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 32),
          // Question review
          if (_results?['details'] != null) ...[
            const Align(alignment: Alignment.centerLeft, child: Text('Review', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700))),
            const SizedBox(height: 12),
            ...((_results!['details'] as List).asMap().entries.map((e) {
              final d = e.value;
              final correct = d['correct'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: correct ? kGreen.withOpacity(0.08) : kRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: correct ? kGreen.withOpacity(0.3) : kRed.withOpacity(0.3))),
                child: Row(children: [
                  Icon(correct ? Icons.check_circle_outline : Icons.cancel_outlined, color: correct ? kGreen : kRed, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Q${e.key + 1}: ${d['question'] ?? ''}', style: TextStyle(color: kText, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ]),
              );
            })),
          ],
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          )),
        ]),
      )),
    );
  }
}
