import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../widgets/tts_player.dart';
import '../widgets/audio_player_widget.dart';

class LessonScreen extends StatefulWidget {
  final dynamic lesson;
  const LessonScreen({super.key, required this.lesson});
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  int _currentSection = 0;
  final List<Map<String, String>> _sections = [
    {'key': 'introduction',    'title': 'Introduction'},
    {'key': 'objectives',      'title': 'Learning Objectives'},
    {'key': 'content',         'title': 'Explanation'},
    {'key': 'worked_examples', 'title': 'Worked Examples'},
    {'key': 'common_mistakes', 'title': 'Common Mistakes'},
    {'key': 'summary',         'title': 'Summary'},
  ];

  dynamic get _lesson => widget.lesson;

  String get _currentText {
    final key = _sections[_currentSection]['key']!;
    return (_lesson[key] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text((_lesson['topic'] ?? 'Lesson').toString()),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${_currentSection + 1}/${_sections.length}', style: const TextStyle(color: kMuted, fontSize: 13)))),
        ],
      ),
      body: Column(children: [
        Container(
          color: kSurface, height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: _sections.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              final isSelected = _currentSection == i;
              return GestureDetector(
                onTap: () => setState(() => _currentSection = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? kPrimary : kSurface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? kPrimary : kBorder),
                  ),
                  child: Text(_sections[i]['title']!, style: TextStyle(color: isSelected ? Colors.white : kMuted, fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400)),
                ),
              );
            },
          ),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(0),
          child: Column(children: [
            LessonAudioPlayer(
                audioUrl: _lesson['audio_url']?.toString(),
                fallbackText: _currentText,
                title: _sections[_currentSection]['title']!,
              ),
            Padding(padding: const EdgeInsets.all(20), child: _buildCurrentSection()),
          ]),
        )),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: kBorder))),
          child: Row(children: [
            if (_currentSection > 0) Expanded(child: OutlinedButton(
              onPressed: () => setState(() => _currentSection--),
              style: OutlinedButton.styleFrom(foregroundColor: kText, side: const BorderSide(color: kBorder), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('← Previous'),
            )),
            if (_currentSection > 0) const SizedBox(width: 12),
            if (_currentSection < _sections.length - 1)
              Expanded(child: ElevatedButton(onPressed: () => setState(() => _currentSection++), child: const Text('Next →'))),
            if (_currentSection == _sections.length - 1)
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: kGreen),
                child: const Text('✓ Complete'),
              )),
          ]),
        ),
      ]),
    );
  }

  Widget _buildCurrentSection() {
    final key = _sections[_currentSection]['key']!;
    final title = _sections[_currentSection]['title']!;
    switch (key) {
      case 'introduction':
        return _buildTextSection(title, _lesson['introduction']?.toString() ?? '', kPrimary);
      case 'objectives':
        final objs = _lesson['learning_objectives'];
        if (objs == null) return _emptySection('No objectives available');
        final list = objs is List ? objs : [];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader(title), const SizedBox(height: 16),
          ...list.asMap().entries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kGreen.withOpacity(0.08), border: Border.all(color: kGreen.withOpacity(0.25)), borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 24, height: 24, decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(12)), child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)))),
              const SizedBox(width: 12),
              Expanded(child: Text(e.value.toString(), style: const TextStyle(color: kText, fontSize: 14, height: 1.5))),
            ]),
          )),
        ]);
      case 'content':
        return _buildTextSection(title, _lesson['content']?.toString() ?? '', kPrimary);
      case 'worked_examples':
        final examples = _lesson['worked_examples']?.toString() ?? '';
        if (examples.isEmpty) return _emptySection('Worked examples coming soon');
        return _buildExamplesSection(examples);
      case 'common_mistakes':
        final mistakes = _lesson['common_mistakes']?.toString() ?? '';
        if (mistakes.isEmpty) return _emptySection('Common mistakes coming soon');
        return _buildMistakesSection(mistakes);
      case 'summary':
        return _buildTextSection(title, _lesson['summary']?.toString() ?? '', kYellow);
      default:
        return _emptySection('Content coming soon');
    }
  }

  Widget _buildTextSection(String title, String content, Color color) {
    if (content.isEmpty) return _emptySection('Content coming soon');
    final paragraphs = content.split('\n\n').where((p) => p.trim().isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(title), const SizedBox(height: 16),
      ...paragraphs.map((para) {
        final trimmed = para.trim();
        final isHeader = (trimmed == trimmed.toUpperCase() && trimmed.length > 3 && trimmed.length < 60) || trimmed.startsWith('PART ') || trimmed.startsWith('Law ');
        if (isHeader) return Padding(padding: const EdgeInsets.only(top: 20, bottom: 8), child: Text(trimmed, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)));
        return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(trimmed, style: const TextStyle(color: kText, fontSize: 14, height: 1.75)));
      }),
    ]);
  }

  Widget _buildExamplesSection(String examples) {
    final parts = examples.split('\n\n').where((p) => p.trim().isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('Worked Examples'), const SizedBox(height: 16),
      ...parts.asMap().entries.map((e) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: kPrimary.withOpacity(0.15), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
            child: Row(children: [
              Container(width: 28, height: 28, decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(14)), child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)))),
              const SizedBox(width: 10),
              Text('Example ${e.key + 1}', style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(16), child: Text(e.value.trim(), style: const TextStyle(color: kText, fontSize: 13, height: 1.75))),
        ]),
      )),
    ]);
  }

  Widget _buildMistakesSection(String mistakes) {
    final lines = mistakes.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('Common Mistakes'), const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kRed.withOpacity(0.08), border: Border.all(color: kRed.withOpacity(0.3)), borderRadius: BorderRadius.circular(10)),
        child: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: kRed, size: 18), SizedBox(width: 8),
          Expanded(child: Text('Study these carefully — these exact mistakes cost marks in SPM!', style: TextStyle(color: kRed, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      ),
      const SizedBox(height: 16),
      ...lines.map((line) {
        final trimmed = line.trim();
        return Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(trimmed, style: const TextStyle(color: kText, fontSize: 13, height: 1.6)));
      }),
    ]);
  }

  Widget _sectionHeader(String title) => Text(title, style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w800));

  Widget _emptySection(String message) {
    return Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(children: [
      const Icon(Icons.hourglass_empty, color: kMuted, size: 48), const SizedBox(height: 12),
      Text(message, style: const TextStyle(color: kMuted, fontSize: 14)),
    ])));
  }
}


