// HARDCODED — NEVER REMOVE
export const FREE_SUBJECTS = ['MY-BahasaMalaysia', 'MY-English'];

export const SUBJECT_CATALOGUE = {
  SPM: [
    'MY-BahasaMalaysia', 'MY-English', 'MY-Mathematics', 'MY-AddMaths',
    'MY-Physics', 'MY-Chemistry', 'MY-Biology', 'MY-Sejarah', 'MY-Geography',
  ],
  ALevel: [
    'AL-Mathematics', 'AL-FurtherMaths', 'AL-Physics', 'AL-Chemistry', 'AL-Biology',
  ],
  Indonesian: [
    'ID-BahasaIndonesia', 'ID-Matematika', 'ID-Fisika', 'ID-Kimia', 'ID-Biologi',
  ],
};

// Returns the full active subject list — always prepends free subjects
// Normalizes display names (e.g. 'Matematik') to API keys (e.g. 'MY-Mathematics')
export function getStudentSubjects(level, selectedSubjects = []) {
  const free = [...FREE_SUBJECTS];
  const extra = (selectedSubjects || [])
    .map(s => DISPLAY_TO_KEY[s] || s)
    .filter(s => !free.includes(s));
  return [...new Set([...free, ...extra])];
}

export function canAccessSubject(subject, studentSubjects) {
  if (FREE_SUBJECTS.includes(subject)) return true;
  return (studentSubjects || []).includes(subject);
}

export function getDashboardSubjects(studentSubjects) {
  return (studentSubjects || []).map(s => ({
    key: s,
    displayName: getDisplayName(s),
    isFree: FREE_SUBJECTS.includes(s),
    emoji: getSubjectEmoji(s),
  }));
}

export function getDisplayName(subject) {
  const names = {
    'MY-BahasaMalaysia': 'Bahasa Malaysia',
    'MY-English':         'English',
    'MY-Mathematics':     'Matematik',
    'MY-AddMaths':        'Add Maths',
    'MY-Physics':         'Fizik',
    'MY-Chemistry':       'Kimia',
    'MY-Biology':         'Biologi',
    'MY-Sejarah':         'Sejarah',
    'MY-Geography':       'Geografi',
    'AL-Mathematics':     'A-Level Mathematics',
    'AL-FurtherMaths':    'A-Level Further Maths',
    'AL-Physics':         'A-Level Physics',
    'AL-Chemistry':       'A-Level Chemistry',
    'AL-Biology':         'A-Level Biology',
    'ID-BahasaIndonesia': 'Bahasa Indonesia',
    'ID-Matematika':      'Matematika',
    'ID-Fisika':          'Fisika',
    'ID-Kimia':           'Kimia',
    'ID-Biologi':         'Biologi',
  };
  return names[subject] || subject;
}

export function getSubjectEmoji(subject) {
  const emojis = {
    'MY-BahasaMalaysia': '📘',
    'MY-English':         '📙',
    'MY-Mathematics':     '📐',
    'MY-AddMaths':        '📊',
    'MY-Physics':         '⚡',
    'MY-Chemistry':       '🧪',
    'MY-Biology':         '🧬',
    'MY-Sejarah':         '📜',
    'MY-Geography':       '🌍',
    'AL-Mathematics':     '📐',
    'AL-FurtherMaths':    '📊',
    'AL-Physics':         '⚡',
    'AL-Chemistry':       '🧪',
    'AL-Biology':         '🧬',
    'ID-BahasaIndonesia': '📘',
    'ID-Matematika':      '📐',
    'ID-Fisika':          '⚡',
    'ID-Kimia':           '🧪',
    'ID-Biologi':         '🧬',
  };
  return emojis[subject] || '📚';
}

// Flutter display name → prefixed key (mirrors normalizeSubject in server)
const DISPLAY_TO_KEY = {
  'Bahasa Malaysia': 'MY-BahasaMalaysia',
  'English':         'MY-English',
  'Mathematics':     'MY-Mathematics',
  'Matematik':       'MY-Mathematics',
  'Add Maths':       'MY-AddMaths',
  'Physics':         'MY-Physics',
  'Fizik':           'MY-Physics',
  'Chemistry':       'MY-Chemistry',
  'Kimia':           'MY-Chemistry',
  'Biology':         'MY-Biology',
  'Biologi':         'MY-Biology',
  'Sejarah':         'MY-Sejarah',
  'Geography':       'MY-Geography',
  'Geografi':        'MY-Geography',
};

export function toSubjectKey(displayName) {
  return DISPLAY_TO_KEY[displayName] || displayName;
}
