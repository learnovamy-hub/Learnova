/**
 * Unit tests for Phase 1 STEM Problem State pure functions.
 * No server, no API key required.
 * Run: node test_stem_unit.mjs
 */

// ── Inline copies of the pure functions (identical to server_updated.mjs) ──

const UNIT_CONVERSIONS = {
  'deg:rad':       v => v * Math.PI / 180,
  'rad:deg':       v => v * 180 / Math.PI,
  'degree:radian': v => v * Math.PI / 180,
  'degrees:radians':v => v * Math.PI / 180,
  'radian:degree': v => v * 180 / Math.PI,
  'radians:degrees':v => v * 180 / Math.PI,
  'km:m':  v => v * 1000,
  'm:km':  v => v / 1000,
  'cm:m':  v => v / 100,
  'm:cm':  v => v * 100,
  'mm:m':  v => v / 1000,
  'm:mm':  v => v * 1000,
  'g:kg':  v => v / 1000,
  'kg:g':  v => v * 1000,
  'ms:s':  v => v / 1000,
  's:ms':  v => v * 1000,
};

function applyUnitConversion(value, fromUnit, toUnit) {
  const key = `${(fromUnit || '').toLowerCase().trim()}:${(toUnit || '').toLowerCase().trim()}`;
  const fn = UNIT_CONVERSIONS[key];
  return fn ? fn(value) : null;
}

function validateDeclarationGivens(questionText, givens) {
  for (const g of (givens || [])) {
    const n = Number(g.value);
    if (!isFinite(n)) continue;
    const candidates = [String(n), n.toFixed(0), n.toFixed(1), n.toFixed(2), n.toFixed(3)];
    if (!candidates.some(c => questionText.includes(c))) {
      return { valid: false, offending: { label: g.label, value: n } };
    }
  }
  return { valid: true };
}

function matchValue(extracted, declared, extractedUnit, declaredUnit, tolPct) {
  if (typeof tolPct !== 'number' || !isFinite(tolPct)) tolPct = 1.0;
  if (extracted === null || extracted === undefined || typeof extracted !== 'number' || !isFinite(extracted)) {
    return 'extraction_failed';
  }
  const eu = (extractedUnit || '').toLowerCase().trim();
  const du = (declaredUnit || '').toLowerCase().trim();
  if (!eu || !du || eu === du) {
    const pctErr = Math.abs(extracted - declared) / (Math.abs(declared) || 1) * 100;
    return pctErr <= tolPct ? 'correct' : 'wrong';
  }
  const converted = applyUnitConversion(extracted, eu, du);
  if (converted !== null) {
    const pctErr = Math.abs(converted - declared) / (Math.abs(declared) || 1) * 100;
    return pctErr <= tolPct ? 'correct' : 'wrong';
  }
  return 'needs_review';
}

// ── Test harness ──────────────────────────────────────────────────────────────

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

// ── validateDeclarationGivens ─────────────────────────────────────────────────
console.log('\n-- validateDeclarationGivens --');

assert('integer appears in text',
  validateDeclarationGivens('A car travels at 30 m/s for 5 seconds.', [
    { label: 'v', value: 30 }, { label: 't', value: 5 }
  ]).valid === true
);

assert('float appears in text',
  validateDeclarationGivens('Mass is 3.2 kg and acceleration is 9.81 m/s^2.', [
    { label: 'm', value: 3.2 }, { label: 'a', value: 9.81 }
  ]).valid === true
);

assert('gate blocks: value not in text',
  (() => {
    const r = validateDeclarationGivens('A car travels at some speed for 5 seconds.', [
      { label: 'v', value: 30 }, { label: 't', value: 5 }
    ]);
    return r.valid === false && r.offending.label === 'v';
  })()
);

assert('gate passes: value in text as decimal form',
  validateDeclarationGivens('Resistance R = 3.20 ohms.', [
    { label: 'R', value: 3.2 }
  ]).valid === true
);

assert('empty givens -> valid',
  validateDeclarationGivens('Any question text.', []).valid === true
);

assert('non-finite value skipped (no false block)',
  validateDeclarationGivens('Some text without numbers.', [
    { label: 'x', value: NaN }
  ]).valid === true
);

// ── matchValue: same units / no units ────────────────────────────────────────
console.log('\n-- matchValue: same/no units --');

// Test D: equivalent representation — "3.20" vs "3.2"
assert('D: 3.20 vs 3.2 (same unit) -> correct',
  matchValue(3.20, 3.2, 'ohm', 'ohm', 1.0) === 'correct'
);
assert('D: 3.200 vs 3.2 (no units stated) -> correct',
  matchValue(3.200, 3.2, '', '', 1.0) === 'correct'
);

assert('exact match integer -> correct',
  matchValue(30, 30, 'm/s', 'm/s', 1.0) === 'correct'
);

assert('slightly off within tolerance -> correct',
  matchValue(9.8, 9.81, '', '', 1.0) === 'correct'  // ~0.1% error
);

assert('clearly wrong same units -> wrong',
  matchValue(20, 30, 'm/s', 'm/s', 1.0) === 'wrong'
);

assert('null extracted -> extraction_failed',
  matchValue(null, 30, 'm/s', 'm/s', 1.0) === 'extraction_failed'
);

assert('NaN extracted -> extraction_failed',
  matchValue(NaN, 30, 'm/s', 'm/s', 1.0) === 'extraction_failed'
);

// ── matchValue: unit conversion ───────────────────────────────────────────────
console.log('\n-- matchValue: unit conversion --');

// Test E: degrees vs radians — student says "90 degrees", declared "1.5708 rad"
assert('E: 90 deg vs PI/2 rad -> correct (deg->rad conversion)',
  matchValue(90, Math.PI / 2, 'deg', 'rad', 1.0) === 'correct'
);

assert('E: PI/2 rad vs 90 deg -> correct (rad->deg conversion)',
  matchValue(Math.PI / 2, 90, 'rad', 'deg', 1.0) === 'correct'
);

assert('E: 1.57 rad vs 90 deg -> correct (approx pi/2)',
  matchValue(1.57, 90, 'rad', 'deg', 1.5) === 'correct'  // 1.5% tol for rounding
);

assert('km -> m conversion',
  matchValue(2, 2000, 'km', 'm', 1.0) === 'correct'
);

assert('g -> kg conversion',
  matchValue(500, 0.5, 'g', 'kg', 1.0) === 'correct'
);

// Test E variant: unknown unit pair -> needs_review (not auto-wrong)
assert('E: unknown unit pair -> needs_review',
  matchValue(42, 42, 'furlongs', 'parsecs', 1.0) === 'needs_review'
);

assert('different unknown units, value also wrong -> still needs_review (not wrong)',
  matchValue(10, 42, 'furlongs', 'parsecs', 1.0) === 'needs_review'
);

// ── applyUnitConversion ───────────────────────────────────────────────────────
console.log('\n-- applyUnitConversion --');

assert('90 deg -> rad ≈ PI/2',
  Math.abs(applyUnitConversion(90, 'deg', 'rad') - Math.PI / 2) < 1e-10
);

assert('1000 m -> km = 1',
  Math.abs(applyUnitConversion(1000, 'm', 'km') - 1) < 1e-10
);

assert('unknown pair -> null',
  applyUnitConversion(1, 'furlong', 'parsec') === null
);

assert('case-insensitive: DEG -> RAD',
  Math.abs(applyUnitConversion(180, 'DEG', 'RAD') - Math.PI) < 1e-10
);

// ── Print summary ─────────────────────────────────────────────────────────────
console.log();
for (const r of results) console.log(r);
console.log();
console.log(`  ${passed}/${passed + failed} passed  |  ${failed} failed`);
console.log('-'.repeat(60));

if (failed > 0) process.exit(1);
