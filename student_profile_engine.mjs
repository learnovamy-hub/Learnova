import {
  FREE_SUBJECTS,
  getStudentSubjects,
  getDashboardSubjects,
  getDisplayName,
} from './subject_access_engine.mjs';
import { getSmartGreeting } from './learnova_core.mjs';

let _supabase = null;

export function init(supabase) {
  _supabase = supabase;
}

// Generate unique display ID: LRN-XXXXXX
export async function generateLearnovaId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  for (let attempt = 0; attempt < 20; attempt++) {
    let id = 'LRN-';
    for (let i = 0; i < 6; i++) id += chars[Math.floor(Math.random() * chars.length)];
    const { data } = await _supabase
      .from('students')
      .select('id')
      .eq('learnova_id', id)
      .maybeSingle();
    if (!data) return id;
  }
  // Fallback: timestamp-based
  return 'LRN-' + Date.now().toString(36).toUpperCase().slice(-6);
}

// Complete onboarding — stores level + subjects, assigns LRN-ID
export async function completeOnboarding(userId, { level, selectedSubjects }) {
  const activeSubjects = getStudentSubjects(level, selectedSubjects);

  // Assign LRN-ID only if not yet assigned
  const { data: existing } = await _supabase
    .from('students')
    .select('learnova_id')
    .eq('id', userId)
    .single();

  let learnovaId = existing?.learnova_id;
  if (!learnovaId) learnovaId = await generateLearnovaId();

  // form_level column is integer — map string labels to numbers
  const levelMap = { 'Form 4': 4, 'Form 5': 5, 'A-Level': 6 };
  const formLevelInt = levelMap[level] ?? null;

  const { data, error } = await _supabase
    .from('students')
    .update({
      form_level: formLevelInt,
      selected_subjects: activeSubjects,
      onboarding_completed: true,
      learnova_id: learnovaId,
      academic_year: new Date().getFullYear(),
    })
    .eq('id', userId)
    .select()
    .single();

  if (error) throw error;
  return { student: data, learnovaId, activeSubjects };
}

// Full profile for returning student
export async function getStudentProfile(userId) {
  const { data: student } = await _supabase
    .from('students')
    .select('*')
    .eq('id', userId)
    .single();

  if (!student) return null;

  // Always include free subjects
  const stored = student.selected_subjects || [];
  const activeSubjects = [...new Set([...FREE_SUBJECTS, ...stored])];

  // Last study session for "continue learning" card
  const { data: lastSession } = await _supabase
    .from('study_sessions')
    .select('subject, topic, created_at')
    .eq('student_id', userId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const dashboardSubjects = getDashboardSubjects(activeSubjects);

  return {
    id: student.id,
    name: student.name,
    email: student.email,
    learnova_id: student.learnova_id || null,
    form_level: student.form_level,
    activeSubjects,
    dashboardSubjects,
    onboardingRequired: !student.onboarding_completed,
    onboarding_completed: !!student.onboarding_completed,
    lastSession: lastSession || null,
  };
}

// Build a personalised greeting for returning students
export function generateGreeting(profile) {
  const fullName = profile.name || '';
  const name = fullName.split(' ')[0] || 'pelajar';
  const level = profile.form_level || 'SPM';
  const subjects = (profile.activeSubjects || []).slice(0, 3);
  const subjectNames = subjects.map(s => getDisplayName(s)).join(', ');
  const last = profile.lastSession;

  const greet = getSmartGreeting(fullName);
  const base = `${greet}, ${name}! Saya ingat kamu pelajar ${level} yang sedang belajar ${subjectNames}.`;
  const cont = last
    ? ` Kita berhenti di topik "${last.topic}" baru-baru ini. Nak sambung dari sana?`
    : ' Apa yang kamu nak belajar hari ini?';

  return base + cont;
}

// Add a purchased subject to the student's active list
export async function addSubjectToStudent(userId, newSubject) {
  const { data: student } = await _supabase
    .from('students')
    .select('selected_subjects')
    .eq('id', userId)
    .single();

  if (!student) return false;

  const updated = [...new Set([...(student.selected_subjects || []), newSubject])];
  const { error } = await _supabase
    .from('students')
    .update({ selected_subjects: updated })
    .eq('id', userId);

  return !error;
}
