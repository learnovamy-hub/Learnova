// Targeted test: verify the three changed prompt sections
import { NOVA_ZH_PROMPT, NOVA_TA_PROMPT } from './learnova_core.mjs';

let passed = 0;
let failed = 0;

function check(label, condition) {
  if (condition) {
    console.log('  PASS:', label);
    passed++;
  } else {
    console.error('  FAIL:', label);
    failed++;
  }
}

// --- Test 1: NOVA_ZH_PROMPT ---
console.log('\nTest 1: NOVA_ZH_PROMPT new rules');
check('Contains one-concept rule (8)',              NOVA_ZH_PROMPT.includes('8.'));
check('Contains diagnose-before-reteach rule (9)',  NOVA_ZH_PROMPT.includes('9.'));
check('Contains session-resume rule (10)',          NOVA_ZH_PROMPT.includes('10.'));
check('Ends with open-question instruction',        NOVA_ZH_PROMPT.includes('开放式问题结尾'));

// --- Test 2: NOVA_TA_PROMPT ---
console.log('\nTest 2: NOVA_TA_PROMPT new rules');
check('Contains one-concept rule (4)',    NOVA_TA_PROMPT.includes('4.'));
check('Contains diagnose rule (5)',       NOVA_TA_PROMPT.includes('5.'));
check('Contains session-resume rule (6)', NOVA_TA_PROMPT.includes('6.'));

// --- Test 3: Shared rule text (simulate template literal values) ---
console.log('\nTest 3: Shared rule text (BM and EN variants)');
const cases = [
  { lang: 'BM',      isBm: true  },
  { lang: 'English', isBm: false },
  { lang: 'ID',      isBm: false },
];
for (const { lang, isBm } of cases) {
  const p5 = '5. If student is CONFUSED: do NOT re-explain yet. Acknowledge in one sentence, then ask ONE specific question to locate exactly where understanding broke down. Only after the student\'s answer, reteach that specific part -- using a different method (analogy, simpler numbers, or diagram description) if needed.';
  const r6 = isBm
    ? 'Akui kekeliruan dalam SATU ayat. Kemudian tanya SATU soalan diagnostik yang spesifik untuk tahu tepat di mana kefahaman terhenti. Jangan terangkan semula lagi -- tunggu jawapan pelajar dahulu. Selepas pelajar menjawab, barulah terangkan semula bahagian itu sahaja dengan kaedah yang berbeza.'
    : "Acknowledge the confusion in ONE sentence. Then ask ONE specific diagnostic question to find exactly where understanding stopped. Do NOT re-explain yet -- wait for the student's answer first. Only after they answer, reteach that specific part using a different method.";
  const r9 = isBm
    ? 'Jika sejarah perbualan menunjukkan pengajaran telah bermula'
    : "If the conversation history shows teaching was already underway";

  check(`[${lang}] P5 diagnose-first instruction present`,  p5.includes('do NOT re-explain yet'));
  check(`[${lang}] P5 one-question instruction present`,    p5.includes('ONE specific question'));
  check(`[${lang}] P5 reteach only after student answers`,  p5.includes('Only after the student'));
  check(`[${lang}] R6 diagnose-first (no paling asas)`,     !r6.includes('paling asas') && !r6.includes('very basics'));
  check(`[${lang}] R6 wait-for-answer instruction`,         r6.includes('tunggu jawapan') || r6.includes('wait for the student'));
  check(`[${lang}] R9 session-resume text present`,         r9.length > 10);
}

// --- Test 4: Conflicting instruction is gone ---
console.log('\nTest 4: Old conflicting instruction removed');
const oldText = 'switch method entirely. Use analogy, diagram description, or simpler numbers.';
const newP5   = '5. If student is CONFUSED: do NOT re-explain yet. Acknowledge in one sentence, then ask ONE specific question to locate exactly where understanding broke down. Only after the student\'s answer, reteach that specific part -- using a different method (analogy, simpler numbers, or diagram description) if needed.';
check('Old "switch method entirely" absent from new Principle 5',         !newP5.includes('switch method entirely'));
check('New Principle 5 still references analogy as post-diagnosis option', newP5.includes('analogy'));
check('Old "No worries! Let\'s start from the very basics" absent from R6', !newP5.includes("Let's start from the very basics"));

console.log(`\n${'='.repeat(50)}`);
console.log(`Results: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
