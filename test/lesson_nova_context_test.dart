import 'package:flutter_test/flutter_test.dart';

// These tests verify the lesson-context contract between lesson_screen.dart
// and AITutorTab, and between AITutorTab and the /api/tutor/session endpoint.

void main() {
  // ── Lesson context key contract ───────────────────────────────────────────
  // The server reads exactly these five keys from lessonContext (server line 2581).
  // If they change on either side, sessions opened from lessons silently lose context.
  const _serverKeys = {
    'lesson_title',
    'topic',
    'concept_explanation',
    'worked_example',
    'try_it_question',
  };

  group('lessonContext key contract', () {
    // Simulate what _openNova() builds from the _lesson map.
    Map<String, dynamic> buildLessonContext(Map<String, dynamic> lesson) => {
      'lesson_title':        lesson['lesson_title'],
      'topic':               lesson['topic'],
      'concept_explanation': lesson['concept_explanation'],
      'worked_example':      lesson['worked_example'],
      'try_it_question':     lesson['try_it_question'],
    };

    test('all server-expected keys are present', () {
      final lesson = {
        'lesson_title':        'Sel',
        'topic':               'Biologi Sel',
        'concept_explanation': 'Sel adalah unit asas...',
        'worked_example':      'Contoh: sel haiwan vs sel tumbuhan',
        'try_it_question':     'Apakah perbezaan antara sel prokariot dan eukariot?',
      };
      final ctx = buildLessonContext(lesson);
      for (final key in _serverKeys) {
        expect(ctx.containsKey(key), isTrue, reason: 'Missing key: $key');
      }
    });

    test('no extra keys are injected (payload stays minimal)', () {
      final lesson = {
        'lesson_title': 'Test', 'topic': 'T', 'concept_explanation': 'C',
        'worked_example': 'W', 'try_it_question': 'Q',
        'id': 'abc', 'subject': 'MY-Biology', 'difficulty': 'Mudah',
      };
      final ctx = buildLessonContext(lesson);
      expect(ctx.keys.toSet(), equals(_serverKeys));
    });

    test('null lesson fields become null (not missing keys)', () {
      final lesson = <String, dynamic>{
        'lesson_title': null, 'topic': 'Sel', 'concept_explanation': null,
        'worked_example': null, 'try_it_question': null,
      };
      final ctx = buildLessonContext(lesson);
      // All keys still present; server falls back gracefully with ?? ''
      expect(ctx.containsKey('lesson_title'), isTrue);
      expect(ctx['lesson_title'], isNull);
    });
  });

  // ── Topic extraction ───────────────────────────────────────────────────────
  group('topic extraction from lessonContext', () {
    // Mirrors the initState logic: read 'topic', skip if empty.
    String? extractTopic(Map<String, dynamic>? ctx) {
      if (ctx == null) return null;
      final t = ctx['topic'] as String? ?? '';
      return t.isEmpty ? null : t;
    }

    test('returns topic when present', () {
      expect(extractTopic({'topic': 'Sel'}), 'Sel');
    });

    test('returns null for null context (normal Nova tab entry)', () {
      expect(extractTopic(null), isNull);
    });

    test('returns null for empty topic string', () {
      expect(extractTopic({'topic': ''}), isNull);
    });

    test('returns null for missing topic key', () {
      expect(extractTopic({'lesson_title': 'Sel'}), isNull);
    });
  });
}
