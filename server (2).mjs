import express from 'express';
import { createClient } from '@supabase/supabase-js';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';

const app = express();
const supabaseUrl = 'https://nxvbpanozswheackgwni.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54dmJwYW5venN3aGVhY2tnd25pIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQxNTA3NCwiZXhwIjoyMDkwOTkxMDc0fQ.0MvWb7_gBfDQQOlcpmX4brBRk6YbOOVOInyvpJL1a7A';
const supabase = createClient(supabaseUrl, supabaseKey);
const jwtSecret = 'dev-secret-change-in-production';

app.use(express.json());

// ==================== MIDDLEWARE ====================

const verifyToken = (req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'No token' });
  try {
    req.user = jwt.verify(token, jwtSecret);
    next();
  } catch {
    res.status(401).json({ error: 'Invalid token' });
  }
};

// ==================== STUDENT ENDPOINTS ====================

app.post('/api/student/signup', async (req, res) => {
  try {
    const { email, password, name, parent_email } = req.body;
    const hashedPassword = await bcrypt.hash(password, 10);
    const parent_link_token = Math.random().toString(36).substring(2, 15);
    
    const { data, error } = await supabase
      .from('students')
      .insert([{ email, password_hash: hashedPassword, name, parent_email, parent_link_token }])
      .select();
    
    if (error) return res.status(400).json({ error: error.message });
    
    const token = jwt.sign({ student_id: data[0].id, email }, jwtSecret, { expiresIn: '30d' });
    res.json({ token, student_id: data[0].id, parent_link_token: data[0].parent_link_token });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/student/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    
    const { data, error } = await supabase
      .from('students')
      .select('*')
      .eq('email', email)
      .single();
    
    if (error || !data) return res.status(401).json({ error: 'Invalid credentials' });
    
    const validPassword = await bcrypt.compare(password, data.password_hash);
    if (!validPassword) return res.status(401).json({ error: 'Invalid credentials' });
    
    const token = jwt.sign({ student_id: data.id, email }, jwtSecret, { expiresIn: '30d' });
    res.json({ token, student_id: data.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ==================== PARENT ENDPOINTS ====================

app.post('/api/parent/signup', async (req, res) => {
  try {
    const { email, parent_link_token } = req.body;
    
    const { data: studentData } = await supabase
      .from('students')
      .select('id')
      .eq('parent_link_token', parent_link_token)
      .single();
    
    if (!studentData) return res.status(400).json({ error: 'Invalid QR token' });
    
    const { data, error } = await supabase
      .from('parents')
      .insert([{ email, student_id: studentData.id }])
      .select();
    
    if (error) return res.status(400).json({ error: error.message });
    
    const token = jwt.sign({ parent_id: data[0].id, email }, jwtSecret, { expiresIn: '30d' });
    res.json({ token, parent_id: data[0].id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/parent/login', async (req, res) => {
  try {
    const { email } = req.body;
    
    const { data } = await supabase
      .from('parents')
      .select('id')
      .eq('email', email)
      .single();
    
    if (!data) return res.status(401).json({ error: 'Parent not found' });
    
    const magicToken = jwt.sign({ parent_id: data.id, email }, jwtSecret, { expiresIn: '1h' });
    res.json({ magicToken });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ==================== PARENT DASHBOARD ENDPOINTS ====================

app.get('/api/parent/child-info', verifyToken, async (req, res) => {
  try {
    const { data: parentData } = await supabase
      .from('parents')
      .select('student_id')
      .eq('id', req.user.parent_id)
      .single();
    
    const { data: studentData } = await supabase
      .from('students')
      .select('id, name, email')
      .eq('id', parentData.student_id)
      .single();
    
    res.json(studentData);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/parent/quiz-results', verifyToken, async (req, res) => {
  try {
    const { data: parentData } = await supabase
      .from('parents')
      .select('student_id')
      .eq('id', req.user.parent_id)
      .single();
    
    const { data } = await supabase
      .from('quiz_results')
      .select('*')
      .eq('student_id', parentData.student_id)
      .order('created_at', { ascending: false });
    
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/parent/study-time', verifyToken, async (req, res) => {
  try {
    const { data: parentData } = await supabase
      .from('parents')
      .select('student_id')
      .eq('id', req.user.parent_id)
      .single();
    
    const { data } = await supabase
      .from('study_sessions')
      .select('topic, duration_minutes')
      .eq('student_id', parentData.student_id);
    
    const topicTime = {};
    (data || []).forEach(session => {
      topicTime[session.topic] = (topicTime[session.topic] || 0) + session.duration_minutes;
    });
    
    res.json(topicTime);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/parent/analytics', verifyToken, async (req, res) => {
  try {
    const { data: parentData } = await supabase
      .from('parents')
      .select('student_id')
      .eq('id', req.user.parent_id)
      .single();
    
    const { data: quizzes } = await supabase
      .from('quiz_results')
      .select('score, topic')
      .eq('student_id', parentData.student_id);
    
    const { data: sessions } = await supabase
      .from('study_sessions')
      .select('topic, duration_minutes')
      .eq('student_id', parentData.student_id);
    
    const avgScore = quizzes?.length ? (quizzes.reduce((sum, q) => sum + q.score, 0) / quizzes.length).toFixed(1) : 0;
    const totalStudyTime = sessions?.reduce((sum, s) => sum + s.duration_minutes, 0) || 0;
    
    const topicStats = {};
    quizzes?.forEach(q => {
      if (!topicStats[q.topic]) topicStats[q.topic] = [];
      topicStats[q.topic].push(q.score);
    });
    
    const topicAvg = Object.entries(topicStats).map(([topic, scores]) => ({
      topic,
      avgScore: (scores.reduce((a, b) => a + b) / scores.length).toFixed(1)
    }));
    
    const strengths = topicAvg.sort((a, b) => b.avgScore - a.avgScore).slice(0, 3).map(t => t.topic);
    const weaknesses = topicAvg.sort((a, b) => a.avgScore - b.avgScore).slice(0, 3).map(t => t.topic);
    
    res.json({ avgScore, totalStudyTime, strengths, weaknesses, quizCount: quizzes?.length || 0 });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ==================== QUIZ ENDPOINTS ====================

app.get('/api/quiz/list/:subject', verifyToken, async (req, res) => {
  try {
    const { data } = await supabase
      .from('quizzes')
      .select('id, title, topic, question_count');
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/quiz/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    const { data } = await supabase
      .from('quizzes')
      .select('*')
      .eq('id', id)
      .single();
    
    if (!data) return res.status(404).json({ error: 'Quiz not found' });
    
    const { data: questions } = await supabase
      .from('quiz_questions')
      .select('*')
      .eq('quiz_id', id);
    
    res.json({ ...data, questions });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/quiz/submit', verifyToken, async (req, res) => {
  try {
    const { quiz_id, answers, workings } = req.body;
    const student_id = req.user.student_id;
    
    const { data: quiz } = await supabase.from('quizzes').select('*').eq('id', quiz_id).single();
    const { data: questions } = await supabase.from('quiz_questions').select('*').eq('quiz_id', quiz_id);
    
    let score = 0;
    questions.forEach((q, idx) => {
      const answer = answers[idx];
      if (q.type === 'multiple_choice' && answer === q.correct_answer) {
        score += (100 / questions.length);
      } else if (q.type === 'short_answer' && answer?.toLowerCase().trim() === q.correct_answer.toLowerCase().trim()) {
        score += (100 / questions.length);
      }
    });
    
    const { data: result } = await supabase
      .from('quiz_results')
      .insert([{
        student_id,
        quiz_id,
        score: Math.round(score),
        answers: JSON.stringify(answers),
        workings: JSON.stringify(workings),
        topic: quiz.topic
      }])
      .select();
    
    res.json({ 
      score: Math.round(score), 
      result_id: result[0].id,
      passed: Math.round(score) >= 70
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/quiz/result/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    const { data } = await supabase
      .from('quiz_results')
      .select('*')
      .eq('id', id)
      .single();
    
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ==================== SPONSORSHIP ENDPOINTS ====================

app.post('/api/sponsorship/create', verifyToken, async (req, res) => {
  try {
    const { spots_count, price } = req.body;
    const parent_id = req.user.parent_id;
    
    const codes = Array(spots_count).fill(null).map(() => 
      `LEARNOVA-${uuidv4().substring(0, 8).toUpperCase()}`
    );
    
    const { data: sponsorship } = await supabase
      .from('sponsorships')
      .insert([{
        parent_id,
        spots_count,
        price,
        codes,
        status: 'active'
      }])
      .select();
    
    res.json({ 
      sponsorship_id: sponsorship[0].id,
      codes,
      message: `${spots_count} sponsorship codes generated!`
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/sponsorship/redeem', async (req, res) => {
  try {
    const { code, student_email } = req.body;
    
    const { data: redemption } = await supabase
      .from('redemption_codes')
      .select('*')
      .eq('code', code)
      .eq('status', 'active')
      .single();
    
    if (!redemption) return res.status(400).json({ error: 'Invalid or expired code' });
    
    const { data: student } = await supabase
      .from('students')
      .select('id')
      .eq('email', student_email)
      .single();
    
    if (!student) return res.status(400).json({ error: 'Student not found' });
    
    await supabase
      .from('redemption_codes')
      .update({
        status: 'redeemed',
        redeemed_by_student: student.id,
        redeemed_at: new Date()
      })
      .eq('code', code);
    
    const { data: sponsorship } = await supabase
      .from('sponsorships')
      .select('redeemed_count, spots_count')
      .eq('id', redemption.sponsorship_id)
      .single();
    
    const newRedeemCount = (sponsorship.redeemed_count || 0) + 1;
    const isFull = newRedeemCount >= sponsorship.spots_count;
    
    await supabase
      .from('sponsorships')
      .update({
        redeemed_count: newRedeemCount,
        status: isFull ? 'closed' : 'active'
      })
      .eq('id', redemption.sponsorship_id);
    
    res.json({ 
      success: true, 
      message: 'Code redeemed! Full access granted.',
      sponsorship_closed: isFull
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/sponsorship/list', verifyToken, async (req, res) => {
  try {
    const parent_id = req.user.parent_id;
    
    const { data } = await supabase
      .from('sponsorships')
      .select('*')
      .eq('parent_id', parent_id)
      .order('created_at', { ascending: false });
    
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/sponsorship/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    const { data } = await supabase
      .from('sponsorships')
      .select('*')
      .eq('id', id)
      .single();
    
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ==================== TEACHER ENDPOINTS ====================

app.post('/api/teacher/signup', async (req, res) => {
  try {
    const { email, password, name, subject, experience } = req.body;
    const hashedPassword = await bcrypt.hash(password, 10);
    
    const { data, error } = await supabase
      .from('teachers')
      .insert([{
        email,
        password_hash: hashedPassword,
        name,
        subject,
        experience_years: experience,
        equity_percentage: 0
      }])
      .select();
    
    if (error) return res.status(400).json({ error: error.message });
    
    const token = jwt.sign({ teacher_id: data[0].id, email }, jwtSecret, { expiresIn: '30d' });
    res.json({ token, teacher_id: data[0].id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/teacher/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    
    const { data, error } = await supabase
      .from('teachers')
      .select('*')
      .eq('email', email)
      .single();
    
    if (error || !data) return res.status(401).json({ error: 'Invalid credentials' });
    
    const validPassword = await bcrypt.compare(password, data.password_hash);
    if (!validPassword) return res.status(401).json({ error: 'Invalid credentials' });
    
    const token = jwt.sign({ teacher_id: data.id, email }, jwtSecret, { expiresIn: '30d' });
    res.json({ token, teacher_id: data.id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/teacher/lessons', verifyToken, async (req, res) => {
  try {
    const { title, topic, subject, content, form_level } = req.body;
    const teacher_id = req.user.teacher_id;
    
    const { data, error } = await supabase
      .from('lessons')
      .insert([{
        teacher_id,
        title,
        topic,
        subject,
        content,
        form_level,
        status: 'published'
      }])
      .select();
    
    if (error) return res.status(400).json({ error: error.message });
    
    res.json({ lesson_id: data[0].id, message: 'Lesson created successfully' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/teacher/lessons', verifyToken, async (req, res) => {
  try {
    const teacher_id = req.user.teacher_id;
    
    const { data, error } = await supabase
      .from('lessons')
      .select('*')
      .eq('teacher_id', teacher_id)
      .order('created_at', { ascending: false });
    
    if (error) return res.status(400).json({ error: error.message });
    
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.put('/api/teacher/lessons/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    const { title, content, topic } = req.body;
    
    const { data, error } = await supabase
      .from('lessons')
      .update({ title, content, topic })
      .eq('id', id)
      .select();
    
    if (error) return res.status(400).json({ error: error.message });
    
    res.json({ message: 'Lesson updated', lesson: data[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/api/teacher/lessons/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    const { error } = await supabase
      .from('lessons')
      .delete()
      .eq('id', id);
    
    if (error) return res.status(400).json({ error: error.message });
    
    res.json({ message: 'Lesson deleted' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/teacher/quizzes', verifyToken, async (req, res) => {
  try {
    const { title, topic, subject, form_level, questions } = req.body;
    const teacher_id = req.user.teacher_id;
    
    const { data: quizData, error: quizError } = await supabase
      .from('quizzes')
      .insert([{
        title,
        topic,
        subject,
        form_level,
        question_count: questions.length,
        teacher_id,
        difficulty: 'Medium'
      }])
      .select();
    
    if (quizError) return res.status(400).json({ error: quizError.message });
    
    const quiz_id = quizData[0].id;
    
    const questionRows = questions.map(q => ({
      quiz_id,
      question: q.question,
      type: q.type,
      options: q.options ? JSON.stringify(q.options) : null,
      correct_answer: q.correct_answer,
      explanation: q.explanation || ''
    }));
    
    const { error: questionsError } = await supabase
      .from('quiz_questions')
      .insert(questionRows);
    
    if (questionsError) return res.status(400).json({ error: questionsError.message });
    
    res.json({ quiz_id, message: 'Quiz created with all questions' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/teacher/quizzes', verifyToken, async (req, res) => {
  try {
    const teacher_id = req.user.teacher_id;
    
    const { data, error } = await supabase
      .from('quizzes')
      .select('*')
      .eq('teacher_id', teacher_id)
      .order('created_at', { ascending: false });
    
    if (error) return res.status(400).json({ error: error.message });
    
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/teacher/analytics', verifyToken, async (req, res) => {
  try {
    const teacher_id = req.user.teacher_id;
    
    const { data: quizzes } = await supabase
      .from('quizzes')
      .select('id')
      .eq('teacher_id', teacher_id);
    
    const quiz_ids = quizzes?.map(q => q.id) || [];
    
    if (quiz_ids.length === 0) {
      return res.json({
        total_students: 0,
        total_quizzes_taken: 0,
        avg_score: 0,
        top_topics: [],
        student_progress: []
      });
    }
    
    const { data: results } = await supabase
      .from('quiz_results')
      .select('*')
      .in('quiz_id', quiz_ids);
    
    const uniqueStudents = new Set(results?.map(r => r.student_id) || []).size;
    const avgScore = results?.length 
      ? (results.reduce((sum, r) => sum + r.score, 0) / results.length).toFixed(1)
      : 0;
    
    const topicStats = {};
    results?.forEach(r => {
      if (!topicStats[r.topic]) topicStats[r.topic] = [];
      topicStats[r.topic].push(r.score);
    });
    
    const topTopics = Object.entries(topicStats)
      .map(([topic, scores]) => ({
        topic,
        avg_score: (scores.reduce((a, b) => a + b) / scores.length).toFixed(1),
        attempts: scores.length
      }))
      .sort((a, b) => b.avg_score - a.avg_score)
      .slice(0, 5);
    
    res.json({
      total_students: uniqueStudents,
      total_quizzes_taken: results?.length || 0,
      avg_score: avgScore,
      top_topics: topTopics,
      student_progress: results?.slice(-10) || []
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/teacher/profile', verifyToken, async (req, res) => {
  try {
    const teacher_id = req.user.teacher_id;
    
    const { data, error } = await supabase
      .from('teachers')
      .select('id, name, email, subject, experience_years, equity_percentage, created_at')
      .eq('id', teacher_id)
      .single();
    
    if (error) return res.status(400).json({ error: error.message });
    
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.put('/api/teacher/profile', verifyToken, async (req, res) => {
  try {
    const teacher_id = req.user.teacher_id;
    const { name, subject, experience_years } = req.body;
    
    const { data, error } = await supabase
      .from('teachers')
      .update({ name, subject, experience_years })
      .eq('id', teacher_id)
      .select();
    
    if (error) return res.status(400).json({ error: error.message });
    
    res.json({ message: 'Profile updated', teacher: data[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/teacher/equity', verifyToken, async (req, res) => {
  try {
    const teacher_id = req.user.teacher_id;
    
    const { data: teacher } = await supabase
      .from('teachers')
      .select('equity_percentage, created_at')
      .eq('id', teacher_id)
      .single();
    
    const { data: lessons } = await supabase
      .from('lessons')
      .select('id')
      .eq('teacher_id', teacher_id);
    
    const { data: quizzes } = await supabase
      .from('quizzes')
      .select('id')
      .eq('teacher_id', teacher_id);
    
    res.json({
      equity_percentage: teacher?.equity_percentage || 0,
      lessons_contributed: lessons?.length || 0,
      quizzes_created: quizzes?.length || 0,
      joined_date: teacher?.created_at
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ==================== HEALTH CHECK ====================

app.get('/health', (req, res) => {
  res.json({ 
    status: 'Learnova Backend Running!',
    endpoints: {
      student: ['signup', 'login'],
      parent: ['signup', 'login', 'child-info', 'analytics', 'quiz-results', 'study-time'],
      quiz: ['list', 'get', 'submit', 'result'],
      sponsorship: ['create', 'redeem', 'list', 'details'],
      teacher: ['signup', 'login', 'lessons', 'quizzes', 'analytics', 'profile', 'equity']
    }
  });
});

// ==================== START SERVER ====================

app.listen(3000, () => {
  console.log('✅ LEARNOVA COMPLETE BACKEND RUNNING');
  console.log('📍 http://localhost:3000');
  console.log('🏥 Health: http://localhost:3000/health');
  console.log('🎓 Students, Parents, Teachers, Quizzes, Sponsorships - ALL READY!');
});
