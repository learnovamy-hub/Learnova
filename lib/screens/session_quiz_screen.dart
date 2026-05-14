import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';

class SessionQuizScreen extends StatefulWidget {
  final String studentId;
  final String subject;
  final String topic;
  final String? authToken;

  const SessionQuizScreen({
    super.key,
    required this.studentId,
    required this.subject,
    required this.topic,
    this.authToken,
  });

  @override
  State<SessionQuizScreen> createState() => _SessionQuizScreenState();
}

class _SessionQuizScreenState extends State<SessionQuizScreen>
    with SingleTickerProviderStateMixin {
  // ── State ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _questions = [];
  Map<String, String> _answers = {}; // question id → answer letter
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  int _currentIndex = 0;
  bool _submitted = false;

  // Results
  int _score = 0;
  int _total = 0;
  int _percentage = 0;
  List<Map<String, dynamic>> _gradedAnswers = [];

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _fetchQuestions();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── API calls ────────────────────────────────────────────────────────────
  Future<void> _fetchQuestions() async {
    setState(() { _loading = true; _error = null; });
    try {
      final url = '$kApiUrl/api/session-quiz'
          '/${Uri.encodeComponent(widget.studentId)}'
          '/${Uri.encodeComponent(widget.subject)}';
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final qs = (data['questions'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? [];
        if (qs.isEmpty) {
          setState(() { _error = 'no_questions'; _loading = false; });
          return;
        }
        setState(() { _questions = qs; _loading = false; });
      } else {
        setState(() { _error = 'fetch_failed'; _loading = false; });
      }
    } catch (_) {
      setState(() { _error = 'fetch_failed'; _loading = false; });
    }
  }

  Future<void> _submitQuiz() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/session-quiz/submit'),
        headers: {
          'Content-Type': 'application/json',
          if (widget.authToken != null) 'Authorization': 'Bearer ${widget.authToken}',
        },
        body: jsonEncode({
          'student_id': widget.studentId,
          'subject': widget.subject,
          'topic': widget.topic,
          'answers': _answers,
          'questions': _questions.map((q) => {
            'id': q['id'],
            'question': q['question'],
            'correct_answer': q['correct_answer'],
            'explanation': q['explanation'],
          }).toList(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final graded = (data['answers'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? [];
        setState(() {
          _submitted = true;
          _submitting = false;
          _score = data['score'] as int? ?? 0;
          _total = data['total'] as int? ?? _questions.length;
          _percentage = data['percentage'] as int? ?? 0;
          _gradedAnswers = graded;
        });
        _fadeCtrl.forward(from: 0);
      } else {
        _showError('Could not submit quiz. Please try again.');
        setState(() => _submitting = false);
      }
    } catch (_) {
      _showError('Connection error. Please check your internet.');
      setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: kRed),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  void _selectAnswer(String questionId, String letter) {
    if (_submitted) return;
    setState(() => _answers[questionId] = letter);
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      _fadeCtrl.forward(from: 0);
      setState(() => _currentIndex++);
    }
  }

  void _prevQuestion() {
    if (_currentIndex > 0) {
      _fadeCtrl.forward(from: 0);
      setState(() => _currentIndex--);
    }
  }

  bool get _allAnswered => _questions.every((q) => _answers.containsKey(q['id'].toString()));

  Color _scoreColor(int pct) {
    if (pct >= 80) return kGreen;
    if (pct >= 60) return kYellow;
    return kRed;
  }

  String _scoreLabel(int pct) {
    if (pct >= 80) return 'Excellent!';
    if (pct >= 60) return 'Good work!';
    if (pct >= 40) return 'Keep practising!';
    return 'Review this topic';
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Session Quiz',
                style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
            Text(widget.topic,
                style: const TextStyle(color: kMuted, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ],
        ),
        bottom: _questions.isNotEmpty && !_submitted
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: _buildProgressBar(),
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildProgressBar() {
    final answered = _answers.length;
    final total = _questions.length;
    return LinearProgressIndicator(
      value: total > 0 ? answered / total : 0,
      backgroundColor: kBorder,
      valueColor: const AlwaysStoppedAnimation<Color>(kPrimary),
      minHeight: 4,
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_error == 'no_questions') return _buildNoQuestions();
    if (_error == 'fetch_failed') return _buildFetchError();
    if (_submitted) return _buildResults();
    return _buildQuiz();
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: kPrimary, strokeWidth: 2),
          SizedBox(height: 16),
          Text('Loading your quiz...', style: TextStyle(color: kMuted, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildNoQuestions() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_empty_rounded, color: kMuted, size: 48),
            const SizedBox(height: 16),
            const Text('Quiz not ready yet',
                style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Questions are being prepared in the background.\nTry again in a moment.',
              style: TextStyle(color: kMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kMuted,
                    side: const BorderSide(color: kBorder),
                  ),
                  child: const Text('Go Back'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _fetchQuestions,
                  style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFetchError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: kRed, size: 48),
            const SizedBox(height: 16),
            const Text('Could not load quiz',
                style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Check your connection and try again.',
                style: TextStyle(color: kMuted, fontSize: 13)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kMuted,
                    side: const BorderSide(color: kBorder),
                  ),
                  child: const Text('Go Back'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _fetchQuestions,
                  style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Quiz question UI ─────────────────────────────────────────────────────
  Widget _buildQuiz() {
    final q = _questions[_currentIndex];
    final qId = q['id'].toString();
    final selected = _answers[qId];
    final options = Map<String, String>.from(q['options'] as Map);

    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        children: [
          // Question counter header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: kSurface,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kPrimary.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Q ${_currentIndex + 1} of ${_questions.length}',
                    style: const TextStyle(
                      color: kPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_answers.length} of ${_questions.length} answered',
                    style: const TextStyle(color: kMuted, fontSize: 12),
                  ),
                ),
                // Jump dots
                Row(
                  children: List.generate(_questions.length, (i) {
                    final qId2 = _questions[i]['id'].toString();
                    final done = _answers.containsKey(qId2);
                    return GestureDetector(
                      onTap: () { _fadeCtrl.forward(from: 0); setState(() => _currentIndex = i); },
                      child: Container(
                        width: 8, height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i == _currentIndex
                              ? kPrimary
                              : done
                                  ? kGreen
                                  : kBorder,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),

          // Question and options
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question text
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kBorder),
                    ),
                    child: Text(
                      q['question']?.toString() ?? '',
                      style: const TextStyle(
                        color: kText, fontSize: 16, fontWeight: FontWeight.w600,
                        height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Options
                  ...['A', 'B', 'C', 'D'].map((letter) {
                    final optionText = options[letter] ?? '';
                    if (optionText.isEmpty) return const SizedBox.shrink();
                    final isSelected = selected == letter;
                    return _buildOptionTile(
                      qId: qId,
                      letter: letter,
                      text: optionText,
                      isSelected: isSelected,
                    );
                  }),
                ],
              ),
            ),
          ),

          // Bottom navigation
          _buildNavBar(selected),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required String qId,
    required String letter,
    required String text,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => _selectAnswer(qId, letter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? kPrimary.withOpacity(0.12) : kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? kPrimary : kBorder,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            // Letter badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: isSelected ? kPrimary : kSurface2,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? kPrimary : kBorder,
                ),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    color: isSelected ? Colors.white : kMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: isSelected ? kText : const Color(0xFFCBD5E1),
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  height: 1.4,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: kPrimary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBar(String? selected) {
    final isLast = _currentIndex == _questions.length - 1;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          // Back
          if (_currentIndex > 0)
            OutlinedButton.icon(
              onPressed: _prevQuestion,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kMuted,
                side: const BorderSide(color: kBorder),
              ),
            )
          else
            const SizedBox(width: 80),

          const Spacer(),

          // Next or Submit
          if (!isLast)
            ElevatedButton.icon(
              onPressed: selected != null ? _nextQuestion : null,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Next'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: kBorder,
                disabledForegroundColor: kMuted,
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _allAnswered && !_submitting ? _submitQuiz : null,
              icon: _submitting
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 16),
              label: Text(_submitting ? 'Submitting...' : 'Submit Quiz'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _allAnswered ? kGreen : kBorder,
                foregroundColor: Colors.white,
                disabledBackgroundColor: kBorder,
                disabledForegroundColor: kMuted,
              ),
            ),
        ],
      ),
    );
  }

  // ── Results UI ───────────────────────────────────────────────────────────
  Widget _buildResults() {
    final color = _scoreColor(_percentage);
    final label = _scoreLabel(_percentage);

    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Score card
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  // Score circle
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.1),
                      border: Border.all(color: color, width: 3),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$_percentage%',
                          style: TextStyle(
                            color: color, fontSize: 28,
                            fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '$_score/$_total',
                          style: const TextStyle(color: kMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    style: TextStyle(
                      color: color, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.topic} · ${widget.subject}',
                    style: const TextStyle(color: kMuted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statChip(
                        Icons.check_circle_outline_rounded,
                        kGreen,
                        '$_score Correct',
                      ),
                      _statChip(
                        Icons.cancel_outlined,
                        kRed,
                        '${_total - _score} Wrong',
                      ),
                      _statChip(
                        Icons.quiz_outlined,
                        kPrimary,
                        '$_total Questions',
                      ),
                    ],
                  ),

                  if (_percentage < 80) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kYellow.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kYellow.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lightbulb_outline_rounded,
                              color: kYellow, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _percentage < 60
                                  ? 'Review this topic with your tutor before moving on.'
                                  : 'You\'re getting there! A little more practice will help.',
                              style: const TextStyle(
                                color: kYellow, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Answer review
            const Text(
              'Answer Review',
              style: TextStyle(
                  color: kText, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            ..._gradedAnswers.asMap().entries.map((entry) {
              final i = entry.key;
              final a = entry.value;
              final correct = a['correct'] as bool? ?? false;
              return _buildAnswerReviewCard(i + 1, a, correct);
            }),

            const SizedBox(height: 24),

            // Done button
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Done — Back to Tutor',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, Color color, String label) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildAnswerReviewCard(
      int num, Map<String, dynamic> a, bool correct) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: correct ? kGreen.withOpacity(0.4) : kRed.withOpacity(0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E3347),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Q$num',
                  style: const TextStyle(
                      color: kMuted, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                correct
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: correct ? kGreen : kRed,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                correct ? 'Correct' : 'Incorrect',
                style: TextStyle(
                  color: correct ? kGreen : kRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Question text
          Text(
            a['question']?.toString() ?? '',
            style: const TextStyle(
                color: kText, fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
          ),
          const SizedBox(height: 10),

          // Your answer / Correct answer
          if (!correct) ...[
            _answerRow(
              'Your answer',
              a['student_answer']?.toString() ?? '-',
              kRed,
            ),
            const SizedBox(height: 6),
          ],
          _answerRow(
            correct ? 'Your answer' : 'Correct answer',
            a['correct_answer']?.toString() ?? '-',
            kGreen,
          ),

          // Explanation
          if ((a['explanation'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kPrimary.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: kPrimary, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      a['explanation']!.toString(),
                      style: const TextStyle(
                          color: kMuted, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _answerRow(String label, String value, Color color) {
    return Row(
      children: [
        Text('$label: ',
            style: const TextStyle(color: kMuted, fontSize: 12)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            value,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
