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

// STUDENT AUTH
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
    res.json({ token, student_id: data[0].id });
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

// PARENT AUTH
app.post('/api/parent/signup', async (req, res) => {
  try {
    const { email, parent_link_token } = req.body;
    
    const { data: studentData } = await supabase
      .from('students')
      .select('id')
      .eq('parent_link_token', parent_link_token)
      .single();
    
    if (!studentData) return res.status(400).json({ error: 'Invalid token' });
    
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
    
    if (!data) return res.status(401).json({ error: 'Not found' });
    
    const token = jwt.sign({ parent_id: data.id, email }, jwtSecret, { expiresIn: '30d' });
    res.json({ token });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PARENT DASHBOARD
app.get('/api/parent/child-info', verifyToken, async (req, res) => {
  try {
    const { data: parent } = await supabase
      .from('parents')
      .select('student_id')
      .eq('id', req.user.parent_id)
      .single();
    
    const { data: student } = await supabase
      .from('students')
      .select('*')
      .eq('id', parent.student_id)
      .single();
    
    res.json(student);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/parent/quiz-results', verifyToken, async (req, res) => {
  try {
    const { data: parent } = await supabase
      .from('parents')
      .select('student_id')
      .eq('id', req.user.parent_id)
      .single();
    
    const { data } = await supabase
      .from('quiz_results')
      .select('*')
      .eq('student_id', parent.student_id);
    
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/parent/study-time', verifyToken, async (req, res) => {
  try {
    const { data: parent } = await supabase
      .from('parents')
      .select('student_id')
      .eq('id', req.user.parent_id)
      .single();
    
    const { data } = await supabase
      .from('study_sessions')
      .select('*')
      .eq('student_id', parent.student_id);
    
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/parent/analytics', verifyToken, async (req, res) => {
  try {
    const { data: parent } = await supabase
      .from('parents')
      .select('student_id')
      .eq('id', req.user.parent_id)
      .single();
    
    const { data: results } = await supabase
      .from('quiz_results')
      .select('*')
      .eq('student_id', parent.student_id);
    
    const avgScore = results?.length ? (results.reduce((sum, r) => sum + r.score, 0) / results.length).toFixed(1) : 0;
    
    res.json({ avgScore, quizCount: results?.length || 0 });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// QUIZ ENDPOINTS
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
    const { data: quiz } = await supabase
      .from('quizzes')
      .select('*')
      .eq('id', id)
      .single();
    
    const { data: questions } = await supabase
      .from('quiz_questions')
      .select('*')
      .eq('quiz_id', id);
    
    res.json({ ...quiz, questions });
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
      if (answers[idx] === q.correct_answer) score += (100 / questions.length);
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
    
    res.json({ score: Math.round(score), result_id: result[0].id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/quiz/result/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    const { data } = await supabase.from('quiz_results').select('*').eq('id', id).single();
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// SPONSORSHIP
app.post('/api/sponsorship/create', verifyToken, async (req, res) => {
  try {
    const { spots_count, price } = req.body;
    const parent_id = req.user.parent_id;
    
    const { data } = await supabase
      .from('sponsorships')
      .insert([{ parent_id, spots_count, price, status: 'active' }])
      .select();
    
    res.json({ sponsorship_id: data[0].id, message: 'Sponsorship created' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/sponsorship/redeem', async (req, res) => {
  try {
    const { code } = req.body;
    res.json({ success: true, message: 'Code redeemed' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/sponsorship/list', verifyToken, async (req, res) => {
  try {
    const { data } = await supabase.from('sponsorships').select('*').eq('parent_id', req.user.parent_id);
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// TEACHER AUTH & ENDPOINTS
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
        experience_years: experience || 0,
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
    
    const { data, error } = await supabase
      .from('lessons')
      .insert([{
        teacher_id: req.user.teacher_id,
        title,
        topic,
        subject,
        content,
        form_level: form_level || 4,
        status: 'published'
      }])
      .select();
    
    if (error) return res.status(400).json({ error: error.message });
    res.json({ lesson_id: data[0].id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/teacher/lessons', verifyToken, async (req, res) => {
  try {
    const { data } = await supabase
      .from('lessons')
      .select('*')
      .eq('teacher_id', req.user.teacher_id);
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.put('/api/teacher/lessons/:id', verifyToken, async (req, res) => {
  try {
    const { title, content, topic } = req.body;
    const { data } = await supabase
      .from('lessons')
      .update({ title, content, topic })
      .eq('id', req.params.id)
      .select();
    res.json(data[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/api/teacher/lessons/:id', verifyToken, async (req, res) => {
  try {
    await supabase.from('lessons').delete().eq('id', req.params.id);
    res.json({ message: 'Deleted' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/teacher/quizzes', verifyToken, async (req, res) => {
  try {
    const { title, topic, subject, form_level, questions } = req.body;
    
    const { data: quizData, error: quizError } = await supabase
      .from('quizzes')
      .insert([{
        teacher_id: req.user.teacher_id,
        title,
        topic,
        subject,
        form_level: form_level || 4,
        question_count: questions?.length || 0,
        difficulty: 'Medium'
      }])
      .select();
    
    if (quizError) return res.status(400).json({ error: quizError.message });
    
    if (questions && questions.length > 0) {
      const questionRows = questions.map(q => ({
        quiz_id: quizData[0].id,
        question: q.question,
        type: q.type,
        options: q.options ? JSON.stringify(q.options) : null,
        correct_answer: q.correct_answer,
        explanation: q.explanation || ''
      }));
      
      await supabase.from('quiz_questions').insert(questionRows);
    }
    
    res.json({ quiz_id: quizData[0].id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/teacher/quizzes', verifyToken, async (req, res) => {
  try {
    const { data } = await supabase
      .from('quizzes')
      .select('*')
      .eq('teacher_id', req.user.teacher_id);
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/teacher/analytics', verifyToken, async (req, res) => {
  try {
    const { data: quizzes } = await supabase
      .from('quizzes')
      .select('id')
      .eq('teacher_id', req.user.teacher_id);
    
    if (!quizzes?.length) return res.json({ total_students: 0, avg_score: 0 });
    
    const { data: results } = await supabase
      .from('quiz_results')
      .select('*')
      .in('quiz_id', quizzes.map(q => q.id));
    
    const avgScore = results?.length ? (results.reduce((sum, r) => sum + r.score, 0) / results.length).toFixed(1) : 0;
    res.json({ total_students: new Set(results?.map(r => r.student_id)).size, avg_score: avgScore });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/teacher/profile', verifyToken, async (req, res) => {
  try {
    const { data } = await supabase
      .from('teachers')
      .select('*')
      .eq('id', req.user.teacher_id)
      .single();
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/teacher/equity', verifyToken, async (req, res) => {
  try {
    const { data: lessons } = await supabase.from('lessons').select('id').eq('teacher_id', req.user.teacher_id);
    const { data: quizzes } = await supabase.from('quizzes').select('id').eq('teacher_id', req.user.teacher_id);
    
    res.json({
      equity_percentage: 5,
      lessons_contributed: lessons?.length || 0,
      quizzes_created: quizzes?.length || 0
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// HEALTH CHECK
app.get('/health', (req, res) => {
  res.json({ status: 'Learnova Backend Live! ✅' });
});

// START SERVER
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`✅ Learnova running on port ${PORT}`);
});
