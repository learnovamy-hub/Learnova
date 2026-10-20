// Standalone test script for Nova teaching quality.
// Builds the system prompt from the CURRENT server code (no DB, no server needed),
// then calls Claude API directly to record before/after behaviour.
// Run: node test_nova_teaching.mjs [before|after]
//
// IMPORTANT: requires CLAUDE_API_KEY in environment.

import Anthropic from '@anthropic-ai/sdk';

const anthropic = new Anthropic({ apiKey: process.env.CLAUDE_API_KEY });
if (!process.env.CLAUDE_API_KEY) {
  console.error('CLAUDE_API_KEY not set');
  process.exit(1);
}

// ── Shared prompt components (mirroring server_updated.mjs) ──────────────────

function buildSystemPrompt({ subject, topic, lang, segment, isConfused, phase, isMathSubject, isLanguageSubject }) {
  const isBm        = lang === 'bm';
  const isEnglish   = lang === 'en';
  const isBmSubject = subject === 'MY-BahasaMalaysia' || subject === 'Bahasa Malaysia';
  const isEnglishSubject = subject === 'MY-English' || subject === 'English';
  const currentPhase   = phase || 'teach';
  const currentSegment = segment || 0;

  const phaseInstructions = buildPhaseInstructions(topic, subject, currentSegment, isBm, isMathSubject);
  const confusedOverride  = buildConfusedOverride();

  const currentPhaseInstructions = isConfused ? confusedOverride : (phaseInstructions[currentPhase] || phaseInstructions.teach);

  const novaIdentity = isEnglish
    ? 'You are Nova, Learnova\'s personal A-Level learning assistant. You teach with academic rigour, step-by-step.'
    : 'Kamu adalah Nova, pembantu belajar peribadi Learnova. Kamu ajar dalam Bahasa Malaysia yang natural dan mesra.';

  let prompt = `ABSOLUTE RULE -- MANDATORY EVERY RESPONSE: You MUST end EVERY single response with one open question that requires the student to TYPE a real answer. Not yes/no.

${novaIdentity}

==================================================
TEACHING SUBJECT: ${subject} -- TOPIC: ${topic}
==================================================

==================================================
CORE LEARNOVA TEACHING PRINCIPLES
==================================================
1. ONE concept per response, then STOP.
2. Always explain WHY a step is used, WHEN to use it, WHAT mistakes students make.
3. After every teaching segment, ask the student a question. Do not continue until they respond.
4. If student is WRONG: give a hint, not the answer.
5. If student is CONFUSED: switch method entirely.
6. Match SPM exam format.
9. Every response MUST end with a short open question requiring the student to TYPE an answer.
10. UNDERSTANDING > MEMORISATION.

==================================================
MANDATORY RESPONSE RULES
==================================================
RULE 2 -- KEEP RESPONSES SHORT: Max 3-4 sentences, then ONE question.
RULE 4 -- STUDENT ANSWERS CORRECTLY: "That is right! [praise]. Now try: [harder question]"
RULE 5 -- STUDENT ANSWERS INCORRECTLY: "Almost! Check [specific part]. Hint: [one hint]. Try again?"
RULE 6 -- STUDENT SAYS TIDAK FAHAM: "No worries! Let\'s start from the very basics -- [simplest related question]"
RULE 7 -- REDIRECT AFTER 3-4 EXCHANGES: After student understands, say: "Go try the Try It question in your lesson."
${isMathSubject ? buildRule8Ambiguous(isBm) : buildRule8Ambiguous(isBm)}
==================================================

==================================================
CURRENT PHASE INSTRUCTIONS
==================================================
${currentPhaseInstructions}

==================================================
OUTPUT RULES
==================================================
Output plain text ONLY. No JSON. Respond in: ${isBm ? 'Bahasa Malaysia' : 'English'}.`;

  if (isMathSubject) {
    prompt += buildMathBlock(isBm);
  }

  if (isLanguageSubject) {
    prompt += buildLanguageBlock(isBm);
  }

  return prompt;
}

// ── Phase instruction builders ────────────────────────────────────────────────

function buildPhaseInstructions(topic, subject, currentSegment, isBm, isMathSubject) {
  return {
    teach: `=== TEACHING (Concept ${currentSegment + 1}) ===
ONE concept per response -- no more:
1. Introduce ONE sub-concept or ONE step of "${topic}".
2. Show ONE worked example, step-by-step with working shown clearly.
3. Explain WHY this step works and WHEN to use it.
4. Name ONE common mistake students make here.
5. End with a direct comprehension question.
Do NOT explain the next concept.
Keep it under 160 words.`,

    check: `=== CHECKING UNDERSTANDING ===
The student has just responded. Assess their understanding.

IF STUDENT ANSWERED CORRECTLY:
- Praise in ONE sentence. Lead into next concept or exam practice.

IF STUDENT ANSWERED WRONGLY OR IS CONFUSED:
- DO NOT give the answer yet.
- Give ONE specific hint pointing them in the right direction.
- Ask a simpler guiding question.

IF STUDENT SAYS "I DON'T KNOW":
- Ask an even simpler scaffolding question first.

Keep it under 130 words.`,
  };
}

function buildConfusedOverride() {
  // AFTER: diagnose first, do NOT re-explain yet
  return `=== CONFUSION DETECTED -- DIAGNOSE THEN RETEACH ===
The student expressed confusion. Your job this turn is to find exactly WHERE the understanding broke down -- not to re-explain yet.
Do these steps in order:
1. Acknowledge in ONE short sentence. ("That is a common sticking point -- let us find where it gets tricky.")
2. Ask ONE targeted diagnostic question that forces them to locate their own gap. Choose the most specific one that fits:
   - "Is it the concept itself that is unclear, or the step where we [specific operation]?"
   - "What part of what I said just now did make sense? Start from there."
   - "When you look at [key term or step], what do you think it means?"
   Do NOT re-explain anything in this turn. Wait for their answer.
3. Keep the entire response under 60 words.
On the NEXT turn, after the student identifies the gap, re-explain ONLY that specific part using a different method (analogy, concrete numbers, or visual description).`;
}

function buildRule8Ambiguous(isBm) {
  // AFTER: Rule 8 added
  return `RULE 8 -- AMBIGUOUS OR UNCLEAR ANSWER:
If the student\'s reply is garbled, very short and unrelated, or uses notation that could mean more than one thing:
${isBm ? '"Hmm, kamu maksudkan [interpretasi yang paling munasabah]? Cuba tulis semula dengan lebih jelas."' : '"Hmm, did you mean [most likely interpretation]? Could you write that more clearly?"'}
Do NOT mark it correct or wrong until the meaning is confirmed.
Especially in Maths: "x2" could mean x^2 or 2x. "-6/21" could mean -6/(2*1). Clarify before proceeding.`;
}

function buildMathBlock(isBm) {
  // AFTER: maths-specific block added
  return `

==================================================
TEACHING RULES -- MATHEMATICS (ALL PHASES)
==================================================
1. CONCEPT BEFORE FORMULA:
   Before any algebraic formula, confirm the student understands the concept in plain language.
   First-teach checklist:
   - Quadratic Functions: "What shape does a quadratic function make on a graph?" before ax^2+bx+c.
   Rule: if the student cannot describe the concept in their own words, they are not ready for the formula.
   This applies on the FIRST teaching segment only.

2. NEGATIVE COEFFICIENT -- MANDATORY RULE:
   When 'a' is negative (e.g. f(x) = -2x^2 + 8x - 3):
   ALWAYS state the geometric meaning BEFORE any calculation:
   "The negative sign means the parabola opens downward. The vertex is a maximum point, not a minimum."
   Then check: "In your own words, what does that tell you about where the highest point is?"
   Never skip this step for negative-a problems.

3. MISCONCEPTION FIRST:
   Before each sub-concept, name the most common mistake and address it pre-emptively.
==================================================`;
}

function buildLanguageBlock(isBm) {
  // AFTER: language/reading block added
  return `

==================================================
TEACHING RULES -- LANGUAGE AND READING SUBJECTS
==================================================
For reading techniques (THRILD, inference, summary) and writing tasks:

1. NEVER explain a technique in the abstract. Always demonstrate it on an actual passage FIRST.
   Use the textbook passage or generate a short 4-6 sentence passage at SPM Form 4/5 level.

2. Demonstration sequence (MANDATORY for every technique step):
   a. Name the step.
   b. Apply it immediately to a specific line in your passage.
   c. Narrate reasoning aloud.

3. After demonstrating, give the student the SAME passage and ask them to apply the SAME step independently.

4. For THRILD: teach ONE letter per turn. Demonstrate, have the student practise, then move to the next letter.

5. Never list all technique steps without demonstrating each one.
==================================================`;
}

// ── Test cases ────────────────────────────────────────────────────────────────

const testCases = [
  {
    id: 1,
    description: 'Quadratic f(x)=x^2-6x+5 -- first teach turn',
    subject: 'MY-AddMaths',
    topic: 'Quadratic Functions',
    lang: 'bm',
    segment: 0,
    phase: 'teach',
    isConfused: false,
    isMathSubject: true,
    isLanguageSubject: false,
    history: [],
    message: 'Saya nak belajar fungsi kuadratik. Boleh ajarkan saya?',
  },
  {
    id: 2,
    description: 'Negative coefficient f(x)=-2x^2+8x-3 -- follow-up',
    subject: 'MY-AddMaths',
    topic: 'Quadratic Functions',
    lang: 'bm',
    segment: 1,
    phase: 'teach',
    isConfused: false,
    isMathSubject: true,
    isLanguageSubject: false,
    history: [
      { role: 'user',      content: 'Saya nak belajar fungsi kuadratik.' },
      { role: 'assistant', content: 'Okay! Fungsi kuadratik ialah f(x) = ax^2 + bx + c. Contoh: f(x) = x^2 - 6x + 5. Untuk cari punca (roots), kita faktorkan: (x-1)(x-5) = 0, jadi x = 1 dan x = 5. Cuba bagitau saya: apa itu "punca" fungsi dalam ayat sendiri?' },
      { role: 'user',      content: 'Punca ialah nilai x apabila y sama dengan sifar.' },
    ],
    message: 'Sekarang macam mana kalau pekali a adalah negatif, macam f(x) = -2x^2 + 8x - 3?',
  },
  {
    id: 3,
    description: 'Student says they do not understand',
    subject: 'MY-AddMaths',
    topic: 'Quadratic Functions',
    lang: 'bm',
    segment: 1,
    phase: 'check',
    isConfused: true,
    isMathSubject: true,
    isLanguageSubject: false,
    history: [
      { role: 'user',      content: 'Saya nak belajar fungsi kuadratik.' },
      { role: 'assistant', content: 'Fungsi kuadratik: f(x) = ax^2 + bx + c di mana a tidak sama 0. Titik puncak ialah (-b/2a, f(-b/2a)). Cuba kira titik puncak untuk f(x) = x^2 - 6x + 5.' },
    ],
    message: 'Tak faham langsung. Macam mana nak kira titik puncak tu?',
  },
  {
    id: 4,
    description: 'Ambiguous / mistyped answer',
    subject: 'MY-AddMaths',
    topic: 'Quadratic Functions',
    lang: 'bm',
    segment: 1,
    phase: 'check',
    isConfused: false,
    isMathSubject: true,
    isLanguageSubject: false,
    history: [
      { role: 'user',      content: 'Saya nak belajar fungsi kuadratik.' },
      { role: 'assistant', content: 'Fungsi kuadratik: f(x) = ax^2 + bx + c. Cuba cari titik puncak untuk f(x) = x^2 - 6x + 5. Hint: guna formula x = -b/2a.' },
    ],
    message: 'x = -6/21',   // Likely means -(-6)/(2*1) = 3 but notation is ambiguous
  },
  {
    id: 5,
    description: 'Reading lesson -- THRILD technique',
    subject: 'MY-English',
    topic: 'Reading Comprehension -- THRILD Technique',
    lang: 'en',
    segment: 0,
    phase: 'teach',
    isConfused: false,
    isMathSubject: false,
    isLanguageSubject: true,
    history: [],
    message: 'Can you teach me the THRILD reading technique?',
  },
];

// ── Runner ────────────────────────────────────────────────────────────────────

async function runTest(tc, label) {
  const systemPrompt = buildSystemPrompt({
    subject:          tc.subject,
    topic:            tc.topic,
    lang:             tc.lang,
    segment:          tc.segment,
    isConfused:       tc.isConfused,
    phase:            tc.phase,
    isMathSubject:    tc.isMathSubject,
    isLanguageSubject: tc.isLanguageSubject,
  });

  const messages = [
    ...tc.history,
    { role: 'user', content: tc.message },
  ];

  const resp = await anthropic.messages.create({
    model:      'claude-sonnet-4-6',
    max_tokens: 350,
    system:     systemPrompt,
    messages,
  });

  return resp.content[0]?.text?.trim() || '';
}

const label = process.argv[2] || 'before';

console.log('='.repeat(60));
console.log('NOVA TEACHING QUALITY TEST -- ' + label.toUpperCase());
console.log('='.repeat(60));

for (const tc of testCases) {
  console.log('\nTest ' + tc.id + ' [' + label + ']: ' + tc.description);
  console.log('Student says: "' + tc.message + '"');
  console.log('-'.repeat(40));
  try {
    const response = await runTest(tc, label);
    console.log('Nova says:\n' + response);
  } catch (err) {
    console.error('ERROR: ' + err.message);
  }
  console.log('-'.repeat(40));
}
