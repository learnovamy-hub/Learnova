import cron from 'node-cron';

let _supabase = null;

export function init(supabase) {
  _supabase = supabase;
}

// SPM track promotion rules.
// Form 4 -> Form 5 is the only valid automatic promotion.
// Form 5 students are NOT automatically promoted to Form 6 (A-Level is a separate track).
const PROMOTION_RULES = { 4: 5 };

// ── Config management ─────────────────────────────────────────────────────────

export async function getActiveConfig() {
  const { data, error } = await _supabase
    .from('academic_year_config')
    .select('*')
    .eq('is_current', true)
    .limit(1)
    .maybeSingle();
  if (error) throw new Error('academic_year_config query failed: ' + error.message);
  return data; // null if not set
}

export async function setAcademicYearConfig({ academic_year, promotion_date }) {
  if (!academic_year || !promotion_date) {
    throw new Error('academic_year and promotion_date are required');
  }
  // Clear all existing current flags first
  await _supabase
    .from('academic_year_config')
    .update({ is_current: false })
    .eq('is_current', true);

  const { data, error } = await _supabase
    .from('academic_year_config')
    .upsert(
      { academic_year, promotion_date, is_current: true, updated_at: new Date().toISOString() },
      { onConflict: 'academic_year' }
    )
    .select()
    .single();
  if (error) throw new Error('setAcademicYearConfig failed: ' + error.message);
  return data;
}

// ── Student classification ────────────────────────────────────────────────────

function classifyOne(student, config) {
  const targetForm = PROMOTION_RULES[student.form_level];

  if (!targetForm) {
    return {
      action: 'skip',
      reason: 'form_' + student.form_level + '_no_auto_promotion',
    };
  }
  if (student.no_promote) {
    return { action: 'skip', reason: 'no_promote_flag' };
  }
  if (student.repeat_year) {
    return { action: 'skip', reason: 'repeat_year_flag' };
  }
  // Idempotency: already processed in this academic year.
  // Explicit null check: null is treated as "never promoted" (eligible).
  if (
    student.last_promoted_year !== null &&
    student.last_promoted_year !== undefined &&
    student.last_promoted_year >= config.academic_year
  ) {
    return { action: 'skip', reason: 'already_promoted_in_' + student.last_promoted_year };
  }

  return { action: 'promote', target_form: targetForm };
}

async function classifyAll(config) {
  const { data: students, error } = await _supabase
    .from('students')
    .select(
      'id, name, learnova_id, form_level, repeat_year, no_promote,' +
      ' last_promoted_year, academic_year, onboarding_completed'
    )
    .eq('onboarding_completed', true);

  if (error) throw new Error('students query failed: ' + error.message);

  const eligible = [];
  const skipped  = [];

  for (const s of (students || [])) {
    const verdict = classifyOne(s, config);
    if (verdict.action === 'promote') {
      eligible.push({ ...s, target_form: verdict.target_form });
    } else {
      skipped.push({ ...s, skip_reason: verdict.reason });
    }
  }

  return { eligible, skipped };
}

// ── Core promotion runner ─────────────────────────────────────────────────────

export async function runPromotion({ dryRun = false } = {}) {
  const config = await getActiveConfig();
  if (!config) {
    throw new Error(
      'No active academic_year_config found. ' +
      'POST /api/admin/promotion/config to set one.'
    );
  }

  const { eligible, skipped } = await classifyAll(config);
  const log = [];

  if (!dryRun) {
    for (const s of eligible) {
      try {
        // Update form level and mark as promoted for this academic year.
        const { error: updateErr } = await _supabase
          .from('students')
          .update({
            form_level: s.target_form,
            last_promoted_year: config.academic_year,
          })
          .eq('id', s.id);

        if (updateErr) throw new Error(updateErr.message);

        // Insert audit log row.
        // UNIQUE(student_id, academic_year) on the table prevents a duplicate
        // if somehow this block runs twice concurrently.
        const { error: logErr } = await _supabase
          .from('student_promotion_log')
          .insert({
            student_id:    s.id,
            from_form:     s.form_level,
            to_form:       s.target_form,
            academic_year: config.academic_year,
            reason:        'annual_rollover',
            promoted_by:   'system',
          });

        if (logErr && logErr.code === '23505') {
          // Unique violation: log row already exists from a previous run.
          // The students.last_promoted_year update above was a no-op because
          // classifyAll already filtered this student out on re-run.
          // This path is only reachable under a race condition; log and continue.
          console.warn('[promotion] Duplicate log entry for ' + s.id + ' (idempotent skip)');
          log.push({ ...rowSummary(s), status: 'duplicate_skip' });
          continue;
        }

        if (logErr) {
          // Non-idempotent log failure: revert the students row so the promotion
          // can be retried cleanly on the next run. If the revert also fails,
          // log both errors — manual intervention needed.
          const { error: revertErr } = await _supabase
            .from('students')
            .update({
              form_level:         s.form_level,
              last_promoted_year: s.last_promoted_year !== undefined ? s.last_promoted_year : null,
            })
            .eq('id', s.id);
          if (revertErr) {
            console.error('[promotion] REVERT FAILED for ' + s.id + ': ' + revertErr.message);
          }
          throw new Error('log_insert_failed: ' + logErr.message);
        }

        log.push({ ...rowSummary(s), status: 'promoted' });
        console.log(
          '[promotion] ' + (s.learnova_id || s.id) +
          ' (' + s.name + '): Form ' + s.form_level + ' -> Form ' + s.target_form
        );
      } catch (err) {
        log.push({ ...rowSummary(s), status: 'failed', error: err.message });
        console.error('[promotion] Failed for ' + s.id + ':', err.message);
      }
    }
  }

  return buildSummary({ config, eligible, skipped, log, dryRun });
}

// Alias — identical to dry-run
export async function previewPromotion() {
  return runPromotion({ dryRun: true });
}

// ── Per-student admin override ────────────────────────────────────────────────

export async function setStudentPromotionFlags(studentId, flags) {
  const allowed = ['repeat_year', 'no_promote'];
  const update  = {};
  for (const k of allowed) {
    if (flags[k] !== undefined) update[k] = Boolean(flags[k]);
  }
  if (Object.keys(update).length === 0) {
    throw new Error('Provide at least one of: repeat_year, no_promote');
  }
  const { data, error } = await _supabase
    .from('students')
    .update(update)
    .eq('id', studentId)
    .select('id, name, learnova_id, form_level, repeat_year, no_promote, last_promoted_year')
    .single();
  if (error) throw new Error(error.message);
  return data;
}

// ── Promotion history ─────────────────────────────────────────────────────────

export async function getPromotionLog({ limit = 50 } = {}) {
  const { data, error } = await _supabase
    .from('student_promotion_log')
    .select('*')
    .order('promoted_at', { ascending: false })
    .limit(limit);
  if (error) throw new Error(error.message);
  return data || [];
}

// ── Scheduled daily check ─────────────────────────────────────────────────────

async function checkAndRunDailyPromotion() {
  try {
    const config = await getActiveConfig();
    if (!config) {
      // No config set yet — nothing to do.
      return;
    }

    // Compare today's date in KL time against the configured promotion_date.
    // toLocaleDateString with 'sv-SE' returns YYYY-MM-DD without any locale overhead.
    const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Kuala_Lumpur' });
    if (today !== config.promotion_date) return;

    console.log(
      '[promotion] Promotion date matched: ' + today +
      ' (academic_year ' + config.academic_year + '). Running.'
    );
    const result = await runPromotion({ dryRun: false });
    console.log(
      '[promotion] Complete: ' + result.promoted + ' promoted, ' +
      result.skipped + ' skipped, ' + result.failed + ' failed.'
    );
  } catch (err) {
    console.error('[promotion] Scheduled run error:', err.message);
  }
}

// Called once at server startup.
// Runs at 01:00 Asia/Kuala_Lumpur daily — checks whether today is the configured
// promotion date, and promotes if so.
export function startAnnualPromotionJob(supabase) {
  if (supabase) init(supabase);
  cron.schedule(
    '0 1 * * *',
    () =>
      checkAndRunDailyPromotion().catch(e =>
        console.error('[promotion] Uncaught:', e.message)
      ),
    { timezone: 'Asia/Kuala_Lumpur' }
  );
  console.log('[promotion] Annual promotion job scheduled (01:00 Asia/Kuala_Lumpur daily)');
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function rowSummary(s) {
  return {
    student_id: s.id,
    name:       s.name,
    learnova_id: s.learnova_id,
    from_form:  s.form_level,
    to_form:    s.target_form,
  };
}

function buildSummary({ config, eligible, skipped, log, dryRun }) {
  const promoted = dryRun ? 0 : log.filter(l => l.status === 'promoted').length;
  const failed   = dryRun ? 0 : log.filter(l => l.status === 'failed').length;

  return {
    academic_year:  config.academic_year,
    promotion_date: config.promotion_date,
    dry_run:        dryRun,
    promoted,
    skipped: skipped.length,
    failed,
    eligible_count: eligible.length,
    // Preview lists are always returned (empty in live run)
    eligible_preview: eligible.map(s => ({
      id:         s.id,
      name:       s.name,
      learnova_id: s.learnova_id,
      from_form:  s.form_level,
      to_form:    s.target_form,
    })),
    skipped_preview: skipped.map(s => ({
      id:         s.id,
      name:       s.name,
      learnova_id: s.learnova_id,
      form_level:  s.form_level,
      skip_reason: s.skip_reason,
    })),
    log: dryRun ? [] : log,
  };
}
