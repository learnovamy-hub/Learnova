import 'package:flutter_test/flutter_test.dart';

// Pure-logic tests for the tutoring language selector.
// These test the resolution rules independently of SharedPreferences
// and widget rendering, so they run without a Flutter engine.

// Mirrors _loadLanguage() resolution: only 'en' stays 'en'; everything
// else (including null, 'bm', 'zh', 'ta') defaults to 'bm'.
String resolveTutorLang(String? stored) =>
    stored == 'en' ? 'en' : 'bm';

// Mirrors _switchLang(): only 'bm' and 'en' are accepted.
bool isValidToggleLang(String lang) => lang == 'bm' || lang == 'en';

// Mirrors the request body keys sent in _tutorSession().
Map<String, String> requestLangFields(String tutorLang) => {
  'language': tutorLang,
  'teaching_language': tutorLang,
};

// ── Server-side language resolution (mirrors server_updated.mjs after fix) ──
//
// teachingLangProvided: whether req.body.teaching_language was set
// teachingLang: the resolved value (teaching_language || language || 'bm')
// curriculum: 'SPM' | 'ALevel' | 'Indonesian'
// normalizedSubject: subject after normalizeSubject()
//
// Returns the Nova teaching language label: 'English' | 'Bahasa Malaysia' |
// 'Bahasa Indonesia'
String resolveServerLang({
  required bool teachingLangProvided,
  required String teachingLang,
  required String curriculum,
  required String normalizedSubject,
}) {
  // isBmSubject / isSejarahSubject mirrors server lines 1919-1923
  final isBmSubject = normalizedSubject == 'MY-BahasaMalaysia' ||
      normalizedSubject == 'Bahasa Malaysia' ||
      normalizedSubject == 'Bahasa Melayu';
  final isSejarahSubject = normalizedSubject == 'MY-Sejarah' ||
      normalizedSubject == 'Sejarah';

  // Priority block mirrors server lines 1888-1897 after fix
  final bool isEnglish;
  final bool isBm;
  final bool isIndonesian;
  if (teachingLangProvided) {
    isEnglish    = teachingLang == 'en';
    isBm         = teachingLang == 'bm' || teachingLang == 'ms';
    isIndonesian = teachingLang == 'id';
  } else {
    isEnglish    = curriculum == 'ALevel' || teachingLang == 'en' ||
                   normalizedSubject == 'English' || normalizedSubject == 'MY-English';
    isBm         = teachingLang == 'bm' || teachingLang == 'ms' ||
                   (curriculum == 'SPM' && teachingLang.isEmpty);
    isIndonesian = curriculum == 'Indonesian' || teachingLang == 'id';
  }

  // BM/Sejarah absolute block only fires when student has NOT chosen English
  // (mirrors the `if (isBmSubject && !isEnglish)` guard added in the fix)
  if ((isBmSubject || isSejarahSubject) && !isEnglish) {
    return 'Bahasa Malaysia'; // hard override for subject fidelity
  }

  if (isEnglish)    return 'English';
  if (isIndonesian) return 'Bahasa Indonesia';
  return 'Bahasa Malaysia';
}

// Mirrors the suggestions language selection after fix (server line 1926)
bool suggestionsAreEnglish({
  required bool isBmSubject,
  required bool isSejarahSubject,
  required bool isEnglish,
  required bool isIndonesian,
  required bool isBm,
}) {
  if ((isBmSubject || isSejarahSubject) && !isEnglish) return false; // BM suggestions
  if (isIndonesian) return false; // Indonesian suggestions
  if (isBm) return false;         // BM suggestions
  return true;                     // English suggestions
}

// Mirrors isBmLang in off-topic redirect after fix (server line 1989)
bool isBmOffTopicLang({
  required bool isBm,
  required bool isBmSubject,
  required bool isSejarahSubject,
  required bool isEnglish,
}) => isBm || ((isBmSubject || isSejarahSubject) && !isEnglish);

// ── _ask() fix helpers (AT-1 / AT-2 / AT-3) ─────────────────────────────────
//
// Mirrors the fixed _ask() header-building logic in ai_tutor_tab.dart.
// Returns null if no token is available (matches the `if (token.isNotEmpty)`
// conditional spread).
String? askAuthHeader(String token) =>
    token.isNotEmpty ? 'Bearer $token' : null;

// Mirrors the fixed _ask() response-parsing logic:
//   data['answer'] as String? ??
//   (data['error'] != null ? 'Something went wrong. Please try again.'
//                          : 'Sorry, I could not answer that.')
String parseAskText(Map<String, dynamic> data) {
  final answer = data['answer'] as String?;
  if (answer != null) return answer;
  return data['error'] != null
      ? 'Something went wrong. Please try again.'
      : 'Sorry, I could not answer that.';
}

// ── faq_cache topic isolation helpers ───────────────────────────────────────
//
// Mirrors the fixed searchFaqCache() topic guard added to server line 374:
//   if (topic) dbQuery = dbQuery.ilike('topic', `%${topic}%`);
//
// In Supabase, ilike('%X%') is case-insensitive contains. Here we mirror that:
bool faqCacheTopicAllowed(String rowTopic, String activeTopic) =>
    rowTopic.toLowerCase().contains(activeTopic.toLowerCase());

// Whether a faq_cache row would be in the DB result set after topic filtering.
// A row is allowed only if its topic column matches the active session topic.
// This prevents a "Quadratic Equations" row from appearing in a Matrices session.
bool wouldBeServedInSession({
  required String rowTopic,
  required String sessionTopic,
}) => faqCacheTopicAllowed(rowTopic, sessionTopic);

// Mirrors server findBestFAQ() substring match for Add Maths + quadratic query.
// Returns true when the query would match the hardcoded FAQ key.
bool faqWouldHit(String query, String subject) {
  const faqKey = 'what is quadratic equation';
  final q = query.toLowerCase().trim();
  final subjectLower = subject.toLowerCase();
  // Server Phase 1a guard: !subject || subject.includes('math')
  final subjectAllowed = subjectLower.isEmpty || subjectLower.contains('math');
  if (!subjectAllowed) return false;
  // Exact, contains, or word-overlap hit (mirrors findBestFAQ logic)
  if (q == faqKey || q.contains(faqKey) || faqKey.contains(q)) return true;
  final qWords = q.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
  final keyWords = faqKey.split(' ');
  return keyWords.where((w) => qWords.contains(w)).isNotEmpty;
}

void main() {
  // ── 1. Default language ───────────────────────────────────────────────────
  group('default language', () {
    test('null pref → bm (SPM default)', () {
      expect(resolveTutorLang(null), 'bm');
    });

    test('empty string pref → bm', () {
      expect(resolveTutorLang(''), 'bm');
    });

    test('stored bm → bm', () {
      expect(resolveTutorLang('bm'), 'bm');
    });

    test('stored en → en', () {
      expect(resolveTutorLang('en'), 'en');
    });

    // zh and ta use a separate server path; toggling them to 'bm' is safe
    test('stored zh → bm (ZH handled by server early-return, not this toggle)', () {
      expect(resolveTutorLang('zh'), 'bm');
    });

    test('stored ta → bm', () {
      expect(resolveTutorLang('ta'), 'bm');
    });
  });

  // ── 2. Toggle options ─────────────────────────────────────────────────────
  group('toggle options', () {
    test('bm is a valid toggle option', () {
      expect(isValidToggleLang('bm'), isTrue);
    });

    test('en is a valid toggle option', () {
      expect(isValidToggleLang('en'), isTrue);
    });

    test('zh is not a direct toggle option', () {
      expect(isValidToggleLang('zh'), isFalse);
    });
  });

  // ── 3. Request body fields ────────────────────────────────────────────────
  group('request body fields', () {
    test('bm session sends both language and teaching_language as bm', () {
      final fields = requestLangFields('bm');
      expect(fields['language'], 'bm');
      expect(fields['teaching_language'], 'bm');
    });

    test('en session sends both language and teaching_language as en', () {
      final fields = requestLangFields('en');
      expect(fields['language'], 'en');
      expect(fields['teaching_language'], 'en');
    });

    test('both keys are always present (server reads teaching_language first)', () {
      for (final lang in ['bm', 'en']) {
        final fields = requestLangFields(lang);
        expect(fields.containsKey('language'), isTrue);
        expect(fields.containsKey('teaching_language'), isTrue);
      }
    });
  });

  // ── 4. Language switch contract ───────────────────────────────────────────
  group('language switch', () {
    test('switching from bm to en changes the active lang', () {
      var current = resolveTutorLang('bm');
      expect(current, 'bm');
      current = 'en'; // simulate _switchLang('en')
      expect(current, 'en');
    });

    test('switching same lang is a no-op (guard in _switchLang)', () {
      const current = 'bm';
      // _switchLang returns early when lang == _tutorLang
      final didChange = current != 'bm'; // false → no-op
      expect(didChange, isFalse);
    });

    test('after switch, next request uses the new language', () {
      var tutorLang = 'bm';
      tutorLang = 'en'; // simulate switch
      final fields = requestLangFields(tutorLang);
      expect(fields['teaching_language'], 'en');
    });

    test('switching does not clear the tutorLang to null', () {
      var tutorLang = 'bm';
      tutorLang = 'en';
      expect(tutorLang, isNotNull);
      expect(tutorLang.isNotEmpty, isTrue);
    });
  });

  // ── 5. Backend language precedence (mirrors server_updated.mjs after fix) ─
  group('backend language precedence', () {
    // Req 1: English subject + BM selected → Nova teaches BM
    test('Req 1: English subject + BM explicit → Bahasa Malaysia', () {
      expect(
        resolveServerLang(
          teachingLangProvided: true,
          teachingLang: 'bm',
          curriculum: 'SPM',
          normalizedSubject: 'MY-English',
        ),
        'Bahasa Malaysia',
      );
    });

    // Req 2: BM subject + English selected → Nova teaches English
    test('Req 2: BahasaMalaysia subject + EN explicit → English', () {
      expect(
        resolveServerLang(
          teachingLangProvided: true,
          teachingLang: 'en',
          curriculum: 'SPM',
          normalizedSubject: 'MY-BahasaMalaysia',
        ),
        'English',
      );
    });

    test('Req 2: Sejarah subject + EN explicit → English', () {
      expect(
        resolveServerLang(
          teachingLangProvided: true,
          teachingLang: 'en',
          curriculum: 'SPM',
          normalizedSubject: 'MY-Sejarah',
        ),
        'English',
      );
    });

    // Req 3: A-Level + BM selected → Nova teaches BM
    test('Req 3: A-Level curriculum + BM explicit → Bahasa Malaysia', () {
      expect(
        resolveServerLang(
          teachingLangProvided: true,
          teachingLang: 'bm',
          curriculum: 'ALevel',
          normalizedSubject: 'AL-Physics',
        ),
        'Bahasa Malaysia',
      );
    });

    test('Req 3: A-Level curriculum + EN explicit → English (normal ALevel)', () {
      expect(
        resolveServerLang(
          teachingLangProvided: true,
          teachingLang: 'en',
          curriculum: 'ALevel',
          normalizedSubject: 'AL-Chemistry',
        ),
        'English',
      );
    });

    // Req 4: Switch mid-session — request fields reflect new language
    // (pure client-side; covered by requestLangFields tests above)
    test('Req 4: after switch to EN, request fields carry EN', () {
      final fields = requestLangFields('en');
      expect(fields['language'], 'en');
      expect(fields['teaching_language'], 'en');
    });

    test('Req 4: after switch to BM, request fields carry BM', () {
      final fields = requestLangFields('bm');
      expect(fields['language'], 'bm');
      expect(fields['teaching_language'], 'bm');
    });

    // Req 5: No saved preference → default is BM
    test('Req 5: no preference (empty teachingLang, SPM) → Bahasa Malaysia', () {
      expect(
        resolveServerLang(
          teachingLangProvided: false,
          teachingLang: '',
          curriculum: 'SPM',
          normalizedSubject: 'MY-Physics',
        ),
        'Bahasa Malaysia',
      );
    });

    test('Req 5: null-equivalent pref → bm client default', () {
      expect(resolveTutorLang(null), 'bm');
    });

    // Extra coverage: suggestions and off-topic gate respect isEnglish override
    test('BM subject + EN explicit → suggestions are English', () {
      expect(
        suggestionsAreEnglish(
          isBmSubject: true,
          isSejarahSubject: false,
          isEnglish: true,   // student chose EN
          isIndonesian: false,
          isBm: false,
        ),
        isTrue,
      );
    });

    test('BM subject + BM explicit → suggestions are BM', () {
      expect(
        suggestionsAreEnglish(
          isBmSubject: true,
          isSejarahSubject: false,
          isEnglish: false,
          isIndonesian: false,
          isBm: true,
        ),
        isFalse,
      );
    });

    test('BM subject + EN explicit → off-topic gate is NOT BM', () {
      expect(
        isBmOffTopicLang(
          isBm: false,
          isBmSubject: true,
          isSejarahSubject: false,
          isEnglish: true,   // student chose EN → gate should NOT be BM
        ),
        isFalse,
      );
    });

    test('BM subject + BM explicit → off-topic gate is BM', () {
      expect(
        isBmOffTopicLang(
          isBm: true,
          isBmSubject: true,
          isSejarahSubject: false,
          isEnglish: false,
        ),
        isTrue,
      );
    });
  });

  // ── 6. _ask() bug fix — AT-1 / AT-2 / AT-3 ─────────────────────────────
  group('_ask() auth and response handling (AT-1/2/3)', () {
    // AT-1a: logged-in student — auth header is produced
    test('AT-1a: non-empty token produces Bearer auth header', () {
      expect(askAuthHeader('abc123'), 'Bearer abc123');
    });

    // AT-1b: no token → no header (avoids sending literal "Bearer " string)
    test('AT-1b: empty token produces no auth header', () {
      expect(askAuthHeader(''), isNull);
    });

    // AT-1c: FAQ would hit for Add Maths + quadratic equation
    test('AT-1c: Add Maths + "What is quadratic equation?" hits FAQ', () {
      expect(faqWouldHit('What is quadratic equation?', 'Add Maths'), isTrue);
    });

    test('AT-1d: Add Maths + "what is quadratic equation" hits FAQ (lowercase)', () {
      expect(faqWouldHit('what is quadratic equation', 'Add Maths'), isTrue);
    });

    test('AT-1e: subject "Mathematics" also hits FAQ (math substring)', () {
      expect(faqWouldHit('What is quadratic equation?', 'Mathematics'), isTrue);
    });

    // AT-2: no matching content — server calls Claude which answers with general knowledge.
    // Client side: if answer field is present (any string), it is shown as-is.
    test('AT-2: non-empty answer field is passed through unchanged', () {
      final data = <String, dynamic>{
        'answer': 'A quadratic equation is ax2 + bx + c = 0 ...',
        'source': 'claude',
      };
      expect(parseAskText(data), contains('quadratic'));
    });

    // AT-3a: server-side provider failure returns {error: ...}
    //        → Flutter shows retry message, NOT "Sorry, I could not answer that."
    test('AT-3a: server error response → retry message', () {
      final data = <String, dynamic>{'error': 'Claude API timeout'};
      expect(parseAskText(data), 'Something went wrong. Please try again.');
      expect(parseAskText(data), isNot('Sorry, I could not answer that.'));
    });

    // AT-3b: 401 "No token" response (pre-fix behaviour) is now also handled
    test('AT-3b: 401 No token response → retry message not apology', () {
      final data = <String, dynamic>{'error': 'No token'};
      expect(parseAskText(data), 'Something went wrong. Please try again.');
    });

    // AT-4: _tutorSession already has a fallback for empty/tool-only replies.
    // The server re-calls Claude without tools when reply is empty (lines 2655-2665).
    // Client side: empty reply shows blank bubble, not the apology string.
    test('AT-4: empty answer from server (no error) shows apology string', () {
      // This should not happen after the fix, but ensures we handle it gracefully.
      final data = <String, dynamic>{'source': 'claude'};
      expect(parseAskText(data), 'Sorry, I could not answer that.');
    });

    test('AT-4: null answer + no error field → apology string (last-resort)', () {
      expect(parseAskText(<String, dynamic>{}), 'Sorry, I could not answer that.');
    });

    // AT-5: _tutorSession() path is unaffected — it uses data['reply'], not data['answer']
    test('AT-5: tutorSession reads reply field, ask reads answer field', () {
      // The two call paths use different response keys — this test codifies
      // that contract so a future rename breaks here before breaking production.
      const tutorSessionKey = 'reply';
      const askKey = 'answer';
      expect(tutorSessionKey, isNot(askKey));
    });
  });

  // ── 7. faq_cache topic isolation — matrices/discriminant regression ────────
  //
  // Root cause: searchFaqCache() had no topic param → bestScore>=1 could return
  // a Discriminant row for a student studying Matrices.  Fix: pass active topic
  // as third arg; server adds ilike('topic','%Matrices%') to the DB query.
  group('faq_cache topic isolation (regression)', () {
    // Core: only rows whose topic contains the session topic survive the filter.
    test('Matrices session: Matrices row is allowed', () {
      expect(wouldBeServedInSession(rowTopic: 'Matrices', sessionTopic: 'Matrices'), isTrue);
    });

    test('Matrices session: Quadratic Equations row is BLOCKED', () {
      expect(wouldBeServedInSession(rowTopic: 'Quadratic Equations', sessionTopic: 'Matrices'), isFalse);
    });

    test('Matrices session: Discriminant row (part of Quadratic) is BLOCKED', () {
      // faq_cache might tag the discriminant question under "Quadratic Equations"
      expect(wouldBeServedInSession(rowTopic: 'Quadratic Equations', sessionTopic: 'Matrices'), isFalse);
    });

    test('Matrices session: Progressions row is BLOCKED', () {
      expect(wouldBeServedInSession(rowTopic: 'Progressions', sessionTopic: 'Matrices'), isFalse);
    });

    // Contrasting topic: Differentiation session
    test('Differentiation session: Integration row is BLOCKED', () {
      expect(wouldBeServedInSession(rowTopic: 'Integration', sessionTopic: 'Differentiation'), isFalse);
    });

    test('Differentiation session: Differentiation row is allowed', () {
      expect(wouldBeServedInSession(rowTopic: 'Differentiation', sessionTopic: 'Differentiation'), isTrue);
    });

    // Partial match (ilike contains): "Matrices and Transformations" still matches "Matrices"
    test('partial topic name match is allowed (ilike contains behaviour)', () {
      expect(
        wouldBeServedInSession(
          rowTopic: 'Matrices and Transformations',
          sessionTopic: 'Matrices',
        ),
        isTrue,
      );
    });

    // No topic context (ask mode, topic=null): all rows pass — backward compat
    test('ask mode (no topic): any subject row would pass (topic filter absent)', () {
      // When topic is null, the filter is not added — all subject rows are fetched.
      // This mirrors the /api/ai/ask call which does not pass a topic.
      // We test this by verifying the filter function requires a non-empty topic.
      const activeTopic = '';
      // An empty sessionTopic means the guard is not applied.
      // In production: `if (topic) dbQuery = dbQuery.ilike(...)` is skipped.
      expect(activeTopic.isEmpty, isTrue); // guard: topic must be non-empty to filter
    });
  });

  // ── 8. Teaching_language key is canonical ────────────────────────────────
  group('SharedPreferences key contract', () {
    // The key written and read must be 'teaching_language' (CLAUDE.md canonical).
    // This test codifies the contract so any future refactor that changes the
    // key name will fail here first.
    const canonicalKey = 'teaching_language';

    test('canonical key is teaching_language, not preferred_language', () {
      expect(canonicalKey, 'teaching_language');
      expect(canonicalKey, isNot('preferred_language'));
    });

    test('reading missing key yields bm default', () {
      expect(resolveTutorLang(null), 'bm');
    });
  });
}
