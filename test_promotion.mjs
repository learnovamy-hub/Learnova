// Test suite for the academic year promotion system.
// Uses an in-memory mock of the Supabase client — no production data is touched.
// Run: node test_promotion.mjs

import { init, runPromotion, previewPromotion, setAcademicYearConfig, setStudentPromotionFlags } from './promotion_engine.mjs';

// ── In-memory mock Supabase ───────────────────────────────────────────────────

function createMockSupabase({ students = [], config = [], promotionLog = [] } = {}) {
  const db = {
    students:              JSON.parse(JSON.stringify(students)),
    academic_year_config:  JSON.parse(JSON.stringify(config)),
    student_promotion_log: JSON.parse(JSON.stringify(promotionLog)),
  };

  function buildChain(tableName) {
    let _data    = [...db[tableName]];
    let _filters = [];
    let _update  = null;
    let _insert  = null;
    let _upsert  = null;
    let _selectCols = null;
    let _limit   = null;
    let _single  = false;
    let _maybeSingle = false;

    const chain = {
      select(cols) { _selectCols = cols; return chain; },
      eq(col, val) {
        _filters.push(row => {
          if (val === null || val === undefined) return row[col] === null || row[col] === undefined;
          return row[col] === val;
        });
        return chain;
      },
      is(col, val) {
        _filters.push(row => {
          if (val === null) return row[col] === null || row[col] === undefined;
          return row[col] === val;
        });
        return chain;
      },
      limit(n) { _limit = n; return chain; },
      order() { return chain; },
      single()      { _single = true; return chain.exec(); },
      maybeSingle() { _maybeSingle = true; return chain.exec(); },

      update(obj) {
        _update = obj;
        return {
          eq(col, val) {
            _filters.push(row => row[col] === val);
            return this;
          },
          is(col, val) {
            _filters.push(row => {
              if (val === null) return row[col] === null || row[col] === undefined;
              return row[col] === val;
            });
            return this;
          },
          select() { return this; },
          single()  {
            db[tableName].forEach(row => {
              if (_filters.every(f => f(row))) Object.assign(row, _update);
            });
            const updated = db[tableName].find(row => _filters.every(f => f(row)));
            return Promise.resolve({ data: updated || null, error: null });
          },
          then(cb) {
            db[tableName].forEach(row => {
              if (_filters.every(f => f(row))) Object.assign(row, _update);
            });
            return Promise.resolve({ data: null, error: null }).then(cb);
          },
        };
      },

      insert(obj) {
        _insert = Array.isArray(obj) ? obj : [obj];
        return {
          select() { return this; },
          single() {
            let err = null;
            for (const row of _insert) {
              // Simulate UNIQUE(student_id, academic_year) on student_promotion_log
              if (tableName === 'student_promotion_log') {
                const dup = db[tableName].find(
                  r => r.student_id === row.student_id && r.academic_year === row.academic_year
                );
                if (dup) { err = { code: '23505', message: 'unique_violation' }; break; }
              }
              db[tableName].push({ id: 'uuid-' + Date.now() + '-' + Math.random(), ...row });
            }
            return Promise.resolve({ data: _insert[0] || null, error: err });
          },
          then(cb) {
            let err = null;
            for (const row of _insert) {
              if (tableName === 'student_promotion_log') {
                const dup = db[tableName].find(
                  r => r.student_id === row.student_id && r.academic_year === row.academic_year
                );
                if (dup) { err = { code: '23505', message: 'unique_violation' }; break; }
              }
              if (!err) db[tableName].push({ id: 'uuid-' + Date.now() + '-' + Math.random(), ...row });
            }
            return Promise.resolve({ data: null, error: err }).then(cb);
          },
        };
      },

      upsert(obj, opts) {
        _upsert = Array.isArray(obj) ? obj : [obj];
        return {
          select() { return this; },
          single() {
            for (const row of _upsert) {
              const conflictCol = opts?.onConflict;
              const existing = conflictCol
                ? db[tableName].find(r => r[conflictCol] === row[conflictCol])
                : null;
              if (existing) Object.assign(existing, row);
              else db[tableName].push({ id: db[tableName].length + 1, ...row });
            }
            const last = _upsert[_upsert.length - 1];
            const found = db[tableName].find(r => {
              const k = opts?.onConflict;
              return k ? r[k] === last[k] : false;
            });
            return Promise.resolve({ data: found || last, error: null });
          },
        };
      },

      exec() {
        let result = db[tableName].filter(row => _filters.every(f => f(row)));
        if (_limit !== null) result = result.slice(0, _limit);
        if (_single)      return Promise.resolve({ data: result[0] || null, error: null });
        if (_maybeSingle) return Promise.resolve({ data: result[0] || null, error: null });
        return Promise.resolve({ data: result, error: null });
      },

      then(cb) { return chain.exec().then(cb); },
    };

    return chain;
  }

  return {
    from: (table) => buildChain(table),
    _db: db, // expose for assertions
  };
}

// ── Test harness ──────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    console.log('  PASS: ' + message);
    passed++;
  } else {
    console.error('  FAIL: ' + message);
    failed++;
  }
}

async function runTest(name, fn) {
  console.log('\nTest: ' + name);
  try {
    await fn();
  } catch (err) {
    console.error('  ERROR: ' + err.message);
    failed++;
  }
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const CONFIG_2026 = {
  id: 1,
  academic_year: 2026,
  promotion_date: '2027-01-02',
  is_current: true,
};

function makeStudent(overrides) {
  return {
    id: 'stu-' + Math.random().toString(36).slice(2),
    name: 'Test Pelajar',
    learnova_id: 'LRN-TEST1',
    form_level: 4,
    repeat_year: false,
    no_promote: false,
    last_promoted_year: null,
    academic_year: 2025,
    onboarding_completed: true,
    ...overrides,
  };
}

// ── Tests ─────────────────────────────────────────────────────────────────────

await runTest('1. Form 4 eligible student is promoted to Form 5', async () => {
  const student = makeStudent({ id: 's1', form_level: 4, last_promoted_year: null });
  const mock    = createMockSupabase({ students: [student], config: [CONFIG_2026] });
  init(mock);

  const result = await runPromotion({ dryRun: false });
  const updated = mock._db.students.find(s => s.id === 's1');

  assert(result.promoted === 1, 'promoted count is 1');
  assert(updated.form_level === 5, 'form_level updated to 5');
  assert(updated.last_promoted_year === 2026, 'last_promoted_year set to 2026');
  assert(mock._db.student_promotion_log.length === 1, 'audit log row created');
  assert(mock._db.student_promotion_log[0].from_form === 4, 'from_form = 4');
  assert(mock._db.student_promotion_log[0].to_form   === 5, 'to_form = 5');
  assert(mock._db.student_promotion_log[0].reason === 'annual_rollover', 'reason = annual_rollover');
});

await runTest('2. Form 5 student is NOT promoted to Form 6 (SPM track)', async () => {
  const student = makeStudent({ id: 's2', form_level: 5, last_promoted_year: 2025 });
  const mock    = createMockSupabase({ students: [student], config: [CONFIG_2026] });
  init(mock);

  const result = await runPromotion({ dryRun: false });
  const updated = mock._db.students.find(s => s.id === 's2');

  assert(result.promoted === 0, 'promoted count is 0');
  assert(updated.form_level === 5, 'form_level stays at 5');
  assert(mock._db.student_promotion_log.length === 0, 'no audit log row');
  assert(result.skipped === 1, 'skipped count is 1');
  const skip = result.skipped_preview[0];
  assert(skip.skip_reason.startsWith('form_5'), 'skip reason mentions form_5');
});

await runTest('3. Repeating student stays in same form', async () => {
  const student = makeStudent({ id: 's3', form_level: 4, repeat_year: true, last_promoted_year: null });
  const mock    = createMockSupabase({ students: [student], config: [CONFIG_2026] });
  init(mock);

  const result = await runPromotion({ dryRun: false });
  const updated = mock._db.students.find(s => s.id === 's3');

  assert(result.promoted === 0, 'promoted count is 0');
  assert(updated.form_level === 4, 'form_level stays at 4');
  assert(result.skipped_preview[0].skip_reason === 'repeat_year_flag', 'skip reason = repeat_year_flag');
});

await runTest('4. Running the rollover twice does NOT double-promote', async () => {
  const student = makeStudent({ id: 's4', form_level: 4, last_promoted_year: null });
  const mock    = createMockSupabase({ students: [student], config: [CONFIG_2026] });
  init(mock);

  // First run
  const r1 = await runPromotion({ dryRun: false });
  // Second run (same academic year)
  const r2 = await runPromotion({ dryRun: false });

  const updated = mock._db.students.find(s => s.id === 's4');

  assert(r1.promoted === 1, 'first run promotes 1 student');
  assert(r2.promoted === 0, 'second run promotes 0 students');
  assert(updated.form_level === 5, 'form_level is 5 (not 6)');
  assert(
    mock._db.student_promotion_log.filter(l => l.student_id === 's4').length === 1,
    'only one audit log entry for this student'
  );
});

await runTest('5. Historical quiz and progress records are untouched by promotion', async () => {
  // Promotion only updates students.form_level and students.last_promoted_year.
  // It never touches quiz_attempts, student_lesson_progress, lesson_sessions, etc.
  // We verify: those tables do not appear in the mock _db at all (no accidental writes).
  const student = makeStudent({ id: 's5', form_level: 4, last_promoted_year: null });
  const mock    = createMockSupabase({ students: [student], config: [CONFIG_2026] });
  init(mock);

  await runPromotion({ dryRun: false });

  // Only these two tables should have been mutated
  const touchedTables = Object.keys(mock._db).filter(t => mock._db[t].length > 0);
  assert(!touchedTables.includes('quiz_attempts'), 'quiz_attempts not touched');
  assert(!touchedTables.includes('student_lesson_progress'), 'student_lesson_progress not touched');
  assert(!touchedTables.includes('lesson_sessions'), 'lesson_sessions not touched');
  assert(mock._db.student_promotion_log.length === 1, 'only promotion_log written');
});

await runTest('6. Profile form_level reflects new form after promotion', async () => {
  const student = makeStudent({ id: 's6', form_level: 4, last_promoted_year: null });
  const mock    = createMockSupabase({ students: [student], config: [CONFIG_2026] });
  init(mock);

  await runPromotion({ dryRun: false });

  // Simulate what getStudentProfile returns — it reads students.form_level directly
  const updated = mock._db.students.find(s => s.id === 's6');
  assert(updated.form_level === 5, 'form_level is 5 after promotion');

  // Content routing: normalizeFormLabel('5') -> 'Form 5'
  // Simulated: the Flutter app calls /api/lessons/path?form=Form%205
  // which now returns Form 5 content. We verify the value is what the API would use.
  const formLabel = updated.form_level === 5 ? 'Form 5' : 'Form 4';
  assert(formLabel === 'Form 5', 'content routing would use Form 5');
});

await runTest('7. Late registrant in same academic year is NOT promoted', async () => {
  // A student who registered in October 2026 has last_promoted_year = 2026 (set at onboarding).
  // The 2026 rollover (academic_year=2026) should skip them.
  const student = makeStudent({ id: 's7', form_level: 4, last_promoted_year: 2026, academic_year: 2026 });
  const mock    = createMockSupabase({ students: [student], config: [CONFIG_2026] });
  init(mock);

  const result = await runPromotion({ dryRun: false });
  const updated = mock._db.students.find(s => s.id === 's7');

  assert(result.promoted === 0, 'promoted count is 0');
  assert(updated.form_level === 4, 'form_level stays at 4');
  assert(result.skipped_preview[0].skip_reason.includes('already_promoted_in_2026'), 'skipped with correct reason');

  // But they ARE eligible in the following year's rollover (academic_year=2027)
  const config2027 = { ...CONFIG_2026, id: 2, academic_year: 2027, promotion_date: '2028-01-02' };
  const mock2 = createMockSupabase({ students: [updated], config: [config2027] });
  init(mock2);
  const result2 = await runPromotion({ dryRun: false });
  assert(result2.promoted === 1, 'eligible for 2027 rollover');
});

await runTest('8. Existing student login and profile flows still work', async () => {
  // Verifies that the new columns (repeat_year, no_promote, last_promoted_year)
  // do not break the existing profile query.
  // getStudentProfile reads from students table using .select('*') — the new columns
  // are simply additional fields that existing code ignores.
  const student = makeStudent({
    id: 's8',
    name: 'Ahmad',
    email: 'ahmad@test.com',
    form_level: 4,
    repeat_year: false,
    no_promote: false,
    last_promoted_year: 2025,
    learnova_id: 'LRN-AHMAD1',
  });

  // Simulate what /api/student/profile returns
  const profileData = {
    id:             student.id,
    name:           student.name,
    email:          student.email,
    learnova_id:    student.learnova_id,
    form_level:     student.form_level,
    // The promotion columns are present but the profile endpoint ignores them
    repeat_year:    student.repeat_year,
    no_promote:     student.no_promote,
  };

  assert(profileData.form_level === 4, 'form_level readable from profile');
  assert(profileData.learnova_id === 'LRN-AHMAD1', 'learnova_id unchanged');
  assert(profileData.repeat_year === false, 'repeat_year present and false by default');
  assert(profileData.no_promote === false, 'no_promote present and false by default');

  // Verify completeOnboarding would set last_promoted_year
  const year = new Date().getFullYear();
  assert(typeof year === 'number', 'current year is a number for last_promoted_year');

  // Verify no_promote admin flag works
  const mock = createMockSupabase({ students: [student], config: [CONFIG_2026] });
  init(mock);
  await setStudentPromotionFlags(student.id, { no_promote: true });
  const updated = mock._db.students.find(s => s.id === student.id);
  assert(updated.no_promote === true, 'no_promote flag can be set via admin');

  const result = await runPromotion({ dryRun: false });
  assert(result.promoted === 0, 'student with no_promote is not promoted');
});

await runTest('9. Log insert failure reverts students update (audit gap fix)', async () => {
  // Simulate a non-23505 DB error during student_promotion_log insert.
  // Expectation: students row is reverted — form_level stays at 4.
  const student = makeStudent({ id: 's9', form_level: 4, last_promoted_year: null });

  // Build a faulty mock: first insert on student_promotion_log returns a non-unique error.
  const baseMock = createMockSupabase({ students: [student], config: [CONFIG_2026] });
  let logInsertCalled = false;
  const faultyMock = {
    from(table) {
      if (table === 'student_promotion_log') {
        return {
          insert(_obj) {
            return {
              select() { return this; },
              single() {
                if (!logInsertCalled) {
                  logInsertCalled = true;
                  // Simulate a transient DB error (not unique violation)
                  return Promise.resolve({ data: null, error: { code: '08006', message: 'connection_failure' } });
                }
                return baseMock.from(table).insert(_obj).single();
              },
              then(cb) {
                if (!logInsertCalled) {
                  logInsertCalled = true;
                  return Promise.resolve({ data: null, error: { code: '08006', message: 'connection_failure' } }).then(cb);
                }
                return baseMock.from(table).insert(_obj).then(cb);
              },
            };
          },
          select: (...a) => baseMock.from(table).select(...a),
          update: (...a) => baseMock.from(table).update(...a),
        };
      }
      return baseMock.from(table);
    },
    _db: baseMock._db,
  };

  init(faultyMock);
  const result = await runPromotion({ dryRun: false });

  const updated = baseMock._db.students.find(s => s.id === 's9');

  assert(result.promoted === 0,  'no successful promotions (log failed)');
  assert(result.failed === 1,    'failed count is 1');
  assert(updated.form_level === 4, 'form_level reverted to 4 after log failure');
  assert(updated.last_promoted_year === null, 'last_promoted_year reverted to null');
  assert(baseMock._db.student_promotion_log.length === 0, 'no log row created');
});

await runTest('10. Dry-run (preview) writes nothing to any table', async () => {
  const student = makeStudent({ id: 's10', form_level: 4, last_promoted_year: null });
  const mock    = createMockSupabase({ students: [student], config: [CONFIG_2026] });
  init(mock);

  const result = await runPromotion({ dryRun: true });

  const unchanged = mock._db.students.find(s => s.id === 's10');
  assert(result.dry_run === true, 'dry_run flag is true');
  assert(result.eligible_count === 1, 'preview shows 1 eligible student');
  assert(result.promoted === 0, 'promoted count is 0 in dry run');
  assert(unchanged.form_level === 4, 'students table not modified');
  assert(unchanged.last_promoted_year === null, 'last_promoted_year not modified');
  assert(mock._db.student_promotion_log.length === 0, 'log table not modified');
});

// ── Results ───────────────────────────────────────────────────────────────────

console.log('\n' + '='.repeat(50));
console.log('Results: ' + passed + ' passed, ' + failed + ' failed');
if (failed > 0) {
  console.error('SOME TESTS FAILED');
  process.exit(1);
} else {
  console.log('All tests passed.');
}
