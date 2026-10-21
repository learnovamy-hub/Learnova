/**
 * Direct backend regression tests for the Nova pedagogy bypass fix.
 *
 * Tests A-E mirror the exact server logic — no Supabase connection or API key
 * required.  Where the test depends on the server's structure (not just logic),
 * it reads server_updated.mjs as text so the assertion fails immediately if
 * the code is reverted or refactored.
 *
 * Run:  node test_nova_pedagogy.mjs
 */

import { readFileSync } from 'fs';

// ── Test harness (same pattern as test_stem_unit.mjs) ─────────────────────────

let passed = 0, failed = 0;
const results = [];

function assert(label, condition, detail = '') {
  if (condition) {
    passed++;
    results.push(`  + [PASS] ${label}`);
  } else {
    failed++;
    results.push(`  X [FAIL] ${label}${detail ? '  ->  ' + detail : ''}`);
  }
}

// ── Read server source once for structural tests ───────────────────────────────

const SERVER_SRC = readFileSync('./server_updated.mjs', 'utf-8');

// Extract the tutor session handler body so structural checks are scoped correctly.
// Boundaries: the route declaration up to the next top-level app.post / app.get.
const TUTOR_HANDLER_START = SERVER_SRC.indexOf("app.post('/api/tutor/session'");
const TUTOR_HANDLER_END   = SERVER_SRC.indexOf('\napp.', TUTOR_HANDLER_START + 100);
const TUTOR_HANDLER = TUTOR_HANDLER_START >= 0
  ? SERVER_SRC.slice(TUTOR_HANDLER_START, TUTOR_HANDLER_END > 0 ? TUTOR_HANDLER_END : undefined)
  : '';

assert('server source loaded', SERVER_SRC.length > 10000,
  `file length ${SERVER_SRC.length}`);
assert('tutor session handler found', TUTOR_HANDLER.length > 1000,
  `handler length ${TUTOR_HANDLER.length}`);

// ── Inline: searchFaqCache filtering logic ────────────────────────────────────
//
// This is a pure, synchronous version of searchFaqCache() that accepts an
// in-memory rows array instead of Supabase.  The Supabase .ilike('%X%') filter
// is semantically equivalent to a case-insensitive string contains, so the
// behaviour is identical to the server query.

function mockSearchFaqCache(query, subject, topic, rows) {
  const q = query.toLowerCase().trim();

  // Mirror the Supabase ilike filters added in the fix.
  let filtered = rows.filter(r => r.answer);
  if (subject) {
    filtered = filtered.filter(r =>
      !r.subject || r.subject.toLowerCase().includes(subject.toLowerCase()));
  }
  // KEY FIX: topic filter added in this session's patch.
  if (topic) {
    filtered = filtered.filter(r =>
      r.topic && r.topic.toLowerCase().includes(topic.toLowerCase()));
  }

  if (!filtered.length) return null;

  const qWords = new Set(q.split(/\s+/).filter(w => w.length > 2));
  let bestMatch = null, bestScore = 0;

  for (const row of filtered) {
    const rowQ = (row.question || '').toLowerCase();
    if (rowQ === q)                                    return row;
    if (rowQ.includes(q) || q.includes(rowQ))         return row;
    const score = rowQ.split(/\s+/).filter(w => qWords.has(w)).length;
    if (score > bestScore && row.answer) { bestScore = score; bestMatch = row; }
  }

  return bestScore >= 1 ? bestMatch : null;
}

// ── Inline: detectExplanationType (mirrors PregenLookup.mjs) ─────────────────

const EXPLANATION_TRIGGERS = {
  fear_reduction: ['takut', 'susah', 'sulit', 'nervous', 'risau', 'scared', 'hard', 'difficult', 'give up', 'cannot'],
  beginner:       ['mula', 'start', 'awal', 'basic', 'first time', 'dont know', 'zero'],
  analogy:        ['analogi', 'contoh kehidupan', 'daily life', 'real life', 'macam apa', 'like what'],
  exam_focused:   ['exam', 'ujian', 'peperiksaan', 'tips', 'trick', 'ingat', 'remember', 'formula'],
};

function detectExplanationType(msg) {
  const lower = msg.toLowerCase();
  for (const [type, triggers] of Object.entries(EXPLANATION_TRIGGERS)) {
    if (triggers.some(t => lower.includes(t))) return type;
  }
  return null;
}

// ── Shared fixture: faq_cache rows ─────────────────────────────────────────────

const MOCK_ROWS = [
  {
    question: 'what is a matrix',
    answer:   'A matrix is a rectangular array of numbers arranged in rows and columns.',
    topic:    'Matrices',
    subject:  'MY-AddMaths',
  },
  {
    question: 'how to find determinant',
    answer:   'For 2x2: det = ad - bc.',
    topic:    'Matrices',
    subject:  'MY-AddMaths',
  },
  {
    question: 'what is discriminant',
    answer:   'The discriminant is b^2 - 4ac. It tells you the number of real roots.',
    topic:    'Quadratic Equations',
    subject:  'MY-AddMaths',
  },
  {
    question: 'how to solve quadratic equation',
    answer:   'Use the quadratic formula x = (-b +/- sqrt(b^2-4ac)) / 2a.',
    topic:    'Quadratic Equations',
    subject:  'MY-AddMaths',
  },
  {
    question: 'what is an arithmetic progression',
    answer:   'A sequence with constant common difference d.',
    topic:    'Progressions',
    subject:  'MY-AddMaths',
  },
];

// ── Test A: Topic isolation ────────────────────────────────────────────────────
//
// Matrices session — a cached Discriminant / Quadratic Equations answer must
// NOT be returned, even if there is some word overlap with the student message.

console.log('\n-- Test A: topic isolation (Matrices session, discriminant row) --');

{
  // "what" and "matrix" are in the student message.
  // Without topic filter: the Quadratic rows would compete for the top score.
  // With topic filter: only Matrices rows are candidates.

  const result = mockSearchFaqCache('what is a matrix', 'MY-AddMaths', 'Matrices', MOCK_ROWS);

  assert('A1: result is not null', result !== null, 'no Matrices row returned');
  assert('A1: returned row is from Matrices topic', result?.topic === 'Matrices',
    `got topic="${result?.topic}"`);
  assert('A1: Discriminant row NOT returned', result?.topic !== 'Quadratic Equations',
    'cross-topic contamination');
}

{
  // Student says "teach me from scratch" — "from", "scratch" have no FAQ-key match.
  // Without topic filter: "the" or other common words from any AddMaths row could score.
  // With topic filter: only Matrices rows are checked; no match → null (falls through to Claude).

  const result = mockSearchFaqCache('teach me from scratch', 'MY-AddMaths', 'Matrices', MOCK_ROWS);

  // Should return either a Matrices row (if words overlap) or null — never a Quadratic row.
  assert('A2: no Quadratic Equations row returned for generic message', result === null || result.topic === 'Matrices',
    `got topic="${result?.topic}"`);
}

{
  // Worst-case: student message contains "equation" — the word appears in the
  // Quadratic topic name.  Without topic filter this could return Discriminant.
  // With topic filter: the Quadratic rows are excluded; no Matrices row contains
  // "equation", so result is null and execution continues to Claude.

  const result = mockSearchFaqCache('teach me how to solve an equation using matrices', 'MY-AddMaths', 'Matrices', MOCK_ROWS);

  assert('A3: "equation" in message does NOT pull Quadratic row', result === null || result.topic === 'Matrices',
    `got topic="${result?.topic}"`);
}

// ── Test B: Valid same-topic cache ─────────────────────────────────────────────
//
// A question genuinely about Matrices may still be served from cache.

console.log('\n-- Test B: valid same-topic cache hit --');

{
  const result = mockSearchFaqCache('what is a matrix', 'MY-AddMaths', 'Matrices', MOCK_ROWS);
  assert('B1: Matrices question returns Matrices cached answer', result?.topic === 'Matrices');
  assert('B1: answer is non-empty', (result?.answer?.length ?? 0) > 0);
}

{
  // Exact match — "how to find determinant" is verbatim in the row.
  const result = mockSearchFaqCache('how to find determinant', 'MY-AddMaths', 'Matrices', MOCK_ROWS);
  assert('B2: exact-match question returns correct row', result?.topic === 'Matrices');
  assert('B2: answer contains det', result?.answer?.includes('det'));
}

// ── Test C: Beginner intent — getExplanation shortcut removed ─────────────────
//
// "I dont know anything about matrices. Teach me from zero." would previously
// trigger detectExplanationType('beginner') and serve a cached explanation that
// bypassed Claude's Socratic method.  The shortcut has been removed.

console.log('\n-- Test C: beginner intent (concept_explanations bypass removed) --');

{
  // Step 1: confirm the message WOULD have triggered the old shortcut.
  const beMsg = "I dont know anything about matrices. Teach me from zero.";
  const expType = detectExplanationType(beMsg);
  assert('C1: beginner message classifies as beginner type', expType === 'beginner',
    `got type="${expType}"`);

  const beMsg2 = "Saya tak tahu apa-apa. Mula dari zero.";
  const expType2 = detectExplanationType(beMsg2);
  assert('C1: BM beginner message also classifies (zero trigger)', expType2 === 'beginner',
    `got type="${expType2}"`);
}

{
  // Step 2: verify the server source no longer calls pregen.getExplanation() inside
  // the guided tutor path.  The explanatory comment mentions the name, so we must
  // skip comment lines and only fail if an actual (uncommented) call is present.
  const hasLiveCall = TUTOR_HANDLER.split('\n').some(line => {
    const trimmed = line.trimStart();
    return !trimmed.startsWith('//') && trimmed.includes('pregen.getExplanation(');
  });
  assert('C2: pregen.getExplanation() NOT called inside tutor session handler',
    !hasLiveCall,
    'getExplanation call found in tutor handler — bypass re-introduced');
}

{
  // Step 3: verify the comment that explains WHY it was removed is present.
  assert('C3: explanatory comment present at removal site',
    TUTOR_HANDLER.includes('concept_explanations') && TUTOR_HANDLER.includes('Socratic'),
    'expected removal comment not found');
}

// ── Test D: Missing topic — backward compatibility ─────────────────────────────
//
// /api/ai/ask and /api/qa call searchFaqCache(query, subject) without a topic.
// The default topic=null must leave those call sites unchanged.

console.log('\n-- Test D: topic=null (ask mode, no active session) --');

{
  // null topic → no ilike filter added → all subject rows are candidates.
  const result = mockSearchFaqCache('what is discriminant', 'MY-AddMaths', null, MOCK_ROWS);
  assert('D1: topic=null does not crash', result !== undefined);
  assert('D1: topic=null returns answer for matching question',
    result !== null && (result?.answer?.length ?? 0) > 0);
  // Any topic is allowed (no filter), so the Quadratic row is a valid result here.
  assert('D1: Quadratic Equations row CAN be returned without topic filter',
    result?.topic === 'Quadratic Equations' || result?.topic === 'Matrices');
}

{
  // No subject, no topic — should still work (used by /api/qa).
  const result = mockSearchFaqCache('what is an arithmetic progression', null, null, MOCK_ROWS);
  assert('D2: subject=null and topic=null returns best match', result !== null);
}

{
  // Empty string topic behaves like null (falsy guard).
  const result = mockSearchFaqCache('what is discriminant', 'MY-AddMaths', '', MOCK_ROWS);
  // '' is falsy, so the topic filter is not applied — Quadratic row is a valid return.
  assert('D3: empty-string topic is treated as null (no filter applied)',
    result !== null);
}

// ── Test D4: call sites in source unchanged ─────────────────────────────────

{
  // /api/ai/ask call site must still use 2-arg form (no topic).
  assert('D4: /api/ai/ask still calls searchFaqCache without topic arg',
    SERVER_SRC.includes("searchFaqCache(question, subject)")
    || SERVER_SRC.includes("await searchFaqCache(question, subject)"));
}

{
  // /api/tutor/session call site must now use 3-arg form with topic.
  assert('D5: /api/tutor/session now calls searchFaqCache with topic arg',
    TUTOR_HANDLER.includes('searchFaqCache(message, subject, topic)'));
}

// ── Test E: Pedagogy — constitution reaches Claude ─────────────────────────────
//
// Verify that the system prompt construction (present in the tutor handler after
// the cache-bypass block) contains the key Nova constitution rules, and that
// Claude is actually called — i.e., execution is NOT cut short before the prompt.

console.log('\n-- Test E: pedagogy — Nova constitution reaches Claude --');

{
  // Absolute topic-lock rule
  assert('E1: system prompt contains absolute topic rule',
    TUTOR_HANDLER.includes('ABSOLUTE RULE') && TUTOR_HANDLER.includes('YOU ARE TEACHING'));

  assert('E1: system prompt forbids introducing new topic',
    TUTOR_HANDLER.includes('NEVER introduce a new topic'));

  assert('E1: system prompt requires ONLY teaching the active topic',
    TUTOR_HANDLER.includes('ONLY teach content related to'));
}

{
  // Open-question rule — the Socratic method core constraint
  assert('E2: mandatory open-question rule present',
    TUTOR_HANDLER.includes('MANDATORY EVERY RESPONSE') ||
    TUTOR_HANDLER.includes('ABSOLUTE RULE #1'));

  assert('E2: rule forbids yes/no questions',
    TUTOR_HANDLER.includes('yes or no'));
}

{
  // RULE 1 / RULE 2 / RULE 3 mandatory response rules
  assert('E3: MANDATORY RESPONSE RULES block present',
    TUTOR_HANDLER.includes('MANDATORY RESPONSE RULES'));

  assert('E3: ASK FIRST rule present',
    TUTOR_HANDLER.includes('ASK FIRST'));

  assert('E3: KEEP RESPONSES SHORT rule present',
    TUTOR_HANDLER.includes('KEEP RESPONSES SHORT') ||
    TUTOR_HANDLER.includes('RULE 2'));
}

{
  // Claude API call is present in the handler (never short-circuited for all paths)
  assert('E4: Claude anthropic.messages.create is called in tutor handler',
    TUTOR_HANDLER.includes('anthropic.messages.create'));
}

{
  // Intro phase instructions (the first turn — curiosity hook)
  assert('E5: intro phase instruction present',
    TUTOR_HANDLER.includes('INTRODUCTION') && TUTOR_HANDLER.includes('curiosity hook'));
}

{
  // Teaching phase (one concept at a time)
  assert('E6: teaching phase — one concept at a time rule present',
    TUTOR_HANDLER.includes('ONE concept per response'));
}

{
  // Verify the beginner-intent message would reach Claude now (not exit early).
  // After the fix, the early-exit paths in order are:
  //   1. isOffTopicMessage() — only matches unrelated patterns (sports, hunger, etc.)
  //   2. pregen.detectAndServeFAQ() — queries faq_bank (topic-filtered, may or may not hit)
  //   3. searchFaqCache() — now topic-filtered (Matrices rows only)
  //   4. [getExplanation removed]
  //   5. claudeApiKey guard — passes if key is set
  //   6. Claude is called with full system prompt
  //
  // The isOffTopicMessage check would NOT match "I dont know about matrices"
  // because none of the patterns apply to it.
  const testMsg = "I dont know anything about matrices. Teach me from zero.";
  const offTopicPatterns = [
    /\b(lapar|hungry|tired|sleepy|bored|boring)\b/i,
    /\b(weather|cuaca)\b|what\s*time|whattime/i,
    /\b(toilet|bathroom|wc)\b/i,
    /2\s*\+\s*2|math\s+trick|\bjoke\b/i,
    /\b(sports|gaming|football|basketball)\b/i,
  ];
  const isOffTopic = offTopicPatterns.some(p => p.test(testMsg));
  assert('E7: beginner matrices message is NOT caught by off-topic filter', !isOffTopic,
    'message would be redirected instead of taught');
}

// ── Test F: Mandarin / Tamil path — library grounding ─────────────────────────
//
// Before the fix, the zh/ta early-return block at "if (isMandarin || isTamil)"
// called Claude without injecting textbookContext, without a topic lock, and
// without returning phase/segment.  These assertions verify the fix is in place.

console.log('\n-- Test F: Mandarin/Tamil library grounding --');

// Extract the zh/ta block boundaries so assertions are scoped to that code only.
const ZH_TA_START = TUTOR_HANDLER.indexOf('if (isMandarin || isTamil)');
const ZH_TA_END   = TUTOR_HANDLER.indexOf('\n    const novaIdentity', ZH_TA_START);
const ZH_TA_BLOCK = ZH_TA_START >= 0 && ZH_TA_END > ZH_TA_START
  ? TUTOR_HANDLER.slice(ZH_TA_START, ZH_TA_END)
  : '';

{
  assert('F1: zh/ta block found in handler', ZH_TA_BLOCK.length > 100,
    `block length ${ZH_TA_BLOCK.length}`);
}

{
  // Library grounding: textbookContext must be appended to langPrompt inside the zh/ta block.
  assert('F2: textbookContext injected into zh/ta prompt',
    ZH_TA_BLOCK.includes('textbookContext'),
    'textbookContext not referenced in zh/ta block — library grounding bypass');
}

{
  // Topic lock: an absolute topic rule must be inside the zh/ta block.
  const hasTopicLock = ZH_TA_BLOCK.includes('绝对规则') || ZH_TA_BLOCK.includes('விதி');
  assert('F3: topic lock rule injected into zh/ta prompt', hasTopicLock,
    'no topic-lock rule found in zh/ta block');
}

{
  // Phase contract: intro→teach on first response; subsequent turns stay in current phase.
  // This mirrors nextPhase('intro',...) = 'teach' in the BM/EN/ID path.
  assert('F4a: zh/ta advances intro to teach',
    ZH_TA_BLOCK.includes("currentPhase === 'intro' ? 'teach' : currentPhase"),
    'intro→teach transition absent from zh/ta block');

  // Segment contract: MUST NOT increment blindly. nextSegment() only increments on
  // check→teach, which requires a classify_turn signal this path cannot produce.
  // Unconditional +1 would burn through concept_chunks twice as fast as BM/EN/ID.
  assert('F4b: zh/ta does NOT blindly increment segment',
    !ZH_TA_BLOCK.includes('currentSegment + 1'),
    'segment: currentSegment + 1 found — segment burns through chunks on every turn');

  assert('F4c: zh/ta returns segment unchanged',
    ZH_TA_BLOCK.includes('segment: currentSegment,') || ZH_TA_BLOCK.includes('segment: currentSegment\n'),
    'segment not returned as currentSegment');
}

{
  // start sentinel translation: literal 'start' must NOT be passed to Claude.
  assert('F5: start sentinel translated before Claude call',
    ZH_TA_BLOCK.includes("message === 'start'"),
    'start sentinel not translated — model receives literal "start"');
}

// ── Summary ───────────────────────────────────────────────────────────────────

console.log('\n' + results.join('\n'));
console.log(`\n${passed + failed} tests: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
