// ============================================================
// learning_engine.mjs — Pedagogy + Pacing + Topic Gating
// Location: C:\Learnova\learning_engine.mjs
// Add to server_updated.mjs:
//   import learningEngine from './learning_engine.mjs';
//   app.use('/api/learn', learningEngine);
// ============================================================

import express from 'express';
import Anthropic from '@anthropic-ai/sdk';
import { createClient } from '@supabase/supabase-js';

const router  = express.Router();
const claude  = new Anthropic({ apiKey: process.env.CLAUDE_API_KEY });
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY);

// ── Config ────────────────────────────────────────────────────
const CONFIG = {
  QUIZ_PASS_THRESHOLD:       70,
  REFRESHER_SESSIONS_NEEDED: 3,
  MAX_NEW_TOPICS_PER_DAY:    1,
  MAX_SESSIONS_PER_DAY:      3,
};

const STATUS = {
  LOCKED:      'locked',
  AVAILABLE:   'available',
  IN_PROGRESS: 'in_progress',
  REFRESHER:   'refresher',
  MASTERED:    'mastered',
};

// ── Subject pedagogy prompts ──────────────────────────────────
const PEDAGOGY = {
  Mathematics: {
    identity: 'You are teaching Mathematics. Your approach is FORMULA-FIRST then PROCESS.',
    concept:  'State the formula FIRST before any explanation. Explain each variable simply. Use price/distance/speed analogies. ONE concept only. End with: "Dah nampak formula dia? Jom tengok macam mana nak guna."',
    example:  'Show full working step by step numbered as Langkah 1, 2, 3. Write formula first, substitute values, show units. Point out common mistakes. End with: "Dah faham cara kerjanya? Sekarang awak pula cuba."',
    checkin:  'Give ONE calculation problem with slightly different numbers. Format: "Cuba kira: [problem]". No hints until they attempt.',
    reexplain:'Use a completely different real-world scenario. Break the formula into smaller pieces. "Kita buat langkah demi langkah ya."',
    refresher:'Mix recall questions ("Apakah formula untuk...?") with short calculations. Include one common-mistake trap question.',
  },
  'Additional Mathematics': {
    identity: 'You are teaching Additional Mathematics. Rigorous, proof-aware, SPM exam technique.',
    concept:  'State the theorem formally. Show brief derivation — Add Maths students need to know WHY. Connect to prior knowledge. End with: "Faham asal usul formula ni? Jom tengok contoh."',
    example:  'Full algebraic working. State which rule is applied at each step. For calculus: show limits and substitution clearly.',
    checkin:  'Problem must require 2-3 steps minimum. Include edge cases.',
    reexplain:'Go back to fundamentals. Use a simpler version to rebuild confidence.',
    refresher:'Past year SPM format. Mix short-answer and structured questions.',
  },
  Physics: {
    identity: 'You are teaching Physics. Your approach: PHENOMENON → CONCEPT → EQUATION → APPLICATION.',
    concept:  'Start with a real phenomenon students have experienced ("Awak pernah perasan tak kenapa...?"). Explain the principle. Introduce the equation AFTER the concept. State SI units. End with: "Jom kita tengok macam mana konsep ni digunakan."',
    example:  'State given (diberi) and find (cari) clearly. Write equation, rearrange, substitute. Check if answer is physically reasonable.',
    checkin:  'Mix one conceptual question ("Kenapa berlaku...?") with one calculation. Test both qualitative and quantitative understanding.',
    reexplain:'Use a different real-world context. Re-draw situation verbally.',
    refresher:'Mix definitions, diagram interpretation, and calculations. SPM-style part (a)(b)(c) format.',
  },
  Chemistry: {
    identity: 'You are teaching Chemistry. Your approach: PARTICLE-LEVEL → OBSERVABLE → EQUATION.',
    concept:  'Explain what happens at the particle/atomic level FIRST. Connect to observable changes (colour, gas, precipitate). Introduce balanced equations with state symbols. End with: "Faham apa yang berlaku pada aras zarah? Jom tengok contoh."',
    example:  'For calculations: always start with mole ratio from balanced equation. Show molar mass explicitly. For qualitative: observation → inference → conclusion format.',
    checkin:  'Mix equation balancing with particle-diagram questions. One mole-based problem.',
    reexplain:'Go back to particle level. Simplify the mole concept.',
    refresher:'Equation balancing, ionic equations, mole calculations. Observation/inference/conclusion format.',
  },
  Biology: {
    identity: 'You are teaching Biology. Your approach: STRUCTURE → FUNCTION → PROCESS → SIGNIFICANCE.',
    concept:  'Start with the biological structure. Explain its function and why it exists. Walk through the process step by step. Use mnemonics for sequences. End with: "Faham struktur dan fungsinya? Jom tengok proses dengan lebih terperinci."',
    example:  'For processes: numbered steps. For genetics: show Punnett square explicitly. Include key biological term definitions.',
    checkin:  'One process question + one diagram/labelling question. Include definition recall.',
    reexplain:'Use a body-system analogy. Break into even smaller steps.',
    refresher:'Diagram labelling, process sequencing, comparison tables. SPM essay format.',
  },
  Sejarah: {
    identity: 'You are teaching Sejarah. Your approach: CONTEXT → EVENT → CAUSE-EFFECT → SIGNIFICANCE.',
    concept:  'Set historical context first ("Pada masa ini..."). Introduce the key event. Explain causes clearly. Use storytelling tone. End with: "Faham latar belakangnya? Jom tengok kesan dan kepentingannya."',
    example:  'Model PEKA format: Point, Elaboration, Knowledge, Application. Show model paragraph with topic sentence, evidence, explanation.',
    checkin:  'One factual recall + one cause/effect question. "Berikan DUA sebab mengapa..."',
    reexplain:'Tell story from different angle. Use cause-effect chain.',
    refresher:'SPM structured: "Nyatakan...", "Jelaskan...", "Huraikan...". Essay planning with topic sentences.',
  },
  English: {
    identity: 'You are teaching English. Your approach: MODEL → ANALYSE → PRACTISE → REFINE.',
    concept:  'Introduce the grammar rule clearly. Give the RULE as a simple formula (e.g. Subject + has/have + V3). Show in context immediately. Point out common Malaysian English errors. End with: "Got the pattern? Let me show you how it works."',
    example:  'Show correct and incorrect versions side by side. For writing: model a full paragraph with annotations. Always explain WHY.',
    checkin:  'Fill-in-the-blank or error correction for grammar. Write ONE sentence for writing tasks.',
    reexplain:'Use a different sentence context. Break rule into simpler pattern. Address Manglish interference.',
    refresher:'SPM format: summary writing, directed writing, literature questions.',
  },
  'Bahasa Malaysia': {
    identity: 'Awak mengajar Bahasa Malaysia. Pendekatan: TATABAHASA → MODEL → LATIHAN → PENGAYAAN.',
    concept:  'Nyatakan konsep tatabahasa dengan jelas. Berikan hukum dalam format mudah diingati. Tunjukkan contoh dalam konteks. Asingkan kesilapan lazim. Akhiri dengan: "Dah faham peraturannya? Jom tengok contoh penulisan."',
    example:  'Untuk penulisan: perenggan model dengan anotasi. Untuk tatabahasa: ayat betul dan salah berdampingan. Format PEKA untuk karangan.',
    checkin:  'Isi tempat kosong ATAU betulkan ayat salah. Untuk penulisan: tulis SATU perenggan.',
    reexplain:'Gunakan konteks ayat berbeza. Pecahkan hukum kepada langkah lebih kecil.',
    refresher:'Format SPM: karangan, rumusan, komsas, tatabahasa.',
  },
};

function buildSystemPrompt(subject, phase, topic, subtopic, sessionType) {
  const p = PEDAGOGY[subject] || {
    identity: 'You are a warm SPM tutor.',
    concept: 'Introduce one concept at a time.',
    example: 'Walk through one example step by step.',
    checkin: 'Ask one check-in question.',
    reexplain: 'Re-explain using a different approach.',
    refresher: 'Mix recall and application questions.',
  };

  const phaseMap = {
    concept_intro:  p.concept,
    worked_example: p.example,
    check_in:       p.checkin,
    check_in_2:     p.checkin,
    re_explain:     p.reexplain,
    complete:       'Summarise what was covered. Highlight key points. Be warm and encouraging.',
  };

  const instruction = sessionType === 'refresher'
    ? `REFRESHER SESSION: Student already learned this topic. ${p.refresher} Ask 3-5 varied questions. Increase difficulty progressively. End with score and encouragement.`
    : (phaseMap[phase] || p.concept);

  return `${p.identity}

You are Nova, Learnova's AI tutor. You teach Malaysian SPM students with warmth and patience.
Your language: natural BM-English mix (how Malaysian teachers actually speak in class).
You NEVER rush. You NEVER move to the next concept until the student demonstrates understanding.

Subject: ${subject}
Topic: ${topic}${subtopic ? '\nSubtopic: ' + subtopic : ''}
Phase: ${phase}
Session type: ${sessionType}

PHASE INSTRUCTIONS:
${instruction}

ABSOLUTE RULES:
- ONE concept at a time. Never two.
- Never reveal answers before the student attempts.
- Always be warm. Kesilapan adalah sebahagian daripada pembelajaran.`;
}

// ── Helpers ───────────────────────────────────────────────────
async function getTopicProgress(studentId, subject, chapterNumber) {
  const { data } = await supabase
    .from('student_topic_progress')
    .select('*')
    .eq('student_id', studentId)
    .eq('subject', subject)
    .eq('chapter_number', chapterNumber)
    .maybeSingle();
  return data;
}

async function getTodayLog(studentId) {
  const today = new Date().toISOString().split('T')[0];
  const { data } = await supabase
    .from('daily_session_log')
    .select('*')
    .eq('student_id', studentId)
    .eq('session_date', today)
    .maybeSingle();
  return data;
}

async function upsertDailyLog(studentId, updates) {
  const today = new Date().toISOString().split('T')[0];
  const existing = await getTodayLog(studentId);
  if (!existing) {
    await supabase.from('daily_session_log').insert({
      student_id:          studentId,
      session_date:        today,
      new_topic_learned:   updates.new_topic || null,
      new_chapter_number:  updates.new_chapter || null,
      session_count:       1,
      new_topic_limit_hit: updates.new_topic ? true : false,
    });
  } else {
    const patch = { session_count: existing.session_count + 1 };
    if (updates.new_topic) { patch.new_topic_learned = updates.new_topic; patch.new_topic_limit_hit = true; }
    await supabase.from('daily_session_log').update(patch).eq('id', existing.id);
  }
}

async function unlockNextTopic(studentId, subject, currentChapter) {
  const nextChapter = currentChapter + 1;
  const { data: nextLesson } = await supabase
    .from('lessons')
    .select('chapter_number, topic')
    .eq('subject', subject)
    .eq('chapter_number', nextChapter)
    .maybeSingle();
  if (!nextLesson) return false;
  const existing = await getTopicProgress(studentId, subject, nextChapter);
  if (existing) return false;
  await supabase.from('student_topic_progress').insert({
    student_id: studentId, subject,
    chapter_number: nextChapter, topic: nextLesson.topic,
    status: STATUS.AVAILABLE, unlocked_at: new Date().toISOString(),
  });
  return true;
}

// ── Routes ────────────────────────────────────────────────────

// GET /api/learn/topics/:studentId/:subject
router.get('/topics/:studentId/:subject', async (req, res) => {
  try {
    const { studentId, subject } = req.params;

    // Seed first topic if needed
    const { data: firstLesson } = await supabase
      .from('lessons').select('chapter_number, topic')
      .eq('subject', subject).eq('curriculum', 'SPM')
      .order('chapter_number', { ascending: true }).limit(1).maybeSingle();

    if (firstLesson) {
      const existing = await getTopicProgress(studentId, subject, firstLesson.chapter_number);
      if (!existing) {
        await supabase.from('student_topic_progress').insert({
          student_id: studentId, subject,
          chapter_number: firstLesson.chapter_number, topic: firstLesson.topic,
          status: STATUS.AVAILABLE, unlocked_at: new Date().toISOString(),
        });
      }
    }

    const { data: lessons } = await supabase
      .from('lessons').select('chapter_number, topic, title')
      .eq('subject', subject).eq('curriculum', 'SPM')
      .order('chapter_number', { ascending: true });

    const { data: progress } = await supabase
      .from('student_topic_progress').select('*')
      .eq('student_id', studentId).eq('subject', subject);

    const progressMap = {};
    (progress || []).forEach(p => { progressMap[p.chapter_number] = p; });

    const topics = (lessons || []).map((lesson, idx) => {
      const p = progressMap[lesson.chapter_number];
      let status = STATUS.LOCKED;
      if (p) { status = p.status; }
      else if (idx === 0) { status = STATUS.AVAILABLE; }
      else {
        const prev = progressMap[(lessons[idx-1] || {}).chapter_number];
        if (prev && [STATUS.REFRESHER, STATUS.MASTERED].includes(prev.status)) status = STATUS.AVAILABLE;
      }
      return { chapter_number: lesson.chapter_number, topic: lesson.topic, title: lesson.title, status, progress: p || null };
    });

    const todayLog = await getTodayLog(studentId);
    const sessionsDone = todayLog?.session_count || 0;
    const canStudy = sessionsDone < CONFIG.MAX_SESSIONS_PER_DAY;

    return res.json({
      topics,
      sessions_today:     sessionsDone,
      sessions_remaining: Math.max(0, CONFIG.MAX_SESSIONS_PER_DAY - sessionsDone),
      can_study_today:    canStudy,
      daily_message:      canStudy ? null : `Awak dah buat ${sessionsDone} sesi hari ini — hebat! Rehat dulu dan kembali esok. Konsisten setiap hari lebih berkesan.`,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /api/learn/session/start
router.post('/session/start', async (req, res) => {
  try {
    const { student_id, subject, chapter_number, topic } = req.body;
    const today = new Date().toISOString().split('T')[0];

    // Check daily session limit
    const todayLog = await getTodayLog(student_id);
    const sessionsDone = todayLog?.session_count || 0;
    if (sessionsDone >= CONFIG.MAX_SESSIONS_PER_DAY) {
      return res.status(403).json({
        allowed: false,
        reason: `Awak dah buat ${sessionsDone} sesi hari ini — hebat! Rehat dulu dan kembali esok. Konsisten setiap hari lebih berkesan daripada belajar terlalu lama sekaligus.`,
        come_back_tomorrow: true,
      });
    }

    let progress = await getTopicProgress(student_id, subject, chapter_number);

    if (!progress) {
      // Check if locked
      const { data: lessons } = await supabase
        .from('lessons').select('chapter_number')
        .eq('subject', subject).eq('curriculum', 'SPM')
        .order('chapter_number', { ascending: true });

      const idx = (lessons || []).findIndex(l => l.chapter_number === chapter_number);
      if (idx > 0) {
        const prevChapter = lessons[idx-1].chapter_number;
        const prevProgress = await getTopicProgress(student_id, subject, prevChapter);
        if (!prevProgress || ![STATUS.REFRESHER, STATUS.MASTERED].includes(prevProgress.status)) {
          return res.status(403).json({
            allowed: false,
            reason: 'Topik ini masih terkunci. Selesaikan topik sebelumnya dan buat sesi ulang kaji untuk membuka topik ini.',
            locked: true,
          });
        }
      }

      // Check new topic daily limit
      if (todayLog?.new_topic_limit_hit) {
        return res.status(403).json({
          allowed: false,
          reason: 'Awak dah mulakan topik baru hari ini! Cuba esok ya. Hari ini boleh buat sesi ulang kaji topik yang dah belajar.',
          come_back_tomorrow: true,
        });
      }

      // Create progress
      const { data: newP } = await supabase.from('student_topic_progress').insert({
        student_id, subject, chapter_number, topic,
        status: STATUS.IN_PROGRESS, sessions_on_topic: 1,
        first_session_date: today, last_session_date: today,
        unlocked_at: new Date().toISOString(),
      }).select().single();
      progress = newP;
      await upsertDailyLog(student_id, { new_topic: topic, new_chapter: chapter_number });
    } else {
      if (progress.status === STATUS.LOCKED) {
        return res.status(403).json({ allowed: false, reason: 'Topik ini masih terkunci.', locked: true });
      }
      await supabase.from('student_topic_progress').update({
        sessions_on_topic: (progress.sessions_on_topic || 0) + 1,
        last_session_date: today,
        status: progress.status === STATUS.AVAILABLE ? STATUS.IN_PROGRESS : progress.status,
      }).eq('id', progress.id);
      await upsertDailyLog(student_id, {});
    }

    const { data: session } = await supabase.from('session_logs').insert({
      student_id, subject, topic, started_at: new Date().toISOString(),
    }).select().single();

    const sessionType = [STATUS.REFRESHER, STATUS.MASTERED].includes(progress.status) ? 'refresher' : 'learning';

    return res.json({
      allowed: true,
      session_id: session?.id,
      session_type: sessionType,
      status: progress.status,
      sessions_remaining: CONFIG.MAX_SESSIONS_PER_DAY - (sessionsDone + 1),
      message: sessionType === 'refresher' ? `Selamat datang semula! Hari ini kita buat sesi ulang kaji untuk topik ${topic}.` : null,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /api/learn/chat
router.post('/chat', async (req, res) => {
  try {
    const {
      session_id, student_id, subject, topic, subtopic,
      chapter_number, message, session_type = 'learning',
      current_phase = 'concept_intro', request_advance = false,
      conversation = [],
    } = req.body;

    // Get or create phase state
    let { data: phaseState } = await supabase
      .from('session_phases').select('*').eq('session_id', session_id).maybeSingle();

    if (!phaseState) {
      const { data: newState } = await supabase.from('session_phases').insert({
        session_id, student_id, subject, topic,
        subtopic: subtopic || null,
        current_phase: 'concept_intro',
        concepts_taught: 0, checkin_attempts: 0, conversation: [],
      }).select().single();
      phaseState = newState;
    }

    if (request_advance) {
      const advanceMap = { concept_intro: 'worked_example', worked_example: 'check_in' };
      const next = advanceMap[phaseState.current_phase];
      if (next) {
        await supabase.from('session_phases').update({ current_phase: next }).eq('id', phaseState.id);
        phaseState.current_phase = next;
      }
    }

    const convo = phaseState.conversation || [];
    convo.push({ role: 'user', content: message, phase: phaseState.current_phase });

    const systemPrompt = buildSystemPrompt(subject, phaseState.current_phase, topic, subtopic, session_type);
    const claudeMessages = convo.map(m => ({ role: m.role, content: m.content }));

    const response = await claude.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 700,
      system: systemPrompt,
      messages: claudeMessages,
    });

    const reply = response.content[0].text;
    const replyLower = reply.toLowerCase();
    let newPhase = phaseState.current_phase;

    if (phaseState.current_phase === 'concept_intro' &&
      ['jom saya tunjukkan', 'jom tengok contoh', 'let me show you'].some(s => replyLower.includes(s))) {
      newPhase = 'worked_example';
    } else if (phaseState.current_phase === 'worked_example' &&
      ['sekarang awak pula cuba', 'cuba kira', 'now you try', 'cuba awak'].some(s => replyLower.includes(s))) {
      newPhase = 'check_in';
    }

    if (newPhase !== phaseState.current_phase) {
      await supabase.from('session_phases').update({ current_phase: newPhase }).eq('id', phaseState.id);
    }

    convo.push({ role: 'assistant', content: reply, phase: newPhase });
    await supabase.from('session_phases').update({ conversation: convo }).eq('id', phaseState.id);

    return res.json({
      reply, phase: newPhase, session_type,
      show_advance_button: ['concept_intro', 'worked_example'].includes(newPhase),
      show_quiz_button: newPhase === 'complete',
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// POST /api/learn/quiz/submit
router.post('/quiz/submit', async (req, res) => {
  try {
    const { student_id, subject, chapter_number, topic, score, questions_total, questions_correct } = req.body;
    const today = new Date().toISOString().split('T')[0];
    const progress = await getTopicProgress(student_id, subject, chapter_number);
    if (!progress) return res.status(404).json({ error: 'No progress record found' });

    const passed = score >= CONFIG.QUIZ_PASS_THRESHOLD;
    let newStatus = progress.status;
    let message = '';
    let nextTopicUnlocked = false;

    await supabase.from('topic_quiz_results').insert({
      student_id, subject, chapter_number, topic,
      session_type: progress.status === STATUS.REFRESHER ? 'refresher' : 'learning',
      score, questions_total, questions_correct,
    }).catch(() => {});

    if (passed && progress.status === STATUS.IN_PROGRESS) {
      newStatus = STATUS.REFRESHER;
      message = `Tahniah! Awak dah lulus kuiz dengan ${score}%! Sesi seterusnya akan jadi ulang kaji untuk kukuhkan pemahaman awak.`;
      nextTopicUnlocked = await unlockNextTopic(student_id, subject, chapter_number);
      await supabase.from('student_topic_progress').update({
        status: newStatus, passed_quiz: true,
        best_quiz_score: Math.max(progress.best_quiz_score || 0, score),
        last_quiz_score: score, quiz_attempts: (progress.quiz_attempts || 0) + 1,
        completed_at: new Date().toISOString(),
      }).eq('id', progress.id);

    } else if (progress.status === STATUS.REFRESHER) {
      const refresherDays = progress.refresher_days || [];
      if (!refresherDays.includes(today)) refresherDays.push(today);
      const done = (progress.refresher_sessions_done || 0) + 1;
      const isComplete = refresherDays.length >= CONFIG.REFRESHER_SESSIONS_NEEDED;
      newStatus = isComplete ? STATUS.MASTERED : STATUS.REFRESHER;
      message = isComplete
        ? `Luar biasa! Awak telah menguasai topik ${topic} sepenuhnya! ⭐`
        : `Sesi ulang kaji ${refresherDays.length}/${CONFIG.REFRESHER_SESSIONS_NEEDED} selesai. Kembali lagi ${CONFIG.REFRESHER_SESSIONS_NEEDED - refresherDays.length} hari lagi!`;
      await supabase.from('student_topic_progress').update({
        status: newStatus, refresher_sessions_done: done,
        refresher_days: refresherDays, refresher_complete: isComplete,
        best_quiz_score: Math.max(progress.best_quiz_score || 0, score),
        last_quiz_score: score, quiz_attempts: (progress.quiz_attempts || 0) + 1,
        mastered_at: isComplete ? new Date().toISOString() : null,
      }).eq('id', progress.id);

    } else if (!passed) {
      message = `Awak dapat ${score}%. Perlu ${CONFIG.QUIZ_PASS_THRESHOLD}% untuk teruskan. Jangan risau — kita ulang semula konsep yang susah ya.`;
      await supabase.from('student_topic_progress').update({
        best_quiz_score: Math.max(progress.best_quiz_score || 0, score),
        last_quiz_score: score, quiz_attempts: (progress.quiz_attempts || 0) + 1,
      }).eq('id', progress.id);
    }

    return res.json({ passed, score, new_status: newStatus, message, next_topic_unlocked: nextTopicUnlocked });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /api/learn/revision/:studentId/:subject
router.get('/revision/:studentId/:subject', async (req, res) => {
  try {
    const { data } = await supabase
      .from('student_topic_progress').select('*')
      .eq('student_id', req.params.studentId)
      .eq('subject', req.params.subject)
      .in('status', [STATUS.IN_PROGRESS, STATUS.REFRESHER, STATUS.MASTERED])
      .order('chapter_number', { ascending: true });
    return res.json({ revision_topics: data || [] });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /api/learn/dashboard/:studentId
router.get('/dashboard/:studentId', async (req, res) => {
  try {
    const { studentId } = req.params;
    const todayLog = await getTodayLog(studentId);
    const sessionsDone = todayLog?.session_count || 0;
    const canStudy = sessionsDone < CONFIG.MAX_SESSIONS_PER_DAY;
    const today = new Date().toISOString().split('T')[0];

    const { data: activeTopics } = await supabase
      .from('student_topic_progress').select('*')
      .eq('student_id', studentId)
      .in('status', [STATUS.IN_PROGRESS, STATUS.REFRESHER])
      .order('last_session_date', { ascending: false });

    const refresherDue = (activeTopics || []).filter(t =>
      t.status === STATUS.REFRESHER && (!t.last_session_date || t.last_session_date < today)
    );

    const { data: availableTopics } = await supabase
      .from('student_topic_progress').select('*')
      .eq('student_id', studentId).eq('status', STATUS.AVAILABLE);

    let recommendation = null;
    if (canStudy) {
      if (refresherDue.length) {
        recommendation = { type: 'refresher', topic: refresherDue[0].topic, subject: refresherDue[0].subject, message: `Jom buat sesi ulang kaji untuk "${refresherDue[0].topic}" hari ini!` };
      } else if ((activeTopics || []).find(t => t.status === STATUS.IN_PROGRESS)) {
        const t = activeTopics.find(t => t.status === STATUS.IN_PROGRESS);
        recommendation = { type: 'continue', topic: t.topic, subject: t.subject, message: `Sambung belajar "${t.topic}".` };
      } else if (availableTopics?.length) {
        recommendation = { type: 'new_topic', topic: availableTopics[0].topic, subject: availableTopics[0].subject, message: `Awak bersedia untuk topik baru: "${availableTopics[0].topic}"!` };
      }
    }

    return res.json({
      can_study_today: canStudy,
      sessions_remaining: Math.max(0, CONFIG.MAX_SESSIONS_PER_DAY - sessionsDone),
      daily_message: canStudy ? null : `Awak dah buat ${sessionsDone} sesi hari ini. Kembali esok!`,
      refresher_due: refresherDue,
      active_topics: (activeTopics || []).filter(t => t.status === STATUS.IN_PROGRESS),
      available_topics: availableTopics || [],
      recommendation,
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

export default router;
