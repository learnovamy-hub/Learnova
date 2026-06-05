import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'main_shell.dart';
import '../widgets/tts_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AITutorTab extends StatefulWidget {
  final String selectedSubject;
  const AITutorTab({super.key, required this.selectedSubject});
  @override
  State<AITutorTab> createState() => _AITutorTabState();
}

class _AITutorTabState extends State<AITutorTab> {
  final _ctrl       = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _loading     = false;
  bool _sessionStarting = false;
  String _currentSubject = 'Mathematics';

  bool   _tutorMode  = false;
  String? _currentTopic;
  String  _phase     = 'intro';
  int     _segment   = 0;
  List<String> _suggestedResponses = [];
  List<Map<String, dynamic>> _topics = [];
  List<String> _suggestions = [];
  String? _pendingSwitchTopic;
  String? _currentStandardCode;
  String? _currentStandardDesc;
  String? _standardsProgress;
  String _language = 'en';

  @override
  void initState() {
    super.initState();
    _currentSubject = widget.selectedSubject;
    _loadTopics();
    _loadSuggestions();
    _loadLanguage();
  }

  @override
  void didUpdateWidget(AITutorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubject != widget.selectedSubject) {
      setState(() {
        _currentSubject = widget.selectedSubject;
        _tutorMode = false; _currentTopic = null;
        _messages.clear(); _suggestedResponses = [];
      });
      _loadTopics();
      _loadSuggestions();
    }
  }

  Future<void> _loadTopics() async {
    try {
      final r = await http.get(Uri.parse('$kApiUrl/api/tutor/topics?subject=${Uri.encodeComponent(_currentSubject)}'));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as List;
        if (mounted) setState(() => _topics = data.map((e) => Map<String, dynamic>.from(e)).toList());
      }
    } catch (_) {}
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _language = prefs.getString('preferred_language') ?? 'en');
  }

  Future<void> _loadSuggestions() async {
    try {
      final r = await http.get(Uri.parse('$kApiUrl/api/ai/faq?subject=${Uri.encodeComponent(_currentSubject)}'));
      if (r.statusCode == 200) {
        final topics = (jsonDecode(r.body)['topics'] as Map<String, dynamic>?) ?? {};
        final questions = <String>[];
        topics.forEach((topic, qList) {
          if (qList is List && questions.length < 6) {
            for (final q in qList.take(1)) {
              final question = q['question'] as String? ?? '';
              if (question.isNotEmpty) questions.add(question[0].toUpperCase() + question.substring(1) + '?');
            }
          }
        });
        if (mounted) setState(() => _suggestions = questions.take(6).toList());
      }
    } catch (_) {}
  }

  Future<void> _startTutorSession(String topic) async {
    if (_sessionStarting || topic.isEmpty) return;
    _sessionStarting = true;
    setState(() {
      _tutorMode = true; _currentTopic = topic;
      _phase = 'intro'; _segment = 0;
      _messages.clear(); _suggestedResponses = [];
      _loading = true;
    });
    // Pre-generate quiz silently in background ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â ready by end of session
    _preGenerateQuiz(topic);
    await _tutorSession('start');
    _sessionStarting = false;
  }

  void _preGenerateQuiz(String topic) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final studentId = prefs.getString('student_id') ?? '';
      if (studentId.isEmpty) return;
      await http.post(
        Uri.parse('$kApiUrl/api/session-quiz/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'student_id': studentId,
          'subject': _currentSubject,
          'topic': topic,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      // Non-fatal ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â quiz screen handles empty state gracefully
    }
  }

  Future<void> _tutorSession(String message) async {
    if (!_tutorMode || _currentTopic == null) return;
    setState(() => _loading = true);
    if (message != 'start') {
      setState(() => _messages.add({'role': 'user', 'text': message}));
      _scrollToBottom();
    }
    try {
      final history = _messages.take(10)
        .map((m) => {'role': m['role'] == 'user' ? 'user' : 'assistant', 'content': m['text'] ?? ''})
        .toList();
      final r = await http.post(
        Uri.parse('$kApiUrl/api/tutor/session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'subject': _currentSubject, 'topic': _currentTopic,
          'message': message, 'history': history,
          'phase': _phase, 'segment': _segment, 'language': _language,
        }),
      );
      final data = jsonDecode(r.body);
      setState(() {
        _phase    = data['phase']   ?? _phase;
        _segment  = data['segment'] ?? _segment;
        _currentStandardCode = data['standardCode']    as String?;
        _currentStandardDesc = data['standardDesc']    as String?;
        _standardsProgress   = data['standardsProgress'] as String?;
        if (data['topicSwitchSuggested'] == true) {
          _pendingSwitchTopic = data['suggestedTopic'] as String?;
        }
        _suggestedResponses = (data['suggestedResponses'] as List?)?.cast<String>() ?? [];
        _messages.add({
          'role': 'ai', 'text': data['reply'] ?? '',
          'source': data['source'], 'isCheckIn': data['isCheckIn'] ?? false,
        });
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _messages.add({'role': 'ai', 'text': 'Connection error. Please try again.'});
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  Future<void> _ask(String question) async {
    if (question.trim().isEmpty) return;
    // Handle pending topic switch
    if (_pendingSwitchTopic != null && question.toLowerCase().startsWith('yes')) {
      final t = _pendingSwitchTopic!;
      _pendingSwitchTopic = null;
      _ctrl.clear();
      await _startTutorSession(t);
      return;
    }
    if (_tutorMode && _currentTopic != null) {
      _ctrl.clear();
      await _tutorSession(question);
      return;
    }
    setState(() { _messages.add({'role': 'user', 'text': question}); _loading = true; });
    _ctrl.clear();
    _scrollToBottom();
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/ai/ask'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': question, 'subject': _currentSubject}),
      );
      final data = jsonDecode(r.body);
      final related = data['related_questions'];
      setState(() {
        _messages.add({
          'role': 'ai',
          'text': data['answer'] ?? 'Sorry, I could not answer that.',
          'example': data['example'], 'source': data['source'],
          'related_questions': (related is List) ? related.cast<String>() : <String>[],
          'wrong_subject_note': data['wrong_subject_note'],
        });
        _loading = false;
      });
    } catch (_) {
      setState(() { _messages.add({'role': 'ai', 'text': 'Connection error. Please try again.'}); _loading = false; });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Map<String, dynamic> get _subjectInfo =>
    kSubjects.firstWhere((s) => s['name'] == _currentSubject, orElse: () => kSubjects.first);

  @override
  Widget build(BuildContext context) {
    final subjectColor = Color(_subjectInfo['color'] as int);
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(_tutorMode && _currentTopic != null ? 'Lesson: $_currentTopic' : 'AI Tutor - $_currentSubject',
          style: const TextStyle(fontSize: 15)),
        actions: [
          if (_tutorMode)
            TextButton(
              onPressed: () => setState(() {
                _tutorMode = false; _currentTopic = null;
                _messages.clear(); _suggestedResponses = [];
              }),
              child: const Text('Exit', style: TextStyle(color: kMuted)),
            ),
          if (!_tutorMode && _messages.isNotEmpty)
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => setState(() => _messages.clear())),
        ],
      ),
      body: isWide
        ? Row(children: [
            // Desktop: topic sidebar
            if (!_tutorMode) SizedBox(
              width: 280,
              child: Container(
                decoration: const BoxDecoration(color: kSurface, border: Border(right: BorderSide(color: kBorder))),
                child: _buildTopicSidebar(),
              ),
            ),
            // Main chat
            Expanded(child: Column(children: [
              _buildSubjectBar(),
              if (_messages.isEmpty && !_tutorMode) _buildWelcome(subjectColor),
              Expanded(child: _buildMessageList()),
              if (_tutorMode && _suggestedResponses.isNotEmpty) _buildSuggestedResponses(),
              if (!_tutorMode && _messages.isEmpty) _buildSuggestions(),
              _buildInput(),
            ])),
          ])
        : Column(children: [
            _buildSubjectBar(),
            Expanded(child: _messages.isEmpty && !_tutorMode ? _buildTopicSelector() : _buildMessageList()),
            if (_tutorMode && _suggestedResponses.isNotEmpty) _buildSuggestedResponses(),
            _buildInput(),
          ]),
    );
  }

  Widget _buildSubjectBar() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SubjectSelector(
        selected: _currentSubject,
        onChanged: (s) {
          setState(() => _currentSubject = s);
          _loadTopics(); _loadSuggestions();
          context.findAncestorStateOfType<MainShellState>()?.setSubject(s);
        },
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _messages.length) return _typingIndicator();
        return _buildMessage(_messages[i]);
      },
    );
  }

  Widget _buildWelcome(Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(children: [
        Container(width: 64, height: 64,
          decoration: BoxDecoration(color: color.withOpacity(0.15),
            border: Border.all(color: color.withOpacity(0.4)), borderRadius: BorderRadius.circular(16)),
          child: const Center(child: Icon(Icons.auto_awesome_rounded, size: 30, color: Colors.white))),
        const SizedBox(height: 12),
        Text('$_currentSubject AI Tutor', style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Choose a topic for a guided lesson, or ask any question below',
          style: TextStyle(color: kMuted, fontSize: 13), textAlign: TextAlign.center),
      ]),
    );
  }

  // Desktop sidebar
  Widget _buildTopicSidebar() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Topics', style: TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w700))),
      Expanded(child: ListView(children: _topics.map((t) {
        final topic = t['topic'] as String? ?? t['title'] as String? ?? '';
        return ListTile(
          leading: const Icon(Icons.play_circle_outline, color: kPrimary, size: 20),
          title: Text(topic, style: const TextStyle(color: kText, fontSize: 13)),
          subtitle: const Text('Guided lesson', style: TextStyle(color: kMuted, fontSize: 11)),
          onTap: () => _startTutorSession(topic),
          dense: true,
        );
      }).toList())),
    ]);
  }

  // Mobile topic list
  Widget _buildTopicSelector() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Welcome header
        const SizedBox(height: 8),
        Row(children: const [
          Icon(Icons.auto_awesome_rounded, color: kPrimary, size: 20),
          SizedBox(width: 8),
          Text('Choose a topic to start learning', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        const Text('Tap any topic for a guided lesson, or ask a question below', style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 16),
        if (_topics.isNotEmpty) ...[
          const Text('Guided Lessons', style: TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._topics.map((t) {
            final topic = t['topic'] as String? ?? t['title'] as String? ?? '';
            return GestureDetector(
              onTap: () => _startTutorSession(topic),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Center(child: Icon(Icons.play_circle_rounded, color: kPrimary, size: 20))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t['title'] as String? ?? topic, style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
                    const Text('Guided tuition lesson', style: TextStyle(color: kMuted, fontSize: 11)),
                  ])),
                  const Icon(Icons.arrow_forward_ios_rounded, color: kMuted, size: 12),
                ]),
              ),
            );
          }),
          const SizedBox(height: 16),
          const Divider(color: kBorder),
          const SizedBox(height: 8),
        ],
        const Text('Or ask me anything', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._suggestions.map((q) => GestureDetector(
          onTap: () => _ask(q),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              const Icon(Icons.arrow_forward_ios_rounded, color: kPrimary, size: 10),
              const SizedBox(width: 8),
              Expanded(child: Text(q, style: const TextStyle(color: kText, fontSize: 13))),
            ]),
          ),
        )),
      ]),
    );
  }

  Widget _buildSuggestedResponses() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Quick replies:', style: TextStyle(color: kMuted, fontSize: 11)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: _suggestedResponses.map((s) => GestureDetector(
          onTap: () { _tutorSession(s); setState(() => _suggestedResponses = []); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: kPrimary.withOpacity(0.1),
              border: Border.all(color: kPrimary.withOpacity(0.4)), borderRadius: BorderRadius.circular(20)),
            child: Text(s, style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
        )).toList()),
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _buildSuggestions() {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => GestureDetector(
          onTap: () => _ask(_suggestions[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: kSurface2, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(20)),
            child: Text(_suggestions[i], style: const TextStyle(color: kText, fontSize: 12))),
        ),
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    final text   = msg['text'] as String? ?? '';
    final source = msg['source'] as String?;
    String sourceLabel = '';
    if (source == 'lesson_db')   sourceLabel = 'From textbook';
    else if (source == 'faq_cache')  sourceLabel = 'Instant answer';
    else if (source == 'quiz_bank')  sourceLabel = 'SPM question bank';
    else if (source == 'claude')     sourceLabel = 'AI generated';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(width: 32, height: 32,
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16)),
            const SizedBox(width: 10),
          ],
          Flexible(child: Column(crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            // TTS player for AI messages
            if (!isUser && text.length > 50) TtsPlayer(text: text, title: 'Tutor'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser ? kPrimary : kSurface,
                border: Border.all(color: isUser ? kPrimary : kBorder),
                borderRadius: BorderRadius.circular(14)),
              child: MarkdownBody(data: text, styleSheet: MarkdownStyleSheet(
                p:      const TextStyle(color: kText, fontSize: 14, height: 1.6),
                h2:     const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700),
                h3:     const TextStyle(color: kPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                strong: const TextStyle(color: kText, fontWeight: FontWeight.w700),
                code:   const TextStyle(color: kGreen, fontSize: 13, fontFamily: 'monospace'),
              )),
            ),
            if (!isUser && msg['example'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kGreen.withOpacity(0.1),
                  border: Border.all(color: kGreen.withOpacity(0.3)), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Example:', style: TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(msg['example'].toString(), style: const TextStyle(color: kText, fontSize: 13)),
                ])),
            ],
            if (!isUser && msg['wrong_subject_note'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: kYellow.withOpacity(0.1),
                  border: Border.all(color: kYellow.withOpacity(0.4)), borderRadius: BorderRadius.circular(10)),
                child: Text(msg['wrong_subject_note'].toString(), style: const TextStyle(color: kYellow, fontSize: 12, fontWeight: FontWeight.w600))),
            ],
            if (!isUser && sourceLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(sourceLabel, style: const TextStyle(color: kMuted, fontSize: 11)),
            ],
            if (!isUser && (msg['related_questions'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kPrimary.withOpacity(0.06),
                  border: Border.all(color: kPrimary.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [Icon(Icons.explore_rounded, color: kPrimary, size: 14), SizedBox(width: 6),
                    Text('Explore more:', style: TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w700))]),
                  const SizedBox(height: 8),
                  ...(msg['related_questions'] as List).map((q) => GestureDetector(
                    onTap: () => _ask(q.toString()),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: kSurface2,
                        border: Border.all(color: kPrimary.withOpacity(0.3)), borderRadius: BorderRadius.circular(20)),
                      child: Row(children: [
                        const Icon(Icons.arrow_forward_ios_rounded, color: kPrimary, size: 10),
                        const SizedBox(width: 6),
                        Expanded(child: Text(
                          q.toString()[0].toUpperCase() + q.toString().substring(1) + '?',
                          style: const TextStyle(color: kText, fontSize: 12))),
                      ])),
                  )),
                ])),
            ],
          ])),
          if (isUser) const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _typingIndicator() {
    return Row(children: [
      Container(width: 32, height: 32,
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16)),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
        child: const Row(children: [
          SizedBox(width: 6, height: 6, child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
          SizedBox(width: 8),
          Text('Thinking...', style: TextStyle(color: kMuted, fontSize: 13)),
        ])),
    ]);
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: kBorder))),
      child: Row(children: [
        Expanded(child: TextField(
          controller: _ctrl,
          style: const TextStyle(color: kText, fontSize: 14),
          decoration: InputDecoration(
            hintText: _tutorMode ? 'Ask your tutor...' : 'Ask about $_currentSubject...',
            hintStyle: const TextStyle(color: kMuted),
            filled: true, fillColor: kSurface2,
            border:        OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: kBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: kPrimary)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          onSubmitted: _ask,
          textInputAction: TextInputAction.send,
        )),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => _ask(_ctrl.text),
          child: Container(width: 44, height: 44,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(22)),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}
