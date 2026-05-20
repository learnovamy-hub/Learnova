// learning_engine.mjs â€” Clean rewrite
import express from 'express';
import Anthropic from '@anthropic-ai/sdk';

const router = express.Router();
let _sb = null;
export function init(s) { _sb = s; }
const db = () => _sb;
const ai = () => new Anthropic({ apiKey: process.env.CLAUDE_API_KEY });

const PASS = 70, REFRESH_DAYS = 3, MAX_NEW = 1, MAX_SESS = 3;

// Normalize subject to match Supabase casing (e.g. "physics" â†’ "Physics")
function normalizeSubject(raw) {
  if (!raw) return raw;
  const map = {
    mathematics: 'Mathematics',
    maths: 'Mathematics',
    math: 'Mathematics',
    physics: 'Physics',
    chemistry: 'Chemistry',
    biology: 'Biology',
    sejarah: 'Sejarah',
    history: 'Sejarah',
    english: 'English',
    'bahasa malaysia': 'Bahasa Malaysia',
    bm: 'Bahasa Malaysia',
  };
  return map[raw.toLowerCase()] || (raw.charAt(0).toUpperCase() + raw.slice(1));
}

const PEDAGOGY = {
  Mathematics: { concept: 'State FORMULA first. Explain each variable. ONE concept. End: "Jom tengok contoh."', example: 'Step by step: Langkah 1,2,3. Show formula then substitute. End: "Sekarang awak pula cuba."', checkin: 'ONE calculation. "Cuba kira: [problem]". No hints.', reexplain: 'Different scenario. Break into smaller pieces.', refresher: 'Mix recall + calculations. Include a trap question.' },
  Physics: { concept: 'Start with real phenomenon. Principle first, equation after. State SI units. End: "Jom tengok penggunaan."', example: 'State diberi/cari. Write equation, substitute. Check if reasonable.', checkin: 'One conceptual + one calculation.', reexplain: 'Different context. Re-describe situation.', refresher: 'Definitions, diagrams, calculations. SPM parts a/b/c.' },
  Chemistry: { concept: 'Particle level FIRST. Connect to observable. Balanced equations with state symbols. End: "Jom tengok contoh."', example: 'Mole ratio from balanced equation. Show molar mass. Observationâ†’inferenceâ†’conclusion.', checkin: 'Equation balancing + one mole problem.', reexplain: 'Back to particle level.', refresher: 'Balancing, ionic equations, mole calc.' },
  Biology: { concept: 'Structureâ†’Functionâ†’Processâ†’Significance. Use mnemonics. End: "Jom tengok proses."', example: 'Numbered steps. Punnett square for genetics. Define terms.', checkin: 'Process question + diagram/labelling.', reexplain: 'Body-system analogy. Smaller steps.', refresher: 'Diagram labelling, sequencing, comparison tables.' },
  Sejarah: { concept: 'Set context first. Introduce event. Explain causes. Storytelling. End: "Jom tengok kesan."', example: 'PEKA: Point, Elaboration, Knowledge, Application.', checkin: 'Factual recall + cause/effect.', reexplain: 'Different angle, cause-effect chain.', refresher: '"Nyatakan...", "Jelaskan...", "Huraikan..."' },
  English: { concept: 'Grammar rule as simple formula. Show in context. Point out Malaysian errors. End: "Got the pattern?"', example: 'Correct vs incorrect side by side. Annotated paragraph.', checkin: 'Fill-in-blank or error correction.', reexplain: 'Different sentence. Address Manglish.', refresher: 'SPM format: summary, directed writing, literature.' },
  'Bahasa Malaysia': { concept: 'Nyatakan hukum. Tunjukkan contoh. Asingkan kesilapan. End: "Jom tengok penulisan."', example: 'Perenggan model. Ayat betul vs salah. PEKA.', checkin: 'Isi tempat kosong ATAU betulkan ayat.', reexplain: 'Konteks berbeza. Langkah lebih kecil.', refresher: 'Karangan, rumusan, komsas, tatabahasa.' },
};

function buildPrompt(subject, phase, topic, subtopic, sessionType) {
  const p = PEDAGOGY[subject] || { concept:'Introduce one concept.', example:'Walk through one example.', checkin:'Ask one question.', reexplain:'Re-explain differently.', refresher:'Mix recall and application.' };
  const m = { concept_intro: p.concept, worked_example: p.example, check_in: p.checkin, check_in_2: p.checkin, re_explain: p.reexplain, complete: 'Summarise warmly.' };
  const instr = sessionType === 'refresher' ? `REFRESHER: ${p.refresher} Ask 3-5 questions, increase difficulty.` : (m[phase] || p.concept);
  return `You are Nova, Learnova AI tutor for Malaysian SPM students. Warm, patient, BM-English mix.\nSubject: ${subject} | Topic: ${topic}${subtopic?'|'+subtopic:''} | Phase: ${phase} | Session: ${sessionType}\n${instr}\nRULES: One concept at a time. Never reveal answers early. Kesilapan adalah sebahagian pembelajaran.`;
}

async function getProgress(sid, subj, ch) {
  const { data } = await db().from('student_topic_progress').select('*').eq('student_id', sid).eq('subject', subj).eq('chapter_number', ch).maybeSingle();
  return data;
}

async function getTodayLog(sid) {
  const today = new Date().toISOString().split('T')[0];
  const { data } = await db().from('daily_session_log').select('*').eq('student_id', sid).eq('session_date', today).maybeSingle();
  return data;
}

async function upsertLog(sid, newTopic, newCh) {
  const today = new Date().toISOString().split('T')[0];
  const log = await getTodayLog(sid);
  if (!log) {
    await db().from('daily_session_log').insert({ student_id: sid, session_date: today, new_topic_learned: newTopic||null, new_chapter_number: newCh||null, session_count: 1, new_topic_limit_hit: !!newTopic });
  } else {
    const p = { session_count: log.session_count + 1 };
    if (newTopic) { p.new_topic_learned = newTopic; p.new_topic_limit_hit = true; }
    await db().from('daily_session_log').update(p).eq('id', log.id);
  }
}

router.get('/debug', (req, res) => res.json({ db_ready: !!_sb }));

// GET /api/learn/debug/lessons â€” raw dump, no filters
router.get('/debug/lessons', async (req, res) => {
  try {
    const { data, error } = await db()
      .from('lessons')
      .select('id, chapter_number, topic, title, subject, curriculum, is_published')
      .limit(20);
    return res.json({ count: data?.length || 0, error: error?.message || null, rows: data || [] });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// GET /api/learn/topics/:studentId/:subject
router.get('/topics/:studentId/:subject', async (req, res) => {
  try {
    const { studentId } = req.params;
    const subject = normalizeSubject(req.params.subject);

    console.log(`[topics] studentId=${studentId} subject=${subject}`);

    // curriculum filter removed â€” values may differ in DB; subject alone is sufficient
    const { data: lessons, error: lessonsError } = await db()
      .from('lessons')
      .select('chapter_number, topic, title, subject, curriculum')
      .eq('subject', subject)
      .gt('chapter_number', 0)
      .order('chapter_number', { ascending: true });

    console.log(`[topics] lessons count=${lessons?.length} error=${lessonsError?.message} rows=${JSON.stringify(lessons?.slice(0,2))}`);

    if (!lessons?.length) return res.json({ topics: [], sessions_today: 0, sessions_remaining: MAX_SESS, can_study_today: true });

    // Seed first topic
    const first = lessons[0];
    const { data: ex } = await db().from('student_topic_progress').select('id').eq('student_id', studentId).eq('subject', subject).eq('chapter_number', first.chapter_number).maybeSingle();
    if (!ex) await db().from('student_topic_progress').insert({ student_id: studentId, subject, chapter_number: first.chapter_number, topic: first.topic, status: 'available', unlocked_at: new Date().toISOString() });

    const { data: progress } = await db().from('student_topic_progress').select('*').eq('student_id', studentId).eq('subject', subject);
    const pm = {}; (progress||[]).forEach(p => { pm[p.chapter_number] = p; });

    const topics = lessons.map((l, i) => {
      const p = pm[l.chapter_number];
      let status = 'locked';
      if (p) { status = p.status; }
      else if (i === 0) { status = 'available'; }
      else { const prev = pm[lessons[i-1].chapter_number]; if (prev && ['refresher','mastered'].includes(prev.status)) status = 'available'; }
      return { chapter_number: l.chapter_number, topic: l.topic, title: l.title, status, progress: p||null };
    });

    const log = await getTodayLog(studentId);
    const done = log?.session_count || 0;
    const canStudy = done < MAX_SESS;
    return res.json({ topics, sessions_today: done, sessions_remaining: Math.max(0, MAX_SESS - done), can_study_today: canStudy, daily_message: canStudy ? null : `Awak dah buat ${done} sesi hari ini. Kembali esok!` });
  } catch (e) {
    console.error('[topics] error:', e);
    res.status(500).json({ error: e.message });
  }
});

// POST /api/learn/session/start
router.post('/session/start', async (req, res) => {
  try {
    const { student_id, chapter_number, topic } = req.body;
    const subject = normalizeSubject(req.body.subject); // â† FIX: normalize casing

    const today = new Date().toISOString().split('T')[0];
    const log = await getTodayLog(student_id);
    const done = log?.session_count || 0;
    if (done >= MAX_SESS) return res.status(403).json({ allowed: false, reason: `Awak dah buat ${done} sesi hari ini! Rehat dan kembali esok.`, come_back_tomorrow: true });

    let progress = await getProgress(student_id, subject, chapter_number);
    if (!progress) {
      const { data: lessons } = await db().from('lessons').select('chapter_number').eq('subject', subject).eq('curriculum', 'SPM').gt('chapter_number', 0).order('chapter_number', { ascending: true });
      const idx = (lessons||[]).findIndex(l => l.chapter_number === chapter_number);
      if (idx > 0) {
        const prev = await getProgress(student_id, subject, lessons[idx-1].chapter_number);
        if (!prev || !['refresher','mastered'].includes(prev.status)) return res.status(403).json({ allowed: false, reason: 'Topik ini masih terkunci. Selesaikan topik sebelumnya dahulu.', locked: true });
      }
      if (log?.new_topic_limit_hit) return res.status(403).json({ allowed: false, reason: 'Awak dah mulakan topik baru hari ini! Cuba esok.', come_back_tomorrow: true });
      const { data: newP } = await db().from('student_topic_progress').insert({ student_id, subject, chapter_number, topic, status: 'in_progress', sessions_on_topic: 1, first_session_date: today, last_session_date: today, unlocked_at: new Date().toISOString() }).select().single();
      progress = newP;
      await upsertLog(student_id, topic, chapter_number);
    } else {
      if (progress.status === 'locked') return res.status(403).json({ allowed: false, reason: 'Topik ini masih terkunci.', locked: true });
      await db().from('student_topic_progress').update({ sessions_on_topic: (progress.sessions_on_topic||0)+1, last_session_date: today, status: progress.status === 'available' ? 'in_progress' : progress.status }).eq('id', progress.id);
      await upsertLog(student_id, null, null);
    }
    const { data: session } = await db().from('session_logs').insert({ student_id, subject, topic, session_start: new Date().toISOString() }).select().single();
    const sessionType = ['refresher','mastered'].includes(progress.status) ? 'refresher' : 'learning';
    return res.json({ allowed: true, session_id: session?.id, session_type: sessionType, status: progress.status, sessions_remaining: MAX_SESS-(done+1), message: sessionType==='refresher' ? `Selamat datang semula! Sesi ulang kaji untuk "${topic}".` : null });
  } catch (e) {
    console.error('[session/start] error:', e);
    res.status(500).json({ error: e.message });
  }
});

// POST /api/learn/chat
router.post('/chat', async (req, res) => {
  try {
    const { session_id, student_id, subject, topic, subtopic, message, session_type='learning', current_phase='concept_intro', request_advance=false } = req.body;
    let { data: ps } = await db().from('session_phases').select('*').eq('session_id', session_id).maybeSingle();
    if (!ps) {
      const { data: n } = await db().from('session_phases').insert({ session_id, student_id, subject, topic, subtopic: subtopic||null, current_phase: 'concept_intro', concepts_taught: 0, checkin_attempts: 0, conversation: [] }).select().single();
      ps = n;
    }
    if (request_advance) {
      const adv = { concept_intro: 'worked_example', worked_example: 'check_in' };
      if (adv[ps.current_phase]) { await db().from('session_phases').update({ current_phase: adv[ps.current_phase] }).eq('id', ps.id); ps.current_phase = adv[ps.current_phase]; }
    }
    const convo = ps.conversation || [];
    convo.push({ role: 'user', content: message, phase: ps.current_phase });
    const sys = buildPrompt(subject, ps.current_phase, topic, subtopic, session_type);
    const msgs = convo.map(m => ({ role: m.role, content: m.content }));
    const resp = await ai().messages.create({ model: 'claude-haiku-4-5-20251001', max_tokens: 700, system: sys, messages: msgs });
    const reply = resp.content[0].text;
    const rl = reply.toLowerCase();
    let np = ps.current_phase;
    if (ps.current_phase==='concept_intro' && ['jom saya tunjukkan','jom tengok contoh','let me show'].some(s=>rl.includes(s))) np='worked_example';
    else if (ps.current_phase==='worked_example' && ['sekarang awak pula','cuba kira','now you try','cuba awak'].some(s=>rl.includes(s))) np='check_in';
    if (np!==ps.current_phase) await db().from('session_phases').update({ current_phase: np }).eq('id', ps.id);
    convo.push({ role: 'assistant', content: reply, phase: np });
    await db().from('session_phases').update({ conversation: convo }).eq('id', ps.id);
    return res.json({ reply, phase: np, session_type, show_advance_button: ['concept_intro','worked_example'].includes(np), show_quiz_button: np==='complete' });
  } catch (e) {
    console.error('[chat] error:', e);
    res.status(500).json({ error: e.message });
  }
});

// POST /api/learn/quiz/submit
router.post('/quiz/submit', async (req, res) => {
  try {
    const { student_id, subject, chapter_number, topic, score, questions_total, questions_correct } = req.body;
    const today = new Date().toISOString().split('T')[0];
    const progress = await getProgress(student_id, subject, chapter_number);
    if (!progress) return res.status(404).json({ error: 'No progress record' });
    const passed = score >= PASS;
    let newStatus = progress.status, message = '', nextUnlocked = false;
    await db().from('topic_quiz_results').insert({ student_id, subject, chapter_number, topic, session_type: progress.status==='refresher'?'refresher':'learning', score, questions_total, questions_correct }).catch(()=>{});
    if (passed && progress.status==='in_progress') {
      newStatus = 'refresher';
      message = `Tahniah! Awak lulus dengan ${score}%! Sesi seterusnya akan jadi ulang kaji.`;
      const { data: next } = await db().from('lessons').select('chapter_number,topic').eq('subject', subject).eq('chapter_number', chapter_number+1).maybeSingle();
      if (next) { const { data: ex } = await db().from('student_topic_progress').select('id').eq('student_id', student_id).eq('subject', subject).eq('chapter_number', next.chapter_number).maybeSingle(); if (!ex) { await db().from('student_topic_progress').insert({ student_id, subject, chapter_number: next.chapter_number, topic: next.topic, status: 'available', unlocked_at: new Date().toISOString() }); nextUnlocked = true; } }
      await db().from('student_topic_progress').update({ status: newStatus, passed_quiz: true, best_quiz_score: Math.max(progress.best_quiz_score||0, score), last_quiz_score: score, quiz_attempts: (progress.quiz_attempts||0)+1, completed_at: new Date().toISOString() }).eq('id', progress.id);
    } else if (progress.status==='refresher') {
      const days = progress.refresher_days || [];
      if (!days.includes(today)) days.push(today);
      const done = (progress.refresher_sessions_done||0)+1;
      const complete = days.length >= REFRESH_DAYS;
      newStatus = complete ? 'mastered' : 'refresher';
      message = complete ? `Luar biasa! Awak telah menguasai topik ${topic}! â­` : `Ulang kaji ${days.length}/${REFRESH_DAYS} hari. Kembali lagi ${REFRESH_DAYS-days.length} hari!`;
      await db().from('student_topic_progress').update({ status: newStatus, refresher_sessions_done: done, refresher_days: days, refresher_complete: complete, best_quiz_score: Math.max(progress.best_quiz_score||0, score), last_quiz_score: score, quiz_attempts: (progress.quiz_attempts||0)+1, mastered_at: complete?new Date().toISOString():null }).eq('id', progress.id);
    } else if (!passed) {
      message = `Awak dapat ${score}%. Perlu ${PASS}% untuk teruskan. Jangan risau!`;
      await db().from('student_topic_progress').update({ best_quiz_score: Math.max(progress.best_quiz_score||0, score), last_quiz_score: score, quiz_attempts: (progress.quiz_attempts||0)+1 }).eq('id', progress.id);
    }
    return res.json({ passed, score, new_status: newStatus, message, next_topic_unlocked: nextUnlocked });
  } catch (e) {
    console.error('[quiz/submit] error:', e);
    res.status(500).json({ error: e.message });
  }
});

// GET /api/learn/dashboard/:studentId
router.get('/dashboard/:studentId', async (req, res) => {
  try {
    const { studentId } = req.params;
    const log = await getTodayLog(studentId);
    const done = log?.session_count || 0;
    const canStudy = done < MAX_SESS;
    const today = new Date().toISOString().split('T')[0];
    const { data: active } = await db().from('student_topic_progress').select('*').eq('student_id', studentId).in('status', ['in_progress','refresher']).order('last_session_date', { ascending: false });
    const { data: avail } = await db().from('student_topic_progress').select('*').eq('student_id', studentId).eq('status', 'available');
    const refresherDue = (active||[]).filter(t => t.status==='refresher' && (!t.last_session_date || t.last_session_date < today));
    let rec = null;
    if (canStudy) {
      if (refresherDue.length) rec = { type:'refresher', topic:refresherDue[0].topic, subject:refresherDue[0].subject, message:`Jom buat ulang kaji untuk "${refresherDue[0].topic}"!` };
      else if ((active||[]).find(t=>t.status==='in_progress')) { const t=active.find(t=>t.status==='in_progress'); rec={type:'continue',topic:t.topic,subject:t.subject,message:`Sambung belajar "${t.topic}".`}; }
      else if (avail?.length) rec={type:'new_topic',topic:avail[0].topic,subject:avail[0].subject,message:`Topik baru: "${avail[0].topic}"!`};
    }
    return res.json({ can_study_today: canStudy, sessions_remaining: Math.max(0,MAX_SESS-done), daily_message: canStudy?null:`Dah ${done} sesi hari ini. Kembali esok!`, refresher_due: refresherDue, active_topics: (active||[]).filter(t=>t.status==='in_progress'), available_topics: avail||[], recommendation: rec });
  } catch (e) {
    console.error('[dashboard] error:', e);
    res.status(500).json({ error: e.message });
  }
});

// GET /api/learn/revision/:studentId/:subject
router.get('/revision/:studentId/:subject', async (req, res) => {
  try {
    const subject = normalizeSubject(req.params.subject); // â† FIX: normalize casing
    const { data } = await db().from('student_topic_progress').select('*').eq('student_id', req.params.studentId).eq('subject', subject).in('status', ['in_progress','refresher','mastered']).order('chapter_number', { ascending: true });
    return res.json({ revision_topics: data||[] });
  } catch (e) {
    console.error('[revision] error:', e);
    res.status(500).json({ error: e.message });
  }
});

export default router;

