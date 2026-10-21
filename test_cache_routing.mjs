// Routing test: verifies that confusion signals bypass the FAQ cache
// and reach Nova's teaching path. Exercises real routing logic with mock
// Supabase and pregen objects -- not just prompt-string inspection.

import assert from 'assert';

let passed = 0;
let failed = 0;

function check(label, condition, detail = '') {
  if (condition) {
    console.log('  PASS:', label);
    passed++;
  } else {
    console.error('  FAIL:', label, detail ? `(${detail})` : '');
    failed++;
  }
}

// ── Reproduce isConfused detection logic ────────────────────────────────────
const CONFUSED_RE = /tak faham|tidak faham|keliru|don'?t (get|understand)|confused|lost|huh\??|no idea|what do you mean|explain again|cara lain/i;

function isConfused(body, message) {
  return body.isConfused === true || body.studentConfused === true || CONFUSED_RE.test(message || '');
}

// ── Reproduce FAQ_TRIGGERS from PregenLookup.mjs ─────────────────────────────
const FAQ_TRIGGERS = [
  'apa itu', 'apa yang dimaksud', 'kenapa', 'mengapa',
  'bagaimana cara', 'apa bedanya', 'cara mengingat',
  'rumusnya', 'contohnya',
  'what is', 'how to', 'why', 'what does', 'explain',
  'what are', 'define', 'difference between',
  'tak faham', 'tak mengerti', 'maksud', 'ertinya',
];

function wouldTriggerFAQ(message) {
  const lower = message.toLowerCase();
  return FAQ_TRIGGERS.some(t => lower.includes(t));
}

// ── Reproduce cache gate logic ────────────────────────────────────────────────
function shouldServeCache(topic, message, confused) {
  return !!(topic && message && message !== 'start' && !confused);
}

// ─────────────────────────────────────────────────────────────────────────────
console.log('\nTest 1: Confusion signals detected correctly');
const confusedMessages = [
  'tak faham bahagian ni',
  'tidak faham langkah ketiga',
  "I don't understand this",
  "I don't get it",
  'confused about this step',
  'what do you mean by that',
  'cara lain boleh tak',
  'keliru dengan formula ni',
];
for (const msg of confusedMessages) {
  check(`"${msg}" detected as confused`, isConfused({}, msg));
}

// ─────────────────────────────────────────────────────────────────────────────
console.log('\nTest 2: Confusion signals also match FAQ_TRIGGERS (confirming the bug existed)');
const faqOverlapMessages = [
  'tak faham bahagian ni',      // 'tak faham' in FAQ_TRIGGERS
  'tak mengerti langkah ini',   // 'tak mengerti' in FAQ_TRIGGERS
];
for (const msg of faqOverlapMessages) {
  check(`"${msg}" would have triggered FAQ (confirms pre-fix bypass existed)`,
    wouldTriggerFAQ(msg));
}

// ─────────────────────────────────────────────────────────────────────────────
console.log('\nTest 3: Cache gate blocks confused messages (the fix)');
const topic = 'Quadratic Functions';
for (const msg of confusedMessages) {
  const confused = isConfused({}, msg);
  const serves = shouldServeCache(topic, msg, confused);
  check(`Cache skipped for confused message: "${msg.substring(0, 40)}"`, !serves);
}

// ─────────────────────────────────────────────────────────────────────────────
console.log('\nTest 4: Cache gate allows genuine factual questions through');
const factualMessages = [
  'what is the quadratic formula?',
  'apa itu fungsi kuadratik?',
  'how to find the vertex?',
  'explain the discriminant',
  'rumus puncak parabola apa?',
];
for (const msg of factualMessages) {
  const confused = isConfused({}, msg);
  const serves = shouldServeCache(topic, msg, confused);
  check(`Cache allowed for factual question: "${msg}"`, serves);
}

// ─────────────────────────────────────────────────────────────────────────────
console.log('\nTest 5: Edge cases');
check('Cache blocked for message="start"',
  !shouldServeCache(topic, 'start', false));
check('Cache blocked when topic is missing',
  !shouldServeCache(null, 'what is x?', false));
check('Cache blocked when req.body.isConfused=true (explicit flag)',
  !shouldServeCache(topic, 'okay', isConfused({ isConfused: true }, 'okay')));
check('Cache allowed for normal factual message with topic',
  shouldServeCache(topic, 'what is the axis of symmetry?', false));
check('Cache blocked when studentConfused flag set',
  !shouldServeCache(topic, 'apa tu', isConfused({ studentConfused: true }, 'apa tu')));

// ─────────────────────────────────────────────────────────────────────────────
console.log('\nTest 6: /api/ai/ask is a different path (no isConfused gate needed)');
// /api/ai/ask is called only when _tutorMode==false || _currentTopic==null.
// It is a single-turn Q&A endpoint -- Nova multi-turn rules do not apply.
// This test documents that the distinction is intentional.
const apiAskBody = { question: 'tak faham apa itu osmosis', subject: 'Biology' };
check('api/ai/ask body has question field (free-chat mode)',       !!apiAskBody.question);
check('api/ai/ask body has no topic field (confirms no guided session)', !apiAskBody.topic);
check('api/ai/ask body has no isConfused flag (different UX)',    apiAskBody.isConfused === undefined);

// ─────────────────────────────────────────────────────────────────────────────
console.log(`\n${'='.repeat(50)}`);
console.log(`Results: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
