import 'package:flutter_test/flutter_test.dart';
import 'package:learnova_app/utils/form_level.dart';

void main() {
  // ── labelFromFormLevel ────────────────────────────────────────────────────
  group('labelFromFormLevel', () {
    group('integer inputs (API returns int)', () {
      test('4 → Form 4', () => expect(labelFromFormLevel(4), 'Form 4'));
      test('5 → Form 5', () => expect(labelFromFormLevel(5), 'Form 5'));
      test('6 → A-Level', () => expect(labelFromFormLevel(6), 'A-Level'));
    });

    group('integer-as-string inputs (auth.dart .toString() path)', () {
      test('"4" → Form 4', () => expect(labelFromFormLevel('4'), 'Form 4'));
      test('"5" → Form 5', () => expect(labelFromFormLevel('5'), 'Form 5'));
      test('"6" → A-Level', () => expect(labelFromFormLevel('6'), 'A-Level'));
    });

    group('already-labelled inputs (onboarding_screen stores text directly)', () {
      test('"Form 4" → Form 4', () => expect(labelFromFormLevel('Form 4'), 'Form 4'));
      test('"Form 5" → Form 5', () => expect(labelFromFormLevel('Form 5'), 'Form 5'));
      test('"A-Level" → A-Level', () => expect(labelFromFormLevel('A-Level'), 'A-Level'));
    });

    group('invalid / missing inputs', () {
      test('null → null', () => expect(labelFromFormLevel(null), isNull));
      test('empty string → null', () => expect(labelFromFormLevel(''), isNull));
      test('whitespace → null', () => expect(labelFromFormLevel('  '), isNull));
      test('unknown string → null', () => expect(labelFromFormLevel('Form 3'), isNull));
      test('7 → null', () => expect(labelFromFormLevel(7), isNull));
      test('"0" → null', () => expect(labelFromFormLevel('0'), isNull));
    });
  });

  // ── normalizeFormLabel ────────────────────────────────────────────────────
  group('normalizeFormLabel', () {
    group('returns usable DB filter labels', () {
      test('"Form 4" → Form 4', () => expect(normalizeFormLabel('Form 4'), 'Form 4'));
      test('"Form 5" → Form 5', () => expect(normalizeFormLabel('Form 5'), 'Form 5'));
      test('"4" (integer-string stored by old auth.dart) → Form 4',
          () => expect(normalizeFormLabel('4'), 'Form 4'));
      test('"5" → Form 5', () => expect(normalizeFormLabel('5'), 'Form 5'));
    });

    group('returns null — caller must handle, not silently default', () {
      test('null → null (missing prefs key)', () => expect(normalizeFormLabel(null), isNull));
      test('"" → null (empty prefs value)', () => expect(normalizeFormLabel(''), isNull));
      test('"A-Level" → null (no structured_lessons content yet)',
          () => expect(normalizeFormLabel('A-Level'), isNull));
      test('"6" → null (A-Level as integer-string)',
          () => expect(normalizeFormLabel('6'), isNull));
      test('"Form 3" → null', () => expect(normalizeFormLabel('Form 3'), isNull));
      test('"garbage" → null', () => expect(normalizeFormLabel('garbage'), isNull));
    });

    group('database filter format check', () {
      // The /api/lessons/path backend query does .eq('form', formParam).
      // structured_lessons.form stores exactly 'Form 4' or 'Form 5'.
      // Verify normalizeFormLabel only ever returns those two exact strings or null.
      final validDbLabels = {'Form 4', 'Form 5'};
      final inputs = ['4', '5', '6', 'Form 4', 'Form 5', 'A-Level', null, '', 'x'];
      for (final input in inputs) {
        test('output for "$input" is in $validDbLabels or null', () {
          final result = normalizeFormLabel(input);
          expect(
            result == null || validDbLabels.contains(result),
            isTrue,
            reason: 'Got "$result" for input "$input"',
          );
        });
      }
    });
  });
}
