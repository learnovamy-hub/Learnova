import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/constants.dart';
import 'lesson_list_screen.dart';

class TopicListScreen extends StatefulWidget {
  final String subjectKey;
  final String subjectName;
  final Color  subjectColor;
  const TopicListScreen({
    super.key,
    required this.subjectKey,
    required this.subjectName,
    required this.subjectColor,
  });
  @override
  State<TopicListScreen> createState() => _TopicListScreenState();
}

class _TopicListScreenState extends State<TopicListScreen> {
  Map<String, List<Map<String, dynamic>>> _topicLessons = {};
  Map<String, Map<String, dynamic>> _progress = {};
  bool _loading = true;
  String _studentId = '';
  String _token = '';
  String _form = 'Form 5';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _token     = prefs.getString('token') ?? '';
    _studentId = prefs.getString('student_id') ?? '';
    _form      = prefs.getString('student_form') ?? 'Form 5';

    await Future.wait([_fetchTopics(), _fetchProgress()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchTopics() async {
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/lessons/path?subject=${Uri.encodeComponent(widget.subjectKey)}&form=${Uri.encodeComponent(_form)}'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final path = (d['path'] as Map<String, dynamic>?) ?? {};
        final Map<String, List<Map<String, dynamic>>> topics = {};
        path.forEach((topic, lessons) {
          topics[topic] = (lessons as List).cast<Map<String, dynamic>>();
        });
        if (mounted) setState(() => _topicLessons = topics);
      }
    } catch (_) {}
  }

  Future<void> _fetchProgress() async {
    if (_studentId.isEmpty) return;
    try {
      final pr = await http.get(
        Uri.parse('$kApiUrl/api/lessons/progress?studentId=$_studentId&subject=${Uri.encodeComponent(widget.subjectKey)}'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (pr.statusCode == 200) {
        final pd = jsonDecode(pr.body) as Map<String, dynamic>;
        final list = (pd['progress'] as List?) ?? [];
        final Map<String, Map<String, dynamic>> prog = {};
        for (final p in list) {
          prog[p['lesson_id'] as String] = p as Map<String, dynamic>;
        }
        if (mounted) setState(() => _progress = prog);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        foregroundColor: kText,
        elevation: 0,
        title: Text(widget.subjectName,
          style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: kBorder, height: 1),
        ),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2))
        : _topicLessons.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: () async { await Future.wait([_fetchTopics(), _fetchProgress()]); },
              color: kPrimary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text('${_topicLessons.length} topik tersedia',
                    style: const TextStyle(color: kMuted, fontSize: 12)),
                  const SizedBox(height: 12),
                  ..._topicLessons.entries.map((e) => _buildTopicCard(e.key, e.value)),
                ],
              ),
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.auto_stories_outlined, color: kBorder, size: 48),
      const SizedBox(height: 12),
      const Text('Tiada pelajaran lagi', style: TextStyle(color: kMuted, fontSize: 14)),
      const SizedBox(height: 4),
      Text(widget.subjectName, style: const TextStyle(color: kBorder, fontSize: 12)),
    ]));
  }

  Widget _buildTopicCard(String topic, List<Map<String, dynamic>> lessons) {
    final completedCount = lessons.where((l) {
      final p = _progress[l['id'] as String?];
      return p?['status'] == 'completed';
    }).length;
    final total = lessons.length;
    final pct   = total > 0 ? completedCount / total : 0.0;
    final allDone   = completedCount == total && total > 0;
    final inProgress = completedCount > 0 && !allDone;

    Color dotColor;
    IconData dotIcon;
    if (allDone) {
      dotColor = kGreen;
      dotIcon  = Icons.check_circle_rounded;
    } else if (inProgress) {
      dotColor = kYellow;
      dotIcon  = Icons.radio_button_checked_rounded;
    } else {
      dotColor = kBorder;
      dotIcon  = Icons.radio_button_unchecked_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => LessonListScreen(
                topic: topic,
                lessons: lessons,
                subjectKey: widget.subjectKey,
                subjectName: widget.subjectName,
                subjectColor: widget.subjectColor,
                progress: _progress,
              ),
            ));
            // Refresh progress after returning
            await _fetchProgress();
            if (mounted) setState(() {});
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(dotIcon, color: dotColor, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(topic,
                    style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.subjectColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$total pelajaran',
                    style: TextStyle(color: widget.subjectColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: kSurface2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        allDone ? kGreen : widget.subjectColor),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$completedCount/$total',
                  style: TextStyle(
                    color: allDone ? kGreen : kMuted,
                    fontSize: 11, fontWeight: FontWeight.w500)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
