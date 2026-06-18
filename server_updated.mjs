import learningEngineRouter, { init as initLearningEngine } from './learning_engine.mjs';
import PregenLookup from './PregenLookup.mjs';
import * as subjectEngine from './subject_access_engine.mjs';
import * as profileEngine from './student_profile_engine.mjs';
import { formatNovaResponse, cleanTextForTTS, NOVA_ZH_PROMPT, NOVA_TA_PROMPT, TEACHING_LANGUAGES, AUDIO_COLUMN } from './learnova_core.mjs';
import cors from 'cors';
import express from 'express';
import { createClient } from '@supabase/supabase-js';
import jwt from 'jsonwebtoken';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import rateLimit from 'express-rate-limit';
import { exec } from 'child_process';

const app = express();
app.set('trust proxy', 1); // Railway runs behind a proxy — needed for express-rate-limit
const PORT = process.env.PORT || 3000;

const allowedBaseDomains = [
  'https://learnova.optimus.com.my',
];

app.use(cors({
  origin: function(origin, callback) {
    if (!origin) return callback(null, true);
    if (origin.startsWith('http://localhost')) {
      return callback(null, true);
    }
    // Normalize: strip www. prefix so both www and non-www are accepted
    const normalized = origin.replace(/^(https?:\/\/)www\./, '$1');
    if (allowedBaseDomains.includes(normalized)) {
      return callback(null, true);
    }
    console.error('CORS blocked:', origin);
    callback(new Error('Not allowed by CORS'));
  },
  credentials: true,
  methods: ['GET','POST','PUT','DELETE','OPTIONS'],
  allowedHeaders: ['Content-Type','Authorization'],
}));

app.options('*', cors());

const stripEmojis = (v) => (v || '')
  .replace(/[\u{1F000}-\u{1FFFF}]/gu, '')
  .replace(/[\u{2600}-\u{27BF}]/gu, '')
  .trim();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;
const claudeApiKey = process.env.CLAUDE_API_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error('FATAL: Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

console.log('Supabase connected:', supabaseUrl);
// Service role key bypasses RLS â€” correct for a trusted backend server
const supabase = createClient(supabaseUrl, supabaseKey);
const pregen = new PregenLookup(supabase);
initLearningEngine(supabase);
profileEngine.init(supabase);
const JWT_SECRET = process.env.JWT_SECRET || 'learnova-dev-secret-2025';

// ── Symbol dictionary (loaded from Supabase, cached, refreshed hourly) ────────
let SYMBOL_MAP = null; // null = not yet loaded; cleanTextForTTS falls back to hardcoded BM

async function loadSymbolDictionary() {
  try {
    const { data } = await supabase
      .from('symbol_dictionary')
      .select('symbol, spoken_bm, spoken_en, spoken_zh, priority')
      .order('priority', { ascending: false });
    if (data && data.length > 0) {
      SYMBOL_MAP = {
        bm: data.map(d => ({ pattern: d.symbol, replacement: ' ' + d.spoken_bm + ' ' })),
        en: data.map(d => ({ pattern: d.symbol, replacement: ' ' + d.spoken_en + ' ' })),
        zh: data.map(d => ({ pattern: d.symbol, replacement: ' ' + (d.spoken_zh || d.spoken_en) + ' ' })),
        ta: data.map(d => ({ pattern: d.symbol, replacement: ' ' + d.spoken_en + ' ' })),
        id: data.map(d => ({ pattern: d.symbol, replacement: ' ' + d.spoken_bm + ' ' })),
      };
      console.log('Symbol dictionary loaded: ' + data.length + ' entries');
    }
  } catch (err) {
    console.error('Symbol dictionary load failed:', err.message);
  }
}
loadSymbolDictionary();
setInterval(loadSymbolDictionary, 3600000);

// Maps Flutter display names --> prefixed Supabase subject keys
const SUBJECT_KEY_MAP = {
  'Mathematics':                'MY-Mathematics',
  'Matematik':                  'MY-Mathematics',
  'Add Maths':                  'MY-AddMaths',
  'Physics':                    'MY-Physics',
  'Fizik':                      'MY-Physics',
  'Biology':                    'MY-Biology',
  'Biologi':                    'MY-Biology',
  'Chemistry':                  'MY-Chemistry',
  'Kimia':                      'MY-Chemistry',
  'Sejarah':                    'MY-Sejarah',
  'Bahasa Malaysia':            'MY-BahasaMalaysia',
  'English':                    'MY-English',
  'Geography':                  'MY-Geography',
  'Geografi':                   'MY-Geography',
  'A-Level Biology':            'AL-Biology',
  'A-Level Chemistry':          'AL-Chemistry',
  'A-Level Mathematics':        'AL-Mathematics',
  'A-Level Further Mathematics':'AL-FurtherMaths',
  'A-Level Physics':            'AL-Physics',
  'Bahasa Indonesia':           'ID-BahasaIndonesia',
  'Fisika':                     'ID-Fisika',
  'Matematika':                 'ID-Matematika',
};
// Accept both old display name and new prefixed key
function normalizeSubject(s) { return s ? (SUBJECT_KEY_MAP[s] || s) : s; }

process.on('uncaughtException', (err) => { console.error('UNCAUGHT:', err); process.exit(1); });
process.on('unhandledRejection', (err) => { console.error('REJECTION:', err); process.exit(1); });

const __dirname = dirname(fileURLToPath(import.meta.url));
app.use(express.json());
app.use('/portals', express.static(join(__dirname, 'portals')));
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

const authStudent = (req, res, next) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'No token' });
  try { req.user = jwt.verify(token, JWT_SECRET); next(); }
  catch { res.status(401).json({ error: 'Invalid token' }); }
};
const authTeacher = (req, res, next) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'No token' });
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    if (!req.user.teacher_id) return res.status(403).json({ error: 'Teacher access only' });
    next();
  } catch { res.status(401).json({ error: 'Invalid token' }); }
};
const authParent = (req, res, next) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'No token' });
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    if (!req.user.parent_id) return res.status(403).json({ error: 'Parent access only' });
    next();
  } catch { res.status(401).json({ error: 'Invalid token' }); }
};

// â”€â”€ RATE LIMITING â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 min
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});
const tutorLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 min
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many tutor requests.' },
});
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many auth attempts, please wait.' },
});

app.use('/api/', generalLimiter);
app.use('/api/tutor', tutorLimiter);
app.use('/api/ai/ask', tutorLimiter);
app.use('/api/student/signup', authLimiter);
app.use('/api/student/login', authLimiter);
app.use('/api/teacher/signup', authLimiter);
app.use('/api/teacher/login', authLimiter);
app.use('/api/parent/signup', authLimiter);
app.use('/api/parent/login', authLimiter);
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

app.get('/', (req, res) => res.send('Learnova API v2.5'));
app.get('/health', async (req, res) => {
  const checks = {};

  // Supabase connection
  try {
    const { data, error } = await supabase
      .from('structured_lessons')
      .select('id')
      .limit(1);
    checks.supabase = error ? 'FAIL: ' + error.message : 'OK';
  } catch(e) {
    checks.supabase = 'FAIL: ' + e.message;
  }

  // CORS
  checks.cors_origin = 'learnova.optimus.com.my (www+non-www)';

  // Environment variables
  checks.claude_api_key  = process.env.CLAUDE_API_KEY     ? 'OK' : 'MISSING';
  checks.openai_key      = process.env.OPENAI_API_KEY     ? 'OK' : 'MISSING';
  checks.deepinfra_key   = process.env.DEEPINFRA_API_KEY  ? 'OK' : 'MISSING';
  checks.supabase_url    = process.env.SUPABASE_URL       ? 'OK' : 'MISSING';

  // Lesson count
  try {
    const { count } = await supabase
      .from('structured_lessons')
      .select('*', { count: 'exact', head: true })
      .eq('is_published', true);
    checks.lesson_count = count ?? 0;
  } catch(e) {
    checks.lesson_count = 'FAIL';
  }

  const allOk = !Object.values(checks)
    .some(v => typeof v === 'string' && v.startsWith('FAIL'));

  res.status(allOk ? 200 : 500).json({
    status: allOk ? 'OK' : 'DEGRADED',
    version: '2.5',
    timestamp: new Date().toISOString(),
    checks
  });
});

// â”€â”€ AUTO BACKUP â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function triggerBackup() {
  exec('python C:\\learnova_app\\extraction\\learnova_backup.py',
    (error) => {
      if (error) {
        console.log('[Backup] Failed:', error.message);
      } else {
        console.log('[Backup] Complete');
      }
    }
  );
}

// â”€â”€ FAQ DATA (Maths hardcoded, zero cost AI) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const FAQ_DATA = {
  "what is a function": { answer: "A function is a relation where every input (x-value) has exactly ONE output (y-value). If one input gives two different outputs, it's NOT a function.", topic: "Functions", example: "f(x) = 2x + 1. When x = 3, f(3) = 7. Only one answer!" },
  "what is domain and range": { answer: "Domain = all possible INPUT values (x-values). Range = all possible OUTPUT values (y-values). For f(x) = sqrt(x), domain is x >= 0, range is y >= 0.", topic: "Functions", example: "f(x) = 1/x â€” Domain: all x except 0. Range: all y except 0." },
  "how to find inverse function": { answer: "Step 1: Replace f(x) with y. Step 2: Swap x and y. Step 3: Solve for y. Step 4: Replace y with f-inverse(x). The inverse undoes what the function does.", topic: "Functions", example: "f(x) = 2x + 3 â†' swap â†' x = 2y + 3 â†' f-inv(x) = (x-3)/2" },
  "what is composite function": { answer: "fg(x) means apply g first, then f. Written as f(g(x)). Work from RIGHT to LEFT.", topic: "Functions", example: "f(x)=xÂ², g(x)=x+1. fg(x) = f(x+1) = (x+1)Â²" },
  "how to find fg x": { answer: "fg(x) = f(g(x)). Apply g first, substitute result into f.", topic: "Functions", example: "f(x)=3x, g(x)=x-2. fg(x) = f(x-2) = 3(x-2) = 3x-6" },
  "what is absolute value": { answer: "|x| always gives a positive value or zero. |x| = x if x >= 0, |x| = -x if x < 0. Distance from zero on number line.", topic: "Functions", example: "|5|=5, |-3|=3, |0|=0" },
  "how to graph a function": { answer: "1) Make a table of x and y values. 2) Plot points. 3) Connect smoothly. Find x-intercepts (y=0), y-intercept (x=0).", topic: "Functions", example: "f(x)=xÂ²: x=-2â†'4, x=-1â†'1, x=0â†'0, x=1â†'1, x=2â†'4. U-shape parabola!" },
  "what is quadratic equation": { answer: "axÂ² + bx + c = 0 where a â‰  0. Highest power is 2. Has at most 2 solutions.", topic: "Quadratic Equations", example: "xÂ² - 5x + 6 = 0 has solutions x=2 and x=3" },
  "how to use quadratic formula": { answer: "x = (-b Â± sqrt(bÂ²-4ac)) / 2a. Identify a, b, c from axÂ² + bx + c = 0 and substitute.", topic: "Quadratic Equations", example: "xÂ²-5x+6=0: a=1,b=-5,c=6. x=(5Â±1)/2. So x=3 or x=2" },
  "what is discriminant": { answer: "bÂ²-4ac tells you about roots: >0 means two real roots, =0 means one repeated root, <0 means no real roots.", topic: "Quadratic Equations", example: "xÂ²-4x+4=0: disc=16-16=0. One root: x=2" },
  "how to factorise quadratic": { answer: "Find two numbers that MULTIPLY to c and ADD to b in xÂ²+bx+c. Write as (x+p)(x+q).", topic: "Quadratic Equations", example: "xÂ²+5x+6: need Ã—=6, +=5. That's 2 and 3. Answer: (x+2)(x+3)" },
  "how to complete the square": { answer: "xÂ²+bx+c: add (b/2)Â² to both sides to get (x+b/2)Â²=something. Then solve.", topic: "Quadratic Equations", example: "xÂ²+6x+5=0 â†' (x+3)Â²=4 â†' x=-1 or x=-5" },
  "what is vertex of parabola": { answer: "Turning point of parabola. For axÂ²+bx+c, x-coord of vertex = -b/2a. If a>0, it's minimum. If a<0, it's maximum.", topic: "Quadratic Equations", example: "f(x)=xÂ²-4x+3: vertex x=2, y=-1. Vertex: (2,-1)" },
  "sum and product of roots": { answer: "For axÂ²+bx+c=0 with roots Î± and Î²: Î±+Î² = -b/a, Î±Î² = c/a.", topic: "Quadratic Equations", example: "xÂ²-5x+6=0: sum=5, product=6. Roots 2,3 check: 2+3=5âœ“, 2Ã—3=6âœ“" },
  "what are laws of indices": { answer: "aáµÃ—aâ¿=aáµâºâ¿, aáµÃ·aâ¿=aáµâ»â¿, (aáµ)â¿=aáµâ¿, aâ°=1, aâ»â¿=1/aâ¿, a^(1/n)=nth root of a, a^(m/n)=nth root of aáµ", topic: "Indices and Surds", example: "2Â³Ã—2â´=2â·=128. 5â°=1. 2â»Â³=1/8" },
  "what is a surd": { answer: "An irrational square root that cannot simplify to a whole number. sqrt(2), sqrt(3), sqrt(5) are surds. sqrt(4)=2 is NOT a surd.", topic: "Indices and Surds", example: "sqrt(12)=2sqrt(3) (surd). sqrt(9)=3 (not a surd)" },
  "how to simplify surds": { answer: "Find the largest perfect square factor: sqrt(n) = sqrt(aÂ²Ã—m) = aÃ—sqrt(m). Look for 4, 9, 16, 25, 36...", topic: "Indices and Surds", example: "sqrt(48)=4sqrt(3), sqrt(75)=5sqrt(3), sqrt(200)=10sqrt(2)" },
  "how to rationalise denominator": { answer: "Remove surds from denominator. For 1/sqrt(a): multiply by sqrt(a)/sqrt(a). For 1/(a+sqrt(b)): multiply by conjugate (a-sqrt(b))/(a-sqrt(b)).", topic: "Indices and Surds", example: "3/sqrt(2) = 3sqrt(2)/2. 1/(1+sqrt(3)) = (sqrt(3)-1)/2" },
  "how to add surds": { answer: "Only add LIKE surds (same number under root). Simplify first, then combine.", topic: "Indices and Surds", example: "2sqrt(3)+5sqrt(3)=7sqrt(3). sqrt(12)+sqrt(3)=2sqrt(3)+sqrt(3)=3sqrt(3)" },
  "what is negative index": { answer: "aâ»â¿ = 1/aâ¿. Flip it! Never makes the number negative. 2â»Â³ = 1/8 (still positive).", topic: "Indices and Surds", example: "3â»Â²=1/9. (1/2)â»Â³=8. xâ»Â¹=1/x" },
  "what is fractional index": { answer: "a^(m/n) = nth_root(aáµ). Denominator=ROOT, numerator=POWER.", topic: "Indices and Surds", example: "8^(2/3)=(cube_root 8)Â²=2Â²=4. 27^(1/3)=3. 16^(3/4)=2Â³=8" },
  "what is linear inequality": { answer: "Like a linear equation but with <, >, â‰¤, â‰¥ instead of =. Solution is a RANGE of values.", topic: "Linear Inequalities", example: "2x+3>7 â†' 2x>4 â†' x>2" },
  "how to solve linear inequality": { answer: "Solve like equation EXCEPT: multiplying or dividing by NEGATIVE number FLIPS the inequality sign!", topic: "Linear Inequalities", example: "-2x>6 â†' x<-3 (flipped!). But 2x>6 â†' x>3 (no flip)" },
  "how to show inequality on number line": { answer: "Open circle = strict inequality (< or >) endpoint NOT included. Closed circle = â‰¤ or â‰¥ endpoint IS included.", topic: "Linear Inequalities", example: "x>3: open circle at 3, arrow right. xâ‰¤-1: closed circle at -1, arrow left." },
  "what is combined inequality": { answer: "Has TWO conditions like a<x<b. Solve each part separately, find where BOTH satisfied.", topic: "Linear Inequalities", example: "-2<2x+4â‰¤10 â†' -3<xâ‰¤3" },
  "what is arithmetic progression": { answer: "AP: sequence where each term increases by constant COMMON DIFFERENCE d. General term: Tn = a+(n-1)d", topic: "Progressions", example: "3,7,11,15 is AP with a=3, d=4. Tâ‚…=3+4(4)=19" },
  "what is common difference": { answer: "d = any term minus the previous term. Constant throughout AP. Can be positive, negative, or zero.", topic: "Progressions", example: "5,8,11: d=3. 20,15,10: d=-5" },
  "sum of arithmetic progression": { answer: "Sn = n/2 Ã— (2a+(n-1)d) OR Sn = n/2 Ã— (first+last). Use whichever info you have!", topic: "Progressions", example: "AP: 2,5,8. S10 = 10/2Ã—(4+27) = 155" },
  "what is geometric progression": { answer: "GP: each term multiplied by constant RATIO r. General term: Tn = ar^(n-1)", topic: "Progressions", example: "2,6,18,54 is GP with a=2, r=3. Tâ‚…=2Ã—81=162" },
  "what is common ratio": { answer: "r = any term divided by previous term. If |r|<1 terms decrease. If |r|>1 terms grow.", topic: "Progressions", example: "4,12,36: r=3. 100,10,1: r=0.1" },
  "sum of geometric progression": { answer: "Sn = a(râ¿-1)/(r-1) when r>1. Sn = a(1-râ¿)/(1-r) when r<1.", topic: "Progressions", example: "GP: 3,6,12. S5 = 3(32-1)/1 = 93" },
  "sum to infinity gp": { answer: "For |r|<1: Sâˆž = a/(1-r). Only works when -1<r<1 (terms shrink to zero).", topic: "Progressions", example: "1,0.5,0.25: Sâˆž=1/(1-0.5)=2" },
  "how to find nth term": { answer: "AP: Tn=a+(n-1)d. GP: Tn=ar^(n-1). Identify AP or GP first: constant difference=AP, constant ratio=GP.", topic: "Progressions", example: "T8 of 2,5,8: a=2,d=3, T8=2+7(3)=23" },
  "what is a matrix": { answer: "Rectangular array of numbers in rows and columns. Order = mÃ—n (rows Ã— columns).", topic: "Matrices", example: "2Ã—3 matrix has 2 rows, 3 columns: [[1,2,3],[4,5,6]]" },
  "how to multiply matrices": { answer: "(mÃ—n)Ã—(nÃ—p)=(mÃ—p). Inner dimensions must match. Row times Column: multiply element by element then add.", topic: "Matrices", example: "[[1,2],[3,4]]Ã—[[5],[6]] = [[17],[39]]" },
  "what is inverse matrix": { answer: "AÃ—Aâ»Â¹=I. For 2Ã—2: Aâ»Â¹=(1/det)Ã—[[d,-b],[-c,a]] where det=ad-bc.", topic: "Matrices", example: "A=[[2,1],[5,3]]: det=1. Aâ»Â¹=[[3,-1],[-5,2]]" },
  "what is determinant": { answer: "For [[a,b],[c,d]]: det = ad-bc. If det=0, no inverse exists (singular matrix).", topic: "Matrices", example: "[[3,2],[1,4]]: det=12-2=10. [[2,4],[1,2]]: det=4-4=0 (no inverse)" },
  "what is gradient of line": { answer: "m = (yâ‚‚-yâ‚)/(xâ‚‚-xâ‚) = rise/run. Positive=up, Negative=down, Zero=horizontal, Undefined=vertical.", topic: "Coordinate Geometry", example: "Points (1,2)(3,6): m=(6-2)/(3-1)=2" },
  "equation of straight line": { answer: "y=mx+c (gradient-intercept), y-yâ‚=m(x-xâ‚) (point-slope), ax+by=c (general). m=gradient, c=y-intercept.", topic: "Coordinate Geometry", example: "m=3, passes (1,2): y=3x-1" },
  "how to find midpoint": { answer: "M = ((xâ‚+xâ‚‚)/2, (yâ‚+yâ‚‚)/2). Average the coordinates.", topic: "Coordinate Geometry", example: "Midpoint of (2,4)(8,10): M=(5,7)" },
  "distance between two points": { answer: "d = sqrt((xâ‚‚-xâ‚)Â²+(yâ‚‚-yâ‚)Â²). Pythagoras theorem!", topic: "Coordinate Geometry", example: "(1,2) to (4,6): sqrt(9+16)=5" },
  "parallel and perpendicular lines": { answer: "Parallel: same gradient (mâ‚=mâ‚‚). Perpendicular: mâ‚Ã—mâ‚‚=-1, so mâ‚‚=-1/mâ‚.", topic: "Coordinate Geometry", example: "Line y=2x+3. Parallel: y=2x-1. Perpendicular: y=-x/2+5" },
  "what is mean median mode": { answer: "Mean=sum/count. Median=middle value when sorted. Mode=most frequent value.", topic: "Statistics", example: "3,5,5,7,9: Mean=5.8, Median=5, Mode=5" },
  "what is standard deviation": { answer: "Measures how spread out data is from mean. Small SD=data close to mean. Large SD=widely spread.", topic: "Statistics", example: "SD=0 means all values identical. SD=5 means values typically 5 units from mean." },
  "soh cah toa": { answer: "Sin=Opposite/Hypotenuse, Cos=Adjacent/Hypotenuse, Tan=Opposite/Adjacent. Right-angled triangles only!", topic: "Trigonometry", example: "Opp=3, Hyp=5, Adj=4: Sin=0.6, Cos=0.8, Tan=0.75" },
  "sine rule": { answer: "a/sinA=b/sinB=c/sinC. Use with 2 angles+1 side, or 2 sides+non-included angle.", topic: "Trigonometry", example: "a/sin30Â°=b/sin45Â°. If a=5: b=5Ã—sin45Â°/sin30Â°â‰ˆ7.07" },
  "cosine rule": { answer: "aÂ²=bÂ²+cÂ²-2bcÂ·cosA. Use with 3 sides or 2 sides+included angle. cosA=(bÂ²+cÂ²-aÂ²)/(2bc)", topic: "Trigonometry", example: "b=5,c=7,A=60Â°: aÂ²=74-35=39, aâ‰ˆ6.24" },
  "area of triangle": { answer: "Area=Â½abÂ·sinC for any triangle. For right triangles: Â½Ã—baseÃ—height.", topic: "Trigonometry", example: "Sides 6,8 with 30Â° between: Area=Â½Ã—6Ã—8Ã—0.5=12 unitsÂ²" },
  "equation of circle": { answer: "(x-h)Â²+(y-k)Â²=rÂ². Centre (h,k), radius r. Or xÂ²+yÂ²+2gx+2fy+c=0, centre(-g,-f), radius=sqrt(gÂ²+fÂ²-c).", topic: "Circles", example: "Centre(3,-2), r=5: (x-3)Â²+(y+2)Â²=25" },
  "what is a vector": { answer: "Has both MAGNITUDE and DIRECTION. |a|=magnitude. -a reverses direction.", topic: "Vectors", example: "A(1,2) to B(4,6): AB=(3,4). |AB|=5" },
  "how to add vectors": { answer: "Add tip-to-tail. Algebraically: (aâ‚,aâ‚‚)+(bâ‚,bâ‚‚)=(aâ‚+bâ‚,aâ‚‚+bâ‚‚).", topic: "Vectors", example: "(2,3)+(4,-1)=(6,2). (5,7)-(2,3)=(3,4)" },
  "how to study maths": { answer: "1) Understand concepts, don't memorise. 2) Practice daily. 3) Do past papers. 4) Focus on weak topics. 5) Show all working for method marks!", topic: "Study Tips", example: "20 mins daily practice beats 3 hours on exam eve!" },
  "how to pass spm maths": { answer: "1) Master Form 4 topics. 2) Do 5+ past papers. 3) Time yourself. 4) Never leave blank. 5) Check your work!", topic: "Study Tips", example: "Students who do 5+ past papers average 30% higher marks." },
  "what is probability": { answer: "P(event) = favourable outcomes / total outcomes. Always between 0 and 1. P=0 means impossible, P=1 means certain.", topic: "Probability", example: "P(heads)=1/2. P(rolling 6)=1/6. P(red from 3R,2B)=3/5" },
  "what is permutation": { answer: "Arrangement where ORDER matters. nPr = n!/(n-r)!. Used for passwords, rankings, sequences.", topic: "Probability", example: "3 people in 3 seats: 3P3=3!=6 arrangements" },
  "what is combination": { answer: "Selection where ORDER does NOT matter. nCr = n!/(r!(n-r)!). Used for choosing teams, committees.", topic: "Probability", example: "Choose 3 from 5: 5C3=10 ways" },
  "what is normal distribution": { answer: "Bell-shaped curve symmetric about mean. 68% data within 1 SD, 95% within 2 SD, 99.7% within 3 SD.", topic: "Statistics", example: "Height data: mean=165cm, SD=5cm. 68% have height 160-170cm" },
  "what is set notation": { answer: "âˆª=union (or), âˆ©=intersection (and), A'=complement (not A), âˆ…=empty set, âˆˆ=is element of, âŠ‚=subset.", topic: "Sets", example: "A={1,2,3}, B={2,3,4}. AâˆªB={1,2,3,4}. Aâˆ©B={2,3}" },
  "what is venn diagram": { answer: "Circles overlapping to show sets. Overlapping region=intersection. Total area=union. Outside all circles=complement.", topic: "Sets", example: "Two circles A and B: middle overlap is Aâˆ©B, everything is AâˆªB" },
  "how to solve simultaneous equations": { answer: "Two methods: Substitution (express one variable, substitute) or Elimination (add/subtract to remove one variable).", topic: "Simultaneous Equations", example: "x+y=5, x-y=1. Add: 2x=6, x=3. So y=2." },
  "what is linear programming": { answer: "Optimising (max or min) an objective function subject to constraints (inequalities). Plot region, find vertices, test objective at each vertex.", topic: "Linear Programming", example: "Maximise P=3x+2y subject to x+yâ‰¤10, xâ‰¥0, yâ‰¥0. Check corner points." },
  "what is a logarithm": { answer: "log_a(x)=y means a^y=x. Log is the inverse of exponent. log_10 is common log, ln is natural log (base e).", topic: "Logarithms", example: "log_2(8)=3 because 2Â³=8. log_10(100)=2 because 10Â²=100" },
  "laws of logarithms": { answer: "log(AB)=logA+logB, log(A/B)=logA-logB, log(Aâ¿)=nlogA, log_a(a)=1, log_a(1)=0, change base: log_a(b)=log(b)/log(a)", topic: "Logarithms", example: "log(6)=log(2Ã—3)=log2+log3. log(2âµ)=5log2" },
  "how to solve exponential equation": { answer: "If bases can be matched: equal bases means equal powers. If not, take log of both sides.", topic: "Logarithms", example: "2^x=8 â†' 2^x=2Â³ â†' x=3. 3^x=10 â†' xlog3=log10 â†' x=1/log3â‰ˆ2.096" },
  "what is a polynomial": { answer: "Expression with non-negative integer powers: anxâ¿+...+a1x+a0. Degree=highest power. Polynomial division uses long division or synthetic.", topic: "Polynomials", example: "3xÂ³-2xÂ²+5x-1 is degree 3 polynomial" },
  "remainder theorem": { answer: "When polynomial f(x) divided by (x-a), remainder = f(a). No need to do full division!", topic: "Polynomials", example: "f(x)=xÂ³-2x+1 divided by (x-2): remainder=f(2)=8-4+1=5" },
  "factor theorem": { answer: "If f(a)=0, then (x-a) is a factor of f(x). Use to find factors without full division.", topic: "Polynomials", example: "f(x)=xÂ³-6xÂ²+11x-6. f(1)=0, so (x-1) is a factor" },
  "what is partial fractions": { answer: "Breaking a complex fraction into simpler parts. For (px+q)/((ax+b)(cx+d)) = A/(ax+b) + B/(cx+d). Find A,B by substituting.", topic: "Partial Fractions", example: "5/(xÂ²-1) = A/(x-1) + B/(x+1). Solve: A=5/2, B=-5/2" },
  "what is binomial expansion": { answer: "(a+b)â¿ = sum of nCr Ã— aâ¿â»Ê³ Ã— bÊ³ for r=0 to n. Coefficients from Pascal's Triangle or nCr.", topic: "Binomial Expansion", example: "(1+x)Â³ = 1+3x+3xÂ²+xÂ³. Coefficients: 1,3,3,1 from Pascal's row 3" },
  "what is differentiation": { answer: "Finding the rate of change (gradient) of a function. d/dx(xâ¿)=nxâ¿â»Â¹. Differentiation = finding f'(x) = slope at any point.", topic: "Differentiation", example: "f(x)=xÂ³: f'(x)=3xÂ². At x=2: gradient=12" },
  "what is integration": { answer: "Reverse of differentiation. âˆ«xâ¿ dx = xâ¿âºÂ¹/(n+1) + C. Definite integral gives area under curve between two x values.", topic: "Integration", example: "âˆ«xÂ² dx = xÂ³/3 + C. âˆ«â‚€Â² xÂ² dx = [xÂ³/3]â‚€Â² = 8/3" },
  "how to find stationary points": { answer: "Set f'(x)=0 and solve for x. Then find y-value. Use f''(x) to determine: f''(x)>0 means minimum, f''(x)<0 means maximum.", topic: "Differentiation", example: "f(x)=xÂ²-4x: f'(x)=2x-4=0 â†' x=2. f''(2)=2>0 so minimum at (2,-4)" }
};

// â”€â”€ FUZZY MATCH for hardcoded FAQ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function findBestFAQ(query) {
  const q = query.toLowerCase().trim();
  const keys = Object.keys(FAQ_DATA);
  if (FAQ_DATA[q]) return FAQ_DATA[q];
  for (const key of keys) {
    if (q.includes(key) || key.includes(q)) return FAQ_DATA[key];
  }
  const qWords = new Set(q.split(/\s+/).filter(w => w.length > 2));
  let bestMatch = null, bestScore = 0;
  for (const key of keys) {
    const keyWords = key.split(/\s+/);
    let score = keyWords.filter(w => qWords.has(w)).length;
    if (score > bestScore) { bestScore = score; bestMatch = FAQ_DATA[key]; }
  }
  return bestScore >= 1 ? bestMatch : null;
}

// â”€â”€ SEARCH faq_cache table (multi-subject) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
async function searchFaqCache(query, subject) {
  try {
    const q = query.toLowerCase().trim();
    // Build query
    let dbQuery = supabase
      .from('faq_cache')
      .select('question, answer, topic, subject')
      .not('answer', 'is', null);

    // Filter by subject if provided
    if (subject) {
      dbQuery = dbQuery.ilike('subject', `%${subject}%`);
    }

    const { data, error } = await dbQuery;
    if (error || !data?.length) return null;

    // Score each result by word overlap
    const qWords = new Set(q.split(/\s+/).filter(w => w.length > 2));
    let bestMatch = null, bestScore = 0;

    for (const row of data) {
      const rowQ = (row.question || '').toLowerCase();
      // Exact match
      if (rowQ === q) return row;
      // Contains match
      if (rowQ.includes(q) || q.includes(rowQ)) {
        if (row.answer) return row;
      }
      // Word overlap score
      const rowWords = rowQ.split(/\s+/);
      const score = rowWords.filter(w => qWords.has(w)).length;
      if (score > bestScore && row.answer) {
        bestScore = score;
        bestMatch = row;
      }
    }

    return bestScore >= 1 ? bestMatch : null;
  } catch (err) {
    console.error('faq_cache search error:', err.message);
    return null;
  }
}

// â”€â”€ AI ASK ENDPOINT (updated: FAQ â†' faq_cache â†' Claude) â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.post('/api/ai/ask', authStudent, async (req, res) => {
  try {
    const { question, topic, subject, use_claude } = req.body;
    if (!question) return res.status(400).json({ error: 'Question required' });

    // Phase 1a: Check hardcoded Maths FAQ (instant, $0)
    if (!use_claude && (!subject || subject.toLowerCase().includes('math'))) {
      const faqHit = findBestFAQ(question);
      if (faqHit) {
        return res.json({
          answer: faqHit.answer,
          example: faqHit.example,
          topic: faqHit.topic,
          subject: 'Mathematics',
          source: 'faq',
          cost: 0
        });
      }
    }

    // Phase 1b: Check faq_cache table (all 8 subjects, $0)
    if (!use_claude) {
      const cacheHit = await searchFaqCache(question, subject);
      if (cacheHit) {
        return res.json({
          answer: cacheHit.answer,
          topic: cacheHit.topic,
          subject: cacheHit.subject,
          source: 'faq_cache',
          cost: 0
        });
      }
    }

    // Phase 2: Claude API fallback
    if (!claudeApiKey) {
      return res.json({
        answer: "Great question! I don't have a specific answer for that yet. Please ask your teacher or try rephrasing.",
        source: 'fallback',
        cost: 0
      });
    }

    const { default: Anthropic } = await import('@anthropic-ai/sdk');
    const anthropic = new Anthropic({ apiKey: claudeApiKey });
    const subjectLabel = subject || 'General';
    const message = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 600,
      system: `You are Learnova AI, a warm Malaysian Form 4-5 tutor. Subject: ${subjectLabel}. Topic: ${topic || 'General'}. Explain clearly with examples in under 150 words. Always include an Example: section.`,
      messages: [{ role: 'user', content: question }]
    });

    res.json({
      answer: message.content[0].text,
      topic: topic || 'General',
      subject: subjectLabel,
      source: 'claude',
      cost: 'minimal'
    });
  } catch (err) {
    console.error('AI ask error:', err);
    res.status(500).json({ error: err.message });
  }
});

// â”€â”€ FAQ LIST (combined: hardcoded + faq_cache) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.get('/api/ai/faq', async (req, res) => {
  try {
    const { subject } = req.query;

    // Always include hardcoded Maths FAQ
    const topics = {};
    if (!subject || subject.toLowerCase().includes('math')) {
      for (const [key, val] of Object.entries(FAQ_DATA)) {
        if (!topics[val.topic]) topics[val.topic] = [];
        topics[val.topic].push({ question: key });
      }
    }

    // Also pull from faq_cache
    let dbQuery = supabase.from('faq_cache').select('question, topic, subject');
    if (subject) dbQuery = dbQuery.ilike('subject', `%${subject}%`);
    const { data } = await dbQuery;

    if (data?.length) {
      for (const row of data) {
        const key = row.subject ? `${row.subject} > ${row.topic}` : row.topic;
        if (!topics[key]) topics[key] = [];
        topics[key].push({ question: row.question });
      }
    }

    const total = Object.values(topics).reduce((s, arr) => s + arr.length, 0);
    res.json({ total, topics });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/ai/faq/:topic', (req, res) => {
  const tf = req.params.topic.toLowerCase();
  const results = Object.entries(FAQ_DATA)
    .filter(([, v]) => v.topic.toLowerCase().includes(tf))
    .map(([q, v]) => ({ question: q, answer: v.answer, example: v.example, topic: v.topic }));
  res.json(results);
});

// â”€â”€ SUBJECTS LIST endpoint â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.get('/api/ai/subjects', async (req, res) => {
  try {
    const { data } = await supabase
      .from('faq_cache')
      .select('subject')
      .order('subject');

    const subjects = ['Mathematics', ...new Set((data || []).map(r => r.subject).filter(Boolean))];
    res.json({ subjects: [...new Set(subjects)] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// â”€â”€ STUDENT ROUTES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.post('/api/student/signup', async (req, res) => {
  try {
    const { email, password, name, parent_email } = req.body;
    if (!email || !password) return res.status(400).json({ error: 'Email and password required' });
    const { data: existing } = await supabase.from('students').select('id').eq('email', email).maybeSingle();
    if (existing) return res.status(400).json({ error: 'Email already registered' });
    const { data, error } = await supabase.from('students').insert([{ email, password_hash: password, name: name || 'Student', parent_email: parent_email || null }]).select();
    if (error) return res.status(400).json({ error: error.message });
    const token = jwt.sign({ student_id: data[0].id, email }, JWT_SECRET, { expiresIn: '30d' });
    res.json({ token, student_id: data[0].id, name: data[0].name });
    triggerBackup();
  } catch (err) { console.error('Student signup:', err); res.status(500).json({ error: err.message }); }
});

app.post('/api/student/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const { data } = await supabase.from('students').select('*').eq('email', email).eq('password_hash', password).maybeSingle();
    if (!data) return res.status(401).json({ error: 'Invalid email or password' });
    const token = jwt.sign({ student_id: data.id, email }, JWT_SECRET, { expiresIn: '30d' });
    res.json({ token, student_id: data.id, name: data.name });
  } catch (err) { console.error('Student login:', err); res.status(500).json({ error: err.message }); }
});

app.get('/api/student/profile', authStudent, async (req, res) => {
  try {
    const profile = await profileEngine.getStudentProfile(req.user.student_id);
    if (!profile) return res.status(404).json({ error: 'Student not found' });

    const { data: results } = await supabase
      .from('quiz_results')
      .select('score, total, percentage, created_at')
      .eq('student_id', req.user.student_id);
    const { data: sessions } = await supabase
      .from('study_sessions')
      .select('duration_minutes, topic')
      .eq('student_id', req.user.student_id);

    const totalQuizzes = results?.length || 0;
    const avgScore = totalQuizzes > 0
      ? Math.round(results.reduce((s, r) => s + r.percentage, 0) / totalQuizzes) : 0;
    const totalStudyTime = sessions?.reduce((s, ss) => s + (ss.duration_minutes || 0), 0) || 0;

    const greeting = !profile.onboardingRequired ? profileEngine.generateGreeting(profile) : null;

    res.json({
      student: {
        id: profile.id,
        name: profile.name,
        email: profile.email,
        learnova_id: profile.learnova_id,
        form_level: profile.form_level,
        selected_subjects: profile.activeSubjects,
        active_subjects: profile.activeSubjects,
        onboarding_completed: profile.onboarding_completed,
        onboardingRequired: profile.onboardingRequired,
        profile_complete: !profile.onboardingRequired,
        dashboardSubjects: profile.dashboardSubjects,
      },
      stats: { totalQuizzes, avgScore, totalStudyTime },
      greeting,
      lastSession: profile.lastSession,
    });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// Complete onboarding â€” sets level, subjects, assigns LRN-ID
app.post('/api/student/onboard', authStudent, async (req, res) => {
  try {
    const { level, selectedSubjects } = req.body;
    if (!level) return res.status(400).json({ error: 'level required' });
    const result = await profileEngine.completeOnboarding(
      req.user.student_id, { level, selectedSubjects: selectedSubjects || [] }
    );
    res.json({
      success: true,
      learnova_id: result.learnovaId,
      active_subjects: result.activeSubjects,
      dashboardSubjects: subjectEngine.getDashboardSubjects(result.activeSubjects),
    });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// Add a subject after purchase
app.post('/api/student/add-subject', authStudent, async (req, res) => {
  try {
    const { subject } = req.body;
    if (!subject) return res.status(400).json({ error: 'subject required' });
    const success = await profileEngine.addSubjectToStudent(req.user.student_id, subject);
    res.json({ success });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// Subject catalogue for onboarding screen
app.get('/api/subjects/catalogue', async (req, res) => {
  try {
    const { level } = req.query;
    const catalogue = subjectEngine.SUBJECT_CATALOGUE[level] || subjectEngine.SUBJECT_CATALOGUE.SPM;
    res.json({
      catalogue: subjectEngine.getDashboardSubjects(catalogue),
      freeSubjects: subjectEngine.FREE_SUBJECTS,
    });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/student/session', authStudent, async (req, res) => {
  try {
    const { topic, duration_minutes, subject } = req.body;
    const { data, error } = await supabase.from('study_sessions').insert([{ student_id: req.user.student_id, topic, duration_minutes, subject: subject || 'Mathematics' }]).select();
    if (error) return res.status(400).json({ error: error.message });
    res.json({ session_id: data[0].id, message: 'Session recorded' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/student/quiz-history', authStudent, async (req, res) => {
  try {
    const { data } = await supabase.from('quiz_results').select('*, quizzes(title, topic)').eq('student_id', req.user.student_id).order('created_at', { ascending: false }).limit(20);
    res.json(data || []);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// â”€â”€ LESSON ROUTES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.get('/api/lessons', async (req, res) => {
  try {
    const { subject, form_level, limit } = req.query;
    const cols = 'id,title,topic,subject,form_level,teacher_id,created_at,introduction,content,summary,worked_examples,common_mistakes';
    // Accept lessons published via either flag (is_published=true) or status field ('published'/'active')
    let query = supabase.from('lessons').select(cols).or('is_published.eq.true,status.eq.published,status.eq.active');
    if (subject) query = query.ilike('subject', normalizeSubject(subject));
    if (form_level) query = query.eq('form_level', form_level);
    query = query.order('created_at', { ascending: false });
    if (limit) query = query.limit(parseInt(limit));
    const { data, error } = await query;
    if (error) return res.status(400).json({ error: error.message });
    res.json(data || []);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/lessons/detail/:id', async (req, res) => {
  try {
    const { data, error } = await supabase.from('lessons').select('*').eq('id', req.params.id).single();
    if (error || !data) return res.status(404).json({ error: 'Lesson not found' });
    if (req.headers.authorization) {
      try {
        const d = jwt.verify(req.headers.authorization.replace('Bearer ', ''), JWT_SECRET);
        if (d.student_id) await supabase.from('lesson_views').insert([{ lesson_id: req.params.id, student_id: d.student_id }]);
      } catch {}
    }
    res.json(data);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// -- QUESTION BANK QUIZ ROUTES --
app.get('/api/quizzes/list/:subject', authStudent, async (req, res) => {
  try {
    const subject = req.params.subject;
    const { data, error } = await supabase
      .from('question_bank')
      .select('topic')
      .eq('subject', subject)
      .eq('country', 'MY')
      .not('topic', 'is', null);
    if (error) throw error;
    // Group by topic, count questions per topic
    const topicMap = {};
    (data || []).forEach(row => {
      const t = row.topic;
      if (t) topicMap[t] = (topicMap[t] || 0) + 1;
    });
    const topics = Object.entries(topicMap)
      .map(([topic, count]) => ({
        id: `${subject}-${topic}`,
        title: topic,
        topic,
        subject,
        total_questions: count,
        difficulty: 'mixed'
      }))
      .sort((a, b) => a.topic.localeCompare(b.topic));
    res.json(topics);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/quizzes/questions/:subject/:topic', authStudent, async (req, res) => {
  try {
    const { subject, topic } = req.params;
    const { data, error } = await supabase
      .from('question_bank')
      .select('id,question_text,options,correct_answer,full_solution,difficulty')
      .eq('subject', subject)
      .eq('topic', decodeURIComponent(topic))
      .eq('country', 'MY')
      .eq('question_type', 'multiple_choice')
      .limit(20);
    if (error) throw error;
    res.json(data || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -- QUIZ ROUTES (teacher-created quizzes) --
app.get('/api/quiz/list/:subject', async (req, res) => {
  try {
    const { data } = await supabase.from('quizzes').select('id,title,topic,subject,total_questions,difficulty').eq('subject', req.params.subject).eq('is_published', true);
    res.json(data || []);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/quiz/:id', async (req, res) => {
  try {
    const { data: quiz } = await supabase.from('quizzes').select('*').eq('id', req.params.id).single();
    const { data: questions } = await supabase.from('quiz_questions').select('*').eq('quiz_id', req.params.id);
    if (!quiz) return res.status(404).json({ error: 'Quiz not found' });
    res.json({ ...quiz, questions: questions || [] });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/quiz/:id/submit', authStudent, async (req, res) => {
  try {
    const { answers, time_taken_seconds } = req.body;
    const { data: questions } = await supabase.from('quiz_questions').select('*').eq('quiz_id', req.params.id);
    if (!questions?.length) return res.status(404).json({ error: 'Questions not found' });
    let score = 0;
    const feedback = questions.map(q => {
      const studentAnswer = answers?.[q.id];
      const correct = studentAnswer === q.correct_answer;
      if (correct) score++;
      return { question_id: q.id, correct, correct_answer: q.correct_answer, student_answer: studentAnswer, explanation: q.explanation };
    });
    const percentage = Math.round((score / questions.length) * 100);
    const { data: result } = await supabase.from('quiz_results').insert([{ student_id: req.user.student_id, quiz_id: req.params.id, score, total: questions.length, percentage, time_taken_seconds: time_taken_seconds || 0 }]).select();
    res.json({ score, total: questions.length, percentage, feedback, result_id: result?.[0]?.id });
    triggerBackup();
  } catch (err) { console.error('Quiz submit:', err); res.status(500).json({ error: err.message }); }
});

// â”€â”€ TEACHER ROUTES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.post('/api/teacher/signup', async (req, res) => {
  try {
    const { email, password, name, subject, school } = req.body;
    if (!email || !password || !name) return res.status(400).json({ error: 'Email, password, name required' });
    const { data: existing } = await supabase.from('teachers').select('id').eq('email', email).maybeSingle();
    if (existing) return res.status(400).json({ error: 'Email already registered' });
    const { data, error } = await supabase.from('teachers').insert([{ email, password_hash: password, name, subject: subject || 'Mathematics', school: school || null }]).select();
    if (error) return res.status(400).json({ error: error.message });
    const token = jwt.sign({ teacher_id: data[0].id, email }, JWT_SECRET, { expiresIn: '30d' });
    res.json({ token, teacher_id: data[0].id, name: data[0].name });
  } catch (err) { console.error('Teacher signup:', err); res.status(500).json({ error: err.message }); }
});

app.post('/api/teacher/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const { data } = await supabase.from('teachers').select('*').eq('email', email).eq('password_hash', password).maybeSingle();
    if (!data) return res.status(401).json({ error: 'Invalid credentials' });
    const token = jwt.sign({ teacher_id: data.id, email }, JWT_SECRET, { expiresIn: '30d' });
    res.json({ token, teacher_id: data.id, name: data.name });
  } catch (err) { console.error('Teacher login:', err); res.status(500).json({ error: err.message }); }
});

app.post('/api/teacher/lessons', authTeacher, async (req, res) => {
  try {
    const { title, topic, subject, form_level, content, introduction, learning_objectives, key_concepts, summary, is_published } = req.body;
    if (!title || !topic) return res.status(400).json({ error: 'Title and topic required' });
    const { data, error } = await supabase.from('lessons').insert([{ teacher_id: req.user.teacher_id, title, topic, subject: subject || 'Mathematics', form_level: form_level || 4, content: content || '', introduction: introduction || '', learning_objectives: learning_objectives || [], key_concepts: key_concepts || [], summary: summary || '', is_published: is_published || false }]).select();
    if (error) return res.status(400).json({ error: error.message });
    res.json({ lesson_id: data[0].id, message: 'Lesson created' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/teacher/lessons', authTeacher, async (req, res) => {
  try {
    const { data } = await supabase.from('lessons').select('*').eq('teacher_id', req.user.teacher_id).order('created_at', { ascending: false });
    res.json(data || []);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/teacher/quizzes', authTeacher, async (req, res) => {
  try {
    const { title, topic, subject, form_level, questions, difficulty, lesson_id } = req.body;
    if (!title || !questions?.length) return res.status(400).json({ error: 'Title and questions required' });
    const { data: quiz, error } = await supabase.from('quizzes').insert([{ teacher_id: req.user.teacher_id, title, topic, subject: subject || 'Mathematics', form_level: form_level || 4, total_questions: questions.length, difficulty: difficulty || 'medium', lesson_id: lesson_id || null, is_published: true }]).select();
    if (error) return res.status(400).json({ error: error.message });
    const qRows = questions.map(q => ({ quiz_id: quiz[0].id, question: q.question, type: q.type || 'multiple_choice', options: q.options || [], correct_answer: q.correct_answer, explanation: q.explanation || '' }));
    await supabase.from('quiz_questions').insert(qRows);
    res.json({ quiz_id: quiz[0].id, message: `Quiz with ${questions.length} questions created` });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/teacher/analytics', authTeacher, async (req, res) => {
  try {
    const { data: lessons } = await supabase.from('lessons').select('id,title,topic').eq('teacher_id', req.user.teacher_id);
    const { data: quizzes } = await supabase.from('quizzes').select('id,title,topic').eq('teacher_id', req.user.teacher_id);
    const lessonIds = (lessons || []).map(l => l.id);
    const quizIds = (quizzes || []).map(q => q.id);
    let totalViews = 0, totalAttempts = 0, avgScore = 0;
    if (lessonIds.length > 0) { const { count } = await supabase.from('lesson_views').select('id', { count: 'exact' }).in('lesson_id', lessonIds); totalViews = count || 0; }
    if (quizIds.length > 0) { const { data: results } = await supabase.from('quiz_results').select('percentage').in('quiz_id', quizIds); totalAttempts = results?.length || 0; avgScore = totalAttempts > 0 ? Math.round(results.reduce((s, r) => s + r.percentage, 0) / totalAttempts) : 0; }
    res.json({ lessons: lessons?.length || 0, quizzes: quizzes?.length || 0, totalViews, totalAttempts, avgScore });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/teacher/generate-lesson', authTeacher, async (req, res) => {
  try {
    const { topic, subject, form_level, textbook_content, pedagogy_notes } = req.body;
    if (!topic) return res.status(400).json({ error: 'Topic required' });
    if (!claudeApiKey) return res.status(500).json({ error: 'Claude API key not configured' });
    const { default: Anthropic } = await import('@anthropic-ai/sdk');
    const anthropic = new Anthropic({ apiKey: claudeApiKey });
    const message = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001', max_tokens: 2000,
      system: 'You are a Malaysian secondary school curriculum designer for Form 4-5 KSSM syllabus. Return ONLY valid JSON, no markdown.',
      messages: [{ role: 'user', content: `Create lesson for Form ${form_level || 4} ${subject || 'Mathematics'}.\nTopic: ${topic}\n${textbook_content ? 'Content: ' + textbook_content : ''}\n${pedagogy_notes ? 'Teaching style: ' + pedagogy_notes : ''}\nReturn JSON: {"title":"","introduction":"","learning_objectives":[],"key_concepts":[],"explanation":"","worked_examples":[{"problem":"","solution":""}],"summary":"","quiz_questions":[{"question":"","type":"multiple_choice","options":["A)","B)","C)","D)"],"correct_answer":"A)","explanation":""}]}` }]
    });
    let generated;
    try { generated = JSON.parse(message.content[0].text); } catch { generated = JSON.parse(message.content[0].text.replace(/```json|```/g, '').trim()); }
    res.json({ lesson: generated, message: 'Lesson generated by AI!' });
  } catch (err) { console.error('Generate lesson:', err); res.status(500).json({ error: err.message }); }
});

// â”€â”€ PARENT ROUTES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.post('/api/parent/signup', async (req, res) => {
  try {
    const { email, password, name, child_email } = req.body;
    if (!email) return res.status(400).json({ error: 'Email required' });
    const { data, error } = await supabase.from('parents').insert([{ email, password_hash: password || null, name: name || 'Parent' }]).select();
    if (error) return res.status(400).json({ error: error.message });
    if (child_email) await supabase.from('students').update({ parent_email: email }).eq('email', child_email);
    const token = jwt.sign({ parent_id: data[0].id, email }, JWT_SECRET, { expiresIn: '30d' });
    res.json({ token, parent_id: data[0].id });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/parent/login', async (req, res) => {
  try {
    const { email } = req.body;
    const { data } = await supabase.from('parents').select('*').eq('email', email).maybeSingle();
    if (!data) return res.status(401).json({ error: 'Account not found' });
    const token = jwt.sign({ parent_id: data.id, email }, JWT_SECRET, { expiresIn: '30d' });
    res.json({ token, parent_id: data.id, name: data.name });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/parent/dashboard', authParent, async (req, res) => {
  try {
    const parentId = req.user.parent_id;
    const { data: parent } = await supabase.from('parents').select('name,email').eq('id', parentId).single();
    const parentEmail = parent?.email || req.user.email;

    // Find children via parent_email on students OR parent_child_links
    const { data: byEmail } = await supabase.from('students').select('*').eq('parent_email', parentEmail);
    const byLinkRes = await supabase.from('parent_child_links').select('student_id').eq('parent_id', parentId);
    const byLink = byLinkRes.data || [];
    const linkedIds = (byLink || []).map(l => l.student_id);
    let allChildren = [...(byEmail || [])];
    if (linkedIds.length) {
      const { data: linked } = await supabase.from('students').select('*').in('id', linkedIds);
      (linked || []).forEach(s => { if (!allChildren.find(c => c.id === s.id)) allChildren.push(s); });
    }
    if (!allChildren.length) return res.json({ parent_name: parent?.name || 'Ibu Bapa', children: [], pending_count: 0 });

    const SPM_DATE = new Date('2026-11-10');
    const children = await Promise.all(allChildren.map(async (child) => {
      const sid = child.id;
      const [quizRes, sessRes, progressRes, loginsRes] = await Promise.all([
        supabase.from('quiz_results').select('percentage,created_at,subject,topic').eq('student_id', sid).order('created_at', { ascending: false }).limit(30),
        supabase.from('lesson_sessions').select('lesson_id,subject,started_at,ended_at,duration_seconds,completed').eq('student_id', sid).order('started_at', { ascending: false }).limit(30),
        supabase.from('student_lesson_progress').select('lesson_id,status,completed_at').eq('student_id', sid),
        supabase.from('student_logins').select('logged_at').eq('student_id', sid).order('logged_at', { ascending: false }).limit(1),
      ]);
      const quizzes = quizRes.data || [];
      const sessions = sessRes.data || [];
      const progress = progressRes.data || [];
      const lastLogin = loginsRes.data?.[0]?.logged_at;

      // Is active now (lesson session started < 5 min ago with no end)
      const activeSession = sessions.find(s => !s.ended_at && s.started_at && (Date.now() - new Date(s.started_at)) < 300000);
      const isActiveNow = !!activeSession;

      // Streak (consecutive days with any activity)
      const activityDays = new Set([...sessions, ...quizzes].map(a => (a.started_at || a.created_at || '').substring(0, 10)));
      let streak = 0;
      let d = new Date(); d.setHours(0,0,0,0);
      while (activityDays.has(d.toISOString().substring(0,10))) { streak++; d.setDate(d.getDate()-1); }

      // SPM countdown
      const daysRemaining = Math.max(0, Math.ceil((SPM_DATE - Date.now()) / 86400000));
      const TOTAL_LESSONS_PER_SUBJECT = 24; // fixed denominator â€” actual structured_lessons count
      const completedLessons = progress.filter(p => p.status === 'completed').length;
      const projectedCoverage = Math.min(100, Math.round((completedLessons / TOTAL_LESSONS_PER_SUBJECT) * 100));

      // Subject performance
      const subjMap = {};
      quizzes.forEach(q => {
        const s = q.subject || 'Umum';
        if (!subjMap[s]) subjMap[s] = { scores: [], topics: {} };
        subjMap[s].scores.push(q.percentage || 0);
        const t = q.topic || 'Umum';
        if (!subjMap[s].topics[t]) subjMap[s].topics[t] = { total: 0, count: 0 };
        subjMap[s].topics[t].total += q.percentage || 0;
        subjMap[s].topics[t].count++;
      });
      sessions.forEach(s => {
        const subj = s.subject || 'Umum';
        if (!subjMap[subj]) subjMap[subj] = { scores: [], topics: {} };
      });
      const subjectPerformance = Object.entries(subjMap).map(([subject, d]) => {
        const avg = d.scores.length ? Math.round(d.scores.reduce((a,b)=>a+b,0)/d.scores.length) : null;
        const topicAvgs = Object.entries(d.topics).map(([t, td]) => ({ topic: t, avg: Math.round(td.total/td.count) })).sort((a,b)=>a.avg-b.avg);
        const weakest = topicAvgs.slice(0,2).map(t=>t.topic);
        return { subject, avg_score: avg, trend: 'stable', sessions: sessions.filter(s=>s.subject===subject).length, topics_done: completedLessons, topics_total: 20, weakest_concepts: weakest };
      });

      // Behaviour
      const hourCounts = {};
      sessions.forEach(s => { if (s.started_at) { const h = new Date(s.started_at).getHours(); hourCounts[h] = (hourCounts[h]||0)+1; }});
      const peakHour = Object.keys(hourCounts).length ? Number(Object.entries(hourCounts).sort((a,b)=>b[1]-a[1])[0][0]) : null;
      const totalSecs = sessions.reduce((a,s)=>a+(s.duration_seconds||0),0);
      const avgSessionMins = sessions.length ? Math.round(totalSecs/sessions.length/60) : 0;
      const dayNames = ['Ahad','Isnin','Selasa','Rabu','Khamis','Jumaat','Sabtu'];
      const dayCounts = {};
      sessions.forEach(s => { if (s.started_at) { const dn = dayNames[new Date(s.started_at).getDay()]; dayCounts[dn]=(dayCounts[dn]||0)+1; }});
      const productiveDays = Object.entries(dayCounts).sort((a,b)=>b[1]-a[1]).slice(0,2).map(e=>e[0]);

      // Activity feed
      const feed = sessions.slice(0,8).map(s => ({
        type: 'session', subject: s.subject || 'Pembelajaran', topics: [], minutes: Math.round((s.duration_seconds||0)/60), at: s.started_at, completed: s.completed,
      }));

      // Alerts
      const alerts = [];
      const lastAct = sessions[0]?.started_at || quizzes[0]?.created_at;
      if (lastAct) {
        const daysInactive = Math.floor((Date.now()-new Date(lastAct))/86400000);
        if (daysInactive >= 3) alerts.push({ severity: 'warning', message: `${child.name} tidak belajar selama ${daysInactive} hari. Galakkan mereka membuka app.` });
      } else {
        alerts.push({ severity: 'info', message: `${child.name} belum memulakan pelajaran. Dorong mereka untuk mula hari ini!` });
      }
      if (daysRemaining < 60) alerts.push({ severity: 'danger', message: `SPM tinggal ${daysRemaining} hari lagi! Tingkatkan usaha.` });

      // Recommendations
      const recs = [];
      if (completedLessons === 0) recs.push('Mulakan pelajaran pertama hari ini â€” perjalanan 1000 batu bermula dengan satu langkah.');
      if (subjectPerformance[0]?.weakest_concepts?.length) recs.push(`Ulang kaji topik: ${subjectPerformance[0].weakest_concepts.join(', ')}`);
      recs.push('Pastikan waktu belajar konsisten setiap hari â€” walaupun 20 minit sudah memadai.');

      return {
        name: child.name || 'Pelajar',
        student_code: child.learnova_id || child.id?.substring(0,8),
        form_level: child.form_level || 5,
        is_active_now: isActiveNow,
        subjects: child.selected_subjects || child.active_subjects || [],
        streak,
        enrolled_at: child.created_at?.substring(0,10),
        spm_countdown: { days_remaining: daysRemaining, projected_coverage_pct: projectedCoverage },
        alerts,
        subject_performance: subjectPerformance,
        learnova_comparison: {},
        behaviour: { peak_study_hour: peakHour, avg_session_minutes: avgSessionMins, most_reviewed_topics: [], productive_days: productiveDays },
        activity_feed: feed,
        recommendations: recs,
        wellbeing: { confidence_trend: 'stable', mastery_avg: projectedCoverage, low_mastery_topics: subjectPerformance[0]?.weakest_concepts || [] },
      };
    }));

    res.json({ parent_name: parent?.name || 'Ibu Bapa', children, pending_count: 0 });
  } catch (err) { console.error('Parent dashboard:', err); res.status(500).json({ error: err.message }); }
});

app.post('/api/parent/sponsor', authParent, async (req, res) => {
  try {
    const { amount_myr, spots, message } = req.body;
    if (!amount_myr || !spots) return res.status(400).json({ error: 'Amount and spots required' });
    const { data: sponsorship } = await supabase.from('sponsorships').insert([{ parent_id: req.user.parent_id, amount_myr, spots_total: spots, spots_remaining: spots, message: message || 'A parent is sponsoring your education. Pay it forward!', is_active: true }]).select();
    const codes = Array.from({ length: spots }, () => ({ sponsorship_id: sponsorship[0].id, code: 'LRN-' + Math.random().toString(36).substring(2, 8).toUpperCase(), is_redeemed: false }));
    await supabase.from('redemption_codes').insert(codes);
    const wa = encodeURIComponent(`Learnova Scholarship!\nYou've been sponsored to learn on Learnova.\nYour codes:\n${codes.map(c => c.code).join('\n')}\nRedeem: https://dynamic-tulumba-f9149e.netlify.app`);
    res.json({ sponsorship_id: sponsorship[0].id, codes: codes.map(c => c.code), whatsapp_share: `https://wa.me/?text=${wa}`, message: `${spots} codes generated` });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/redeem', async (req, res) => {
  try {
    const { code, student_id } = req.body;
    if (!code) return res.status(400).json({ error: 'Code required' });
    const { data: r } = await supabase.from('redemption_codes').select('*,sponsorships(spots_remaining)').eq('code', code.toUpperCase()).maybeSingle();
    if (!r) return res.status(404).json({ error: 'Invalid code' });
    if (r.is_redeemed) return res.status(400).json({ error: 'Code already used' });
    await supabase.from('redemption_codes').update({ is_redeemed: true, redeemed_by: student_id, redeemed_at: new Date() }).eq('id', r.id);
    await supabase.from('sponsorships').update({ spots_remaining: r.sponsorships.spots_remaining - 1 }).eq('id', r.sponsorship_id);
    res.json({ success: true, message: 'Sponsorship redeemed! Welcome to Learnova.' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// â”€â”€ LEADERBOARD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.get('/api/leaderboard', async (req, res) => {
  try {
    const { data: results } = await supabase.from('quiz_results').select('student_id, percentage, students(name)');
    const ss = {};
    (results || []).forEach(r => { if (!ss[r.student_id]) ss[r.student_id] = { name: r.students?.name || 'Student', total: 0, count: 0 }; ss[r.student_id].total += r.percentage; ss[r.student_id].count++; });
    const board = Object.entries(ss).map(([id, s]) => ({ student_id: id, name: s.name, avgScore: Math.round(s.total / s.count), quizzes: s.count })).sort((a, b) => b.avgScore - a.avgScore).slice(0, 50).map((s, i) => {
      const rank = i + 1; let tier = 'Bronze';
      if (rank <= 3) tier = 'Diamond'; else if (rank <= 10) tier = 'Platinum'; else if (rank <= 25) tier = 'Gold'; else if (rank <= 50) tier = 'Silver';
      return { ...s, rank, tier };
    });
    res.json({ leaderboard: board, total: Object.keys(ss).length });
  } catch (err) { res.status(500).json({ error: err.message }); }
});


// â”€â”€ PRICING â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.get('/api/pricing', async (req, res) => {
  try {
    const { data } = await supabase.from('subject_pricing').select('*').eq('is_active', true).order('subject');
    res.json({ pricing: data || [] });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// â”€â”€ SUBSCRIPTIONS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.get('/api/student/subscriptions', authStudent, async (req, res) => {
  try {
    const { data } = await supabase.from('subscriptions').select('*').eq('student_id', req.user.student_id).eq('status', 'active').gt('expires_at', new Date().toISOString());
    res.json({ subscriptions: data || [] });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/student/subscribe', authStudent, async (req, res) => {
  try {
    const { subject, plan = 'monthly', qr_type = 'duitnow' } = req.body;
    if (!subject) return res.status(400).json({ error: 'Subject required' });
    const prices = { monthly: 40, yearly: 400 };
    const amount = prices[plan] || 40;
    const refCode = 'LRN-' + Math.random().toString(36).substring(2, 8).toUpperCase();
    await supabase.from('payment_requests').insert([{ student_id: req.user.student_id, subject, amount, plan, qr_type, reference_code: refCode, status: 'pending' }]);
    const waText = encodeURIComponent(`Hi Learnova! I paid for ${subject} (${plan}). Ref: ${refCode}. Amount: RM${amount}`);
    res.json({ reference_code: refCode, amount, subject, plan, qr_type, whatsapp_confirm: `https://wa.me/601XXXXXXXXX?text=${waText}`, instructions: `Pay RM${amount} via ${qr_type.toUpperCase()}. Use reference: ${refCode} in payment description.` });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/student/access/:subject', authStudent, async (req, res) => {
  try {
    const { data } = await supabase.from('subscriptions').select('*').eq('student_id', req.user.student_id).eq('subject', req.params.subject).eq('status', 'active').gt('expires_at', new Date().toISOString()).single();
    res.json({ has_access: !!data, subscription: data || null });
  } catch (err) { res.json({ has_access: false }); }
});

app.post('/api/admin/verify-payment', async (req, res) => {
  try {
    const { reference_code, admin_key } = req.body;
    if (!process.env.ADMIN_KEY || admin_key !== process.env.ADMIN_KEY) return res.status(403).json({ error: 'Unauthorized' });
    const { data: request } = await supabase.from('payment_requests').select('*').eq('reference_code', reference_code).single();
    if (!request) return res.status(404).json({ error: 'Payment request not found' });
    const expiresAt = new Date();
    if (request.plan === 'yearly') expiresAt.setFullYear(expiresAt.getFullYear() + 1);
    else expiresAt.setMonth(expiresAt.getMonth() + 1);
    await supabase.from('subscriptions').insert([{ student_id: request.student_id, subject: request.subject, plan: request.plan, amount_paid: request.amount, payment_method: request.qr_type, payment_reference: reference_code, status: 'active', expires_at: expiresAt.toISOString(), verified_at: new Date().toISOString() }]);
    await supabase.from('payment_requests').update({ status: 'verified', verified_at: new Date().toISOString() }).eq('reference_code', reference_code);
    res.json({ success: true, message: `Subscription activated for ${request.subject}` });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// â”€â”€ SPONSORSHIP â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.post('/api/parent/create-sponsorship', authParent, async (req, res) => {
  try {
    const { subject, show_progress = false, qr_type = 'duitnow' } = req.body;
    if (!subject) return res.status(400).json({ error: 'Subject required' });
    const amount = 480;
    const refCode = 'SPO-' + Math.random().toString(36).substring(2, 8).toUpperCase();
    const accessCode = Math.random().toString(36).substring(2, 10).toUpperCase();
    await supabase.from('sponsorship_seats').insert([{ sponsor_parent_id: req.user.parent_id, subject, amount_paid: amount, payment_reference: refCode, payment_method: qr_type, show_progress_to_sponsor: show_progress, access_code: accessCode, status: 'available' }]);
    const shareLink = `https://learnovamy-hub.github.io/Learnova/?sponsor=${accessCode}`;
    const waText = encodeURIComponent(`You have been sponsored to learn ${subject} on Learnova for FREE!

Claim your access here:
${shareLink}

Access Code: ${accessCode}

Learnova - AI-Powered SPM Tutoring`);
    res.json({ access_code: accessCode, share_link: shareLink, whatsapp_share: `https://wa.me/?text=${waText}`, amount, subject, reference_code: refCode, instructions: `Pay RM${amount} via ${qr_type.toUpperCase()} with reference: ${refCode}. Share the link with the student you want to sponsor.` });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/api/student/claim-sponsorship', authStudent, async (req, res) => {
  try {
    const { access_code } = req.body;
    if (!access_code) return res.status(400).json({ error: 'Access code required' });
    const { data: seat } = await supabase.from('sponsorship_seats').select('*').eq('access_code', access_code.toUpperCase()).eq('status', 'available').single();
    if (!seat) return res.status(404).json({ error: 'Invalid or already claimed code' });
    const expiresAt = new Date(); expiresAt.setFullYear(expiresAt.getFullYear() + 1);
    await supabase.from('subscriptions').insert([{ student_id: req.user.student_id, subject: seat.subject, plan: 'yearly', amount_paid: 0, payment_method: 'sponsored', status: 'active', sponsored_by: seat.sponsor_parent_id, expires_at: expiresAt.toISOString(), verified_at: new Date().toISOString() }]);
    await supabase.from('sponsorship_seats').update({ status: 'claimed', student_id: req.user.student_id, claimed_at: new Date().toISOString() }).eq('id', seat.id);
    res.json({ success: true, subject: seat.subject, message: `Welcome! You now have access to ${seat.subject} sponsored by a generous parent.` });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// â”€â”€ TEACHER PROFILE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.post('/api/teacher/profile', authTeacher, async (req, res) => {
  try {
    const { school, subjects, years_experience, qualifications, teaching_philosophy } = req.body;
    const { data, error } = await supabase.from('teacher_profiles').upsert([{ teacher_id: req.user.teacher_id, school, subjects: subjects || [], years_experience: years_experience || 0, qualifications, teaching_philosophy, onboarding_completed: true }], { onConflict: 'teacher_id' }).select().single();
    if (error) throw error;
    res.json({ success: true, profile: data });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/teacher/profile', authTeacher, async (req, res) => {
  try {
    const { data } = await supabase.from('teacher_profiles').select('*').eq('teacher_id', req.user.teacher_id).single();
    res.json({ profile: data || null, onboarding_completed: data?.onboarding_completed || false });
  } catch (err) { res.json({ profile: null, onboarding_completed: false }); }
});

app.get('/api/teacher/dashboard', authTeacher, async (req, res) => {
  try {
    const { data: lessons } = await supabase.from('lessons').select('id, subject, is_published').eq('teacher_id', req.user.teacher_id);
    const { data: quizzes } = await supabase.from('quizzes').select('id').eq('teacher_id', req.user.teacher_id);
    const { data: profile } = await supabase.from('teacher_profiles').select('*').eq('teacher_id', req.user.teacher_id).single();
    res.json({ lessons_uploaded: lessons?.length || 0, lessons_published: lessons?.filter(l => l.is_published)?.length || 0, lessons_pending: lessons?.filter(l => !l.is_published)?.length || 0, quizzes_created: quizzes?.length || 0, subjects: profile?.subjects || [], school: profile?.school || '', onboarding_completed: profile?.onboarding_completed || false });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// â”€â”€ PARENT-CHILD LINK â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.post('/api/parent/link-child', async (req, res) => {
  try {
    const { parent_email, student_id } = req.body;
    if (!parent_email || !student_id) return res.status(400).json({ error: 'parent_email and student_id required' });
    const { data: parent } = await supabase.from('parents').select('id').eq('email', parent_email.toLowerCase()).single();
    if (!parent) return res.json({ linked: false, message: 'Parent account not found' });
    await supabase.from('parent_child_links').upsert([{ parent_id: parent.id, student_id }], { onConflict: 'parent_id,student_id' });
    res.json({ linked: true, message: 'Parent linked successfully' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});
app.use('/api/learn', learningEngineRouter);

function normalizeTtsInput(text, lang = 'bm') {
  return cleanTextForTTS(text, lang, SYMBOL_MAP);
}

app.get('/api/symbols/lookup', async (req, res) => {
  const { symbol, context, lang } = req.query;
  if (!symbol) return res.status(400).json({ error: 'symbol required' });
  let query = supabase.from('symbol_dictionary').select('*').eq('symbol', symbol);
  if (context) query = query.eq('context', context);
  const { data } = await query.limit(1).single();
  if (!data) return res.json({ found: false });
  res.json({
    found: true,
    symbol: data.symbol,
    spoken: lang === 'en' ? data.spoken_en : lang === 'zh' ? data.spoken_zh : data.spoken_bm,
    meaning: lang === 'en' ? data.meaning_en : data.meaning_bm,
    example: data.example_usage,
  });
});

app.post('/api/admin/reload-symbols', async (req, res) => {
  try {
    await loadSymbolDictionary();
    const count = SYMBOL_MAP ? (SYMBOL_MAP.bm || []).length : 0;
    console.log(`Symbol dictionary reloaded: ${count} entries`);
    res.json({ reloaded: true, count });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/tts', async (req, res) => {
  try {
    const { text, voice = 'nova', language = 'bm' } = req.body;
    if (!text) return res.status(400).json({ error: 'text required' });
    if (!process.env.OPENAI_API_KEY) {
      console.error('TTS: OPENAI_API_KEY is not set');
      return res.status(500).json({ error: 'TTS unavailable: API key not configured' });
    }
    const clean = normalizeTtsInput(text, language).slice(0, 4000);
    if (!clean) return res.status(400).json({ error: 'text empty after normalization' });
    const r = await fetch('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'tts-1-hd',
        input: clean,
        voice,
        speed: 1.0,
        response_format: 'mp3',
      }),
    });
    if (!r.ok) {
      const errText = await r.text();
      console.error(`TTS OpenAI error ${r.status}:`, errText);
      return res.status(502).json({ error: 'TTS failed', status: r.status, detail: errText });
    }
    const buf = Buffer.from(await r.arrayBuffer());
    res.set('Content-Type', 'audio/mpeg');
    res.set('Cache-Control', 'no-cache');
    res.send(buf);
  } catch (e) {
    console.error('TTS exception:', e.message);
    res.status(500).json({ error: e.message });
  }
});


// ── TTS chunking helper (avoids quality degradation on long texts) ────────────
// Splits text at sentence boundaries into ~800-char chunks, generates each
// separately, then concatenates the CBR MP3 buffers (safe for OpenAI TTS output).
async function openAITTSChunked(text, voice = 'nova') {
  const MAX_CHUNK = 800;
  const chunks = [];
  if (text.length <= MAX_CHUNK) {
    chunks.push(text);
  } else {
    const sentences = text.split(/(?<=[.!?])\s+/);
    let current = '';
    for (const sentence of sentences) {
      if (current && (current + ' ' + sentence).length > MAX_CHUNK) {
        chunks.push(current.trim());
        current = sentence;
      } else {
        current = current ? current + ' ' + sentence : sentence;
      }
    }
    if (current.trim()) chunks.push(current.trim());
  }
  console.log(`TTS: ${chunks.length} chunk(s) for ${text.length} chars`);

  const buffers = [];
  for (const chunk of chunks) {
    const r = await fetch('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ model: 'tts-1-hd', input: chunk, voice, speed: 1.0, response_format: 'mp3' }),
    });
    if (!r.ok) {
      const e = await r.text();
      throw new Error(`OpenAI TTS chunk failed: ${e}`);
    }
    buffers.push(Buffer.from(await r.arrayBuffer()));
  }
  return buffers.length === 1 ? buffers[0] : Buffer.concat(buffers);
}

// ── ON-DEMAND AUDIO WITH PERMANENT CACHE ─────────────────────────────────────
// Generates audio on first student request, uploads to cPanel, caches URL in Supabase.
// Subsequent requests serve the cached URL instantly (no API call).

async function buildLessonText(lesson) {
  const parts = [];
  if (lesson.lesson_title) parts.push(lesson.lesson_title + '.');
  if (lesson.concept_explanation) parts.push(lesson.concept_explanation);
  if (lesson.worked_example) parts.push('Contoh: ' + lesson.worked_example);
  if (lesson.exam_technique) parts.push(lesson.exam_technique);
  return parts.join(' ').replace(/\s+/g, ' ').trim().slice(0, 4000);
}

async function uploadAudioToStorage(buffer, filename) {
  // Upload MP3 to cPanel via FTP, return public URL
  const { Client } = await import('basic-ftp');
  const client = new Client();
  try {
    await client.access({
      host: 'learnova.optimus.com.my',
      user: 'optimus',
      password: 'sa@yHLVwmHMN',
      port: 21,
      secure: false,
    });
    const remotePath = `/home/optimus/public_html/Learnova/audio/${filename}`;
    const { Readable } = await import('stream');
    const readable = Readable.from(buffer);
    await client.uploadFrom(readable, remotePath);
    return `https://learnova.optimus.com.my/Learnova/audio/${filename}`;
  } finally {
    client.close();
  }
}

app.get('/api/audio/:lessonId', async (req, res) => {
  try {
    const { lessonId } = req.params;
    const lang = req.query.lang || 'bm';
    const audioCol = AUDIO_COLUMN[lang] || 'audio_url';

    // Check cache in Supabase
    const { data: lesson, error } = await supabase
      .from('structured_lessons')
      .select(`id, lesson_title, concept_explanation, worked_example, key_formula, ${audioCol}`)
      .eq('id', lessonId)
      .single();

    if (error || !lesson) return res.status(404).json({ error: 'Lesson not found' });

    const cachedUrl = lesson[audioCol];
    if (cachedUrl && cachedUrl.length > 0) {
      return res.json({ url: cachedUrl, cached: true });
    }

    // Generate audio
    const text = await buildLessonText(lesson);
    if (!text) return res.status(400).json({ error: 'No lesson text to generate audio from' });

    const langConfig = TEACHING_LANGUAGES[lang] || TEACHING_LANGUAGES['bm'];
    let audioBuffer;

    if (langConfig.ttsEngine === 'kokoro') {
      // DeepInfra serverless Kokoro API
      if (!process.env.DEEPINFRA_API_KEY) {
        return res.status(503).json({ error: 'DEEPINFRA_API_KEY not configured' });
      }
      const deepRes = await fetch('https://api.deepinfra.com/v1/inference/hexgrad/Kokoro-82M', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${process.env.DEEPINFRA_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          text: cleanTextForTTS(text, lang, SYMBOL_MAP),
          voice: langConfig.ttsVoice,
          output_format: 'mp3',
        }),
      });
      if (!deepRes.ok) {
        const e = await deepRes.text();
        console.error('DeepInfra error:', e);
        return res.status(502).json({ error: 'DeepInfra TTS failed', detail: e });
      }
      const deepJson = await deepRes.json();
      const b64 = deepJson.audio || deepJson.audio_url;
      if (!b64) return res.status(502).json({ error: 'No audio in DeepInfra response' });
      audioBuffer = Buffer.from(b64.replace(/^data:audio\/[^;]+;base64,/, ''), 'base64');
    } else {
      // OpenAI TTS (bm / id) — tts-1-hd, chunked for quality
      if (!process.env.OPENAI_API_KEY) {
        return res.status(503).json({ error: 'OPENAI_API_KEY not configured' });
      }
      const cleanedText = cleanTextForTTS(text, lang, SYMBOL_MAP);
      audioBuffer = await openAITTSChunked(cleanedText, langConfig.ttsVoice);
    }

    // Upload to cPanel
    const filename = `${lessonId}_${lang}.mp3`;
    const publicUrl = await uploadAudioToStorage(audioBuffer, filename);

    // Save URL back to Supabase
    await supabase.from('structured_lessons')
      .update({ [audioCol]: publicUrl })
      .eq('id', lessonId);

    return res.json({ url: publicUrl, cached: false });
  } catch (e) {
    console.error('/api/audio error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// -- HELP SYSTEM ----------------------------------------------
app.post('/api/help/log', async (req, res) => {
  try {
    const { event_type, category, details, timestamp } = req.body;
    await supabase.from('help_logs').insert({ event_type, category, details, created_at: timestamp || new Date().toISOString() });
    res.json({ ok: true });
  } catch (e) { res.json({ ok: false }); }
});

app.post('/api/help/chat', async (req, res) => {
  try {
    const { message, category, history } = req.body;
    const { data: cached } = await supabase.from('faq_cache').select('answer').eq('subject', 'help').ilike('question', `%${message.substring(0,30)}%`).limit(1);
    if (cached && cached.length > 0) return res.json({ reply: cached[0].answer, source: 'cache' });
    const claudeRes = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001', max_tokens: 300,
      system: 'You are Nova, Learnova help assistant for Malaysian SPM students. Answer only app-related questions. Be warm and concise. If unsure say: I will connect you with our support team.',
      messages: [...(history||[]).slice(-4).map(h => ({ role: h.role, content: h.content })), { role: 'user', content: message }],
    });
    const reply = claudeRes.content[0].text;
    await supabase.from('help_logs').insert({ event_type: 'ai_response', category, details: `Q: ${message} | A: ${reply}` });
    res.json({ reply, source: 'claude' });
  } catch (e) { res.status(500).json({ reply: 'I am having trouble right now. Please contact support.', error: e.message }); }
});

app.post('/api/help/ticket', async (req, res) => {
  try {
    const { category, issue, chat_history } = req.body;
    const { data } = await supabase.from('help_tickets').insert({ category, issue, chat_history: chat_history || [], status: 'open' }).select().single();
    res.json({ ok: true, ticket_id: data?.id });
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

// -- TTS (duplicate removed â€” active route is above) -----------

// -- TUTOR TOPICS ----------------------------------------------
app.get('/api/tutor/topics', async (req, res) => {
  try {
    const { subject: rawSubject } = req.query;
    const subject = normalizeSubject(rawSubject);
    const cols = 'id, title, topic, subtopic, form_level, introduction, summary';

    // 1. status field (lessons created via setup scripts)
    const { data } = await supabase.from('lessons').select(cols)
      .eq('subject', subject).in('status', ['published', 'active']).order('topic');
    if (data && data.length > 0) return res.json({ topics: data });

    // 2. is_published boolean (lessons created via teacher portal)
    const { data: pub } = await supabase.from('lessons').select(cols)
      .eq('subject', subject).eq('is_published', true).order('topic');
    if (pub && pub.length > 0) return res.json({ topics: pub });

    // 3. Fallback: concept_chunks (topics with content even if no lesson entry)
    const { data: cc } = await supabase.from('concept_chunks')
      .select('topic').eq('subject', subject).order('topic');
    if (cc && cc.length > 0) {
      const unique = [...new Map(cc.map(r => [r.topic, r])).values()];
      return res.json({ topics: unique.map(r => ({ id: null, title: r.topic, topic: r.topic })) });
    }

    // 4. pregen_status fallback
    const { data: pg } = await supabase.from('pregen_status')
      .select('topic').eq('subject', subject).eq('status', 'complete')
      .gt('questions_generated', 0).order('topic');
    if (pg && pg.length > 0) {
      return res.json({ topics: pg.map(p => ({ id: null, title: p.topic, topic: p.topic })) });
    }

    res.json({ topics: [] });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// Strip JSON artifacts from a reply string â€” catches double-encoding where
// Claude wraps its reply text inside another JSON object
function safeReply(text) {
  if (!text || typeof text !== 'string') return text || '';
  const trimmed = text.trim();
  if (trimmed.startsWith('{')) {
    // Try full JSON parse first (happy path)
    try {
      const inner = JSON.parse(trimmed);
      const extracted = inner.reply || inner.answer || inner.content || inner.text || inner.message;
      if (extracted && typeof extracted === 'string') return extracted;
    } catch {}
    // JSON parse failed (truncated response) â€” extract "reply" value via regex
    const replyMatch = trimmed.match(/"reply"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    if (replyMatch) {
      // Re-parse as a JSON string to decode \n, \", etc. properly
      try { return JSON.parse('"' + replyMatch[1] + '"'); } catch {}
      return replyMatch[1].replace(/\\n/g, '\n').replace(/\\t/g, '\t').replace(/\\"/g, '"');
    }
    // Cannot extract anything useful â€” return empty so UI shows the error fallback
    return '';
  }
  return text;
}

// -- TEXTBOOK CONTEXT FETCHER -------------------------------------------
// Returns { text, totalChunks, done } — one concept chunk for the current segment.
// done=true signals topic exhausted; never wraps back to chunk 0.
async function buildTextbookContext(subject, topic, segment = 0) {
  if (!subject || !topic) return { text: '', totalChunks: 0, done: true };
  try {
    const topicKeyword = topic.split(' ').slice(0, 4).join(' ');
    const { data: chunks, error } = await supabase
      .from('concept_chunks')
      .select('concept_title, concept_explanation, worked_example, common_mistakes, keywords')
      .eq('subject', subject)
      .ilike('topic', `%${topicKeyword}%`)
      .order('difficulty_level', { ascending: true })
      .limit(50);
    const fmt = c =>
      `Tajuk: ${c.concept_title}\n${c.concept_explanation}${c.worked_example ? `\nContoh: ${c.worked_example}` : ''}${c.common_mistakes ? `\nKesilapan lazim: ${c.common_mistakes}` : ''}`;
    if (error || !chunks || chunks.length === 0) {
      const { data: fallback } = await supabase
        .from('concept_chunks')
        .select('concept_title, concept_explanation, worked_example, common_mistakes')
        .eq('subject', subject)
        .limit(5);
      if (!fallback || fallback.length === 0) return { text: '', totalChunks: 0, done: true };
      if (segment >= fallback.length) return { text: '', totalChunks: fallback.length, done: true };
      return { text: fmt(fallback[segment]), totalChunks: fallback.length, done: false };
    }
    if (segment >= chunks.length) return { text: '', totalChunks: chunks.length, done: true };
    return { text: fmt(chunks[segment]), totalChunks: chunks.length, done: false };
  } catch (e) {
    console.error('buildTextbookContext error:', e.message);
    return { text: '', totalChunks: 0, done: true };
  }
}

// -- TUTOR FLOW: server-owned phase machine + chip templates --------------
// Replaces the model-emitted JSON envelope. The model now returns plain
// teaching text plus one classify_turn tool call; the server decides
// phase/segment/chips and the client never sees a JSON envelope.

const TUTOR_CLASSIFY_TOOL = {
  name: 'classify_turn',
  description: 'Classify the student turn so the server can drive lesson flow. Call exactly once per response.',
  input_schema: {
    type: 'object',
    properties: {
      student_signal: {
        type: 'string',
        enum: ['correct', 'wrong', 'confused', 'idk', 'off_topic', 'first_turn', 'continue'],
        description: 'How the student responded this turn: correct=right answer; wrong=incorrect; confused=does not understand; idk=said they do not know; off_topic=changed subject; first_turn=opening turn (message was "start"); continue=neutral acknowledgement / asking to continue.'
      },
      ready_for_quiz: {
        type: 'boolean',
        description: 'true only when the student has demonstrated mastery of the current concept AND there are no more concepts left to teach. Otherwise false.'
      }
    },
    required: ['student_signal']
  }
};

function nextPhase(currentPhase, signal, segment, totalChunks, readyForQuiz, topicDone) {
  if (currentPhase === 'intro') return 'teach';
  if (signal === 'wrong' || signal === 'confused' || signal === 'idk') {
    return currentPhase === 'teach' ? 'check' : currentPhase;
  }
  if (signal === 'off_topic') return currentPhase;
  if (currentPhase === 'teach') return 'check';
  if (currentPhase === 'check') {
    if (topicDone || readyForQuiz || (totalChunks > 0 && segment >= totalChunks - 1)) {
      return 'quiz_setup';
    }
    return 'teach';
  }
  if (currentPhase === 'quiz_setup') return 'quiz_answer';
  if (currentPhase === 'quiz_answer') return 'done';
  return currentPhase;
}

function nextSegment(currentPhase, newPhase, currentSegment) {
  // Advance only when moving from check → teach (i.e. starting the next concept).
  if (currentPhase === 'check' && newPhase === 'teach') return currentSegment + 1;
  return currentSegment;
}

function chipsForPhase(phase, isBm, isIndonesian, isBmSubject, isSejarahSubject) {
  if (phase === 'quiz_setup' || phase === 'quiz_answer') return ['A', 'B', 'C', 'D'];
  if (phase === 'done') {
    if (isBmSubject || isSejarahSubject || isBm) return ['Lagi soalan praktis', 'Topik baru', 'Ulang topik ini'];
    if (isIndonesian) return ['Coba soal lagi', 'Topik baru', 'Ulang topik ini'];
    return ['Try more questions', 'New topic', 'Review this topic'];
  }
  if (isBmSubject || isSejarahSubject) return ['Faham! Teruskan.', 'Boleh cerita lebih lanjut?', 'Saya kurang faham bahagian ini.'];
  if (isIndonesian) return ['Oke, lanjut!', 'Bisa kasih contoh lain?', 'Aku belum paham bagian ini.'];
  if (isBm) return ['Faham! Teruskan.', 'Boleh tunjukkan contoh?', 'Saya kurang faham bahagian ini.'];
  return ['I understand, please continue.', 'Can you show an example?', "I'm not sure about this part."];
}

app.post('/api/tutor/session', authStudent, async (req, res) => {
  try {
    const { subject: rawSubject, topic, message, history, phase, segment, language, activeQuestion, question,
            lessonId, lessonContext } = req.body;
    const subject = normalizeSubject(rawSubject);
    const teachingLang = req.body.teaching_language || language || 'bm';
    const curriculum = subject.startsWith('AL-') ? 'ALevel'
      : subject.startsWith('ID-') ? 'Indonesian'
      : 'SPM';
    const isBm = teachingLang === 'bm' || teachingLang === 'ms' || (curriculum === 'SPM' && !teachingLang);
    const isEnglish = curriculum === 'ALevel' || teachingLang === 'en' || subject === 'English' || subject === 'English Literature';
    const isIndonesian = curriculum === 'Indonesian' || teachingLang === 'id';
    const isMandarin = teachingLang === 'zh';
    const isTamil = teachingLang === 'ta';
    const lang = isEnglish ? 'English' : isIndonesian ? 'Bahasa Indonesia' : isMandarin ? 'Chinese' : isTamil ? 'Tamil' : 'Bahasa Malaysia';

    // Fetch ONE concept chunk for the current segment (prevents content dump)
    const { text: textbookContext, totalChunks, done: topicDone } =
      topic ? await buildTextbookContext(subject, topic, parseInt(segment) || 0)
            : { text: '', totalChunks: 0, done: false };

    const isBmSubject = subject === 'MY-BahasaMalaysia' || subject === 'Bahasa Malaysia' || subject === 'Bahasa Melayu' ||
      !!(topic && (topic.includes('Bahasa Malaysia') || topic.includes('Bahasa Melayu')));

    const isSejarahSubject = subject === 'MY-Sejarah' || subject === 'Sejarah' || subject === 'Sejarah Indonesia' ||
      !!(subject && subject.includes('Sejarah'));

    // Language-matched quick-reply suggestions
    const suggestions = (isBmSubject || isSejarahSubject)
      ? ['Faham! Teruskan.', 'Boleh cerita lebih lanjut?', 'Saya kurang faham bahagian ini.']
      : isIndonesian
      ? ['Oke, lanjut!', 'Bisa kasih contoh lain?', 'Aku belum paham bagian ini.']
      : isBm
      ? ['Faham! Teruskan.', 'Boleh tunjukkan contoh?', 'Saya kurang faham bahagian ini.']
      : ['I understand, please continue.', 'Can you show an example?', "I'm not sure about this part."];

    // â”€â”€ Q&A mode: free question, no active topic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (question && !topic) {
      // Check pregen FAQ bank first (covers all subjects, zero API cost)
      const pregenFaq = await pregen.detectAndServeFAQ(
        req.body.country || 'MY', subject || 'General', req.body.topic || '', question
      );
      if (pregenFaq) {
        console.log(`[PreGen] FAQ hit: ${pregenFaq.category}`);
        return res.json({ answer: pregenFaq.answer, example: null, source: 'faq_cache', from_cache: true, related_questions: [] });
      }

      if (!subject || subject.toLowerCase().includes('math')) {
        const faqHit = findBestFAQ(question);
        if (faqHit) {
          return res.json({ answer: faqHit.answer, example: faqHit.example || null, source: 'faq_cache', related_questions: [] });
        }
      }
      const cacheHit = await searchFaqCache(question, subject);
      if (cacheHit) {
        return res.json({ answer: cacheHit.answer, example: null, source: 'faq_cache', related_questions: [] });
      }
      if (!claudeApiKey) {
        return res.json({ answer: "Great question! Ask your teacher or try rephrasing.", source: 'fallback', related_questions: [] });
      }
      const { default: Anthropic } = await import('@anthropic-ai/sdk');
      const anthropic = new Anthropic({ apiKey: claudeApiKey });
      const claudeRes = await anthropic.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 500,
        system: `You are Nova, a warm Malaysian SPM tutor for ${subject || 'General'}. Answer in ${lang}. Be concise and friendly. Respond with valid JSON only: {"answer":"...","example":"...or null","related_questions":["q1","q2","q3"]}`,
        messages: [{ role: 'user', content: question }],
      });
      let parsed;
      try {
        const text = claudeRes.content[0].text.trim();
        const match = text.match(/\{[\s\S]*\}/);
        parsed = JSON.parse(match ? match[0] : text);
      } catch {
        parsed = { answer: safeReply(claudeRes.content[0].text), example: null, related_questions: [] };
      }
      // Ensure answer field is never raw JSON
      if (parsed.answer) parsed.answer = safeReply(parsed.answer);
      if (parsed.reply)  parsed.reply  = safeReply(parsed.reply);
      return res.json({ ...parsed, source: 'claude' });
    }

    // â”€â”€ Pregen: serve FAQ or explanation before calling Claude â”€â”€â”€
    if (topic && message && message !== 'start') {
      const country = req.body.country || 'MY';

      // FAQ check
      const pregenFaq = await pregen.detectAndServeFAQ(country, subject || 'General', topic, message);
      if (pregenFaq) {
        console.log(`[PreGen] Tutor FAQ hit: ${pregenFaq.category}`);
        return res.json({
          reply: safeReply(pregenFaq.answer), source: 'faq_cache', from_cache: true,
          phase, segment: (parseInt(segment) || 0) + 1, isCheckIn: false,
          suggestedResponses: suggestions,
          activeQuestion: null,
        });
      }

      // Explanation type check
      const expType = pregen.detectExplanationType(message);
      if (expType) {
        const prebuilt = await pregen.getExplanation(country, subject || 'General', topic, expType);
        if (prebuilt) {
          console.log(`[PreGen] Explanation hit: ${expType}`);
          return res.json({
            reply: safeReply(prebuilt), source: 'explanation_cache', from_cache: true,
            phase, segment: (parseInt(segment) || 0) + 1, isCheckIn: false,
            suggestedResponses: suggestions,
            activeQuestion: null,
          });
        }
      }
    }

    // â”€â”€ Tutor mode: guided lesson with topic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (!claudeApiKey) {
      return res.json({
        reply: isBm ? "Maaf, jurulatih AI tidak tersedia sekarang. Sila cuba lagi." : "Sorry, the AI tutor is not available right now. Please try again later.",
        phase: phase || 'intro', segment: (parseInt(segment) || 0) + 1,
        suggestedResponses: suggestions,
        activeQuestion: null, source: 'fallback', isCheckIn: false,
      });
    }
    const { default: Anthropic } = await import('@anthropic-ai/sdk');
    const anthropic = new Anthropic({ apiKey: claudeApiKey });
    const currentPhase = phase || 'intro';
    const currentSegment = parseInt(segment) || 0;
    const personalityMode = req.body.personality || 'balanced';
    const isConfused = req.body.isConfused === true || req.body.studentConfused === true ||
      /tak faham|tidak faham|keliru|don'?t (get|understand)|confused|lost|huh\??|no idea|what do you mean|explain again|cara lain/i.test(message || '');

    // â”€â”€ Per-phase token limits (prevent content dumps) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    const phaseTokens = { intro: 500, teach: 480, check: 380, quiz_setup: 380, quiz_answer: 380, done: 380 };
    const maxTokens = phaseTokens[currentPhase] || 420;

    // â”€â”€ Personality styles â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    const personalityStyles = {
      friendly:  'Warm, fun, lots of encouragement, uses relatable analogies. Celebrate every correct answer. Use casual Malaysian phrases occasionally.',
      balanced:  'Professional yet approachable. Clear pacing. Steady encouragement. Neither too strict nor too casual.',
      strict:    'High expectations, minimal small talk, demands precise answers. Still respectful but very focused.',
      military:  'Very direct, drills concepts with repetition, expects exact answers. No wasted words. Discipline-first.'
    };
    const personalityDesc = personalityStyles[personalityMode] || personalityStyles.balanced;

    // â”€â”€ Phase-specific teaching instructions (HARDCODED PEDAGOGY) â”€â”€
    const phaseInstructions = {
      intro: `=== INTRODUCTION ===
This is the very first turn of the lesson. Do ALL of these in one short message, nothing more:
1. Write ONE curiosity hook -- a surprising fact, relatable scenario, or real-life connection to "${topic}" in ${subject || 'Mathematics'} (1-2 sentences only).
2. Ask ONE activation question to find out what the student already knows (e.g. "Before we start, what do you already know about this?").
Do NOT explain the concept yet.
Keep it under 80 words.`,

      teach: `=== TEACHING (Concept ${currentSegment + 1}) ===
ONE concept per response -- no more:
1. Introduce ONE sub-concept or ONE step of "${topic}" -- not the whole topic.
2. Show ONE worked example, step-by-step with working shown clearly.
3. Explain WHY this step works and WHEN to use it.
4. Name ONE common mistake SPM students make here.
5. End with a direct comprehension question to the student (e.g. "Now, can you tell me WHY we do step 2?" or "What do you think comes next?").
Do NOT explain the next concept. Do NOT summarise the whole topic.
Keep reply under 160 words.`,

      check: `=== CHECKING UNDERSTANDING ===
The student has just responded. Assess their understanding and reply accordingly. The server decides what comes next based on the classify_turn tool you call.

IF STUDENT ANSWERED CORRECTLY:
- Praise in ONE sentence (genuine, not hollow).
- Either lead into the next concept of "${topic}" or, if all concepts have been taught, into exam practice. Your reply should flow naturally into whichever it is.

IF STUDENT ANSWERED WRONGLY OR IS CONFUSED:
- DO NOT give the answer yet.
- Give ONE specific hint that points them in the right direction.
- Ask a simpler guiding question ("What if I told you that...?").

IF STUDENT SAYS "I DON'T KNOW":
- Ask an even simpler scaffolding question first.
- Break it into the smallest possible step.

Keep reply under 130 words.`,

      quiz_setup: `=== EXAM PRACTICE ===
Write ONE SPM-style question on "${topic}" in ${subject || 'Mathematics'}:
1. Tell student: "Let's try an SPM-style question. Take your time and think before answering."
2. Write the question text.
3. For MCQ: list options A, B, C, D each on its own line. Do NOT reveal the correct answer -- the student must work it out and reply with A/B/C/D.
4. The question should match the difficulty and format of actual SPM past-year papers.
5. Add an exam tip: mention which SPM paper this type appears in (Paper 1/Paper 2).
Keep reply under 200 words.`,

      quiz_answer: `=== QUIZ FEEDBACK ===
The student has answered the question. Assess their answer in your reply:

IF CORRECT:
- Confirm it enthusiastically.
- Explain WHY it is correct step-by-step (SPM marking-scheme style -- show how marks are awarded).

IF WRONG:
- DO NOT reveal the answer immediately.
- Ask: "Interesting choice -- what was your thinking for that option?"
- After they explain: guide them to see the error.
- Only reveal correct answer + full working after student attempts to reason.

Keep reply under 130 words.`,

      done: `=== WRAP-UP ===
1. Summarise "${topic}" in EXACTLY 3 bullet points using exam-ready language.
2. Give ONE specific SPM exam tip for this topic (e.g. "In Paper 2 Section B, always show full working for...").
3. Ask: "Would you like to try more practice questions, revisit any part, or move to a new topic?"
Keep reply under 120 words.`
    };

    const currentPhaseInstructions = isConfused
      ? `=== CONFUSION DETECTED -- OVERRIDE NORMAL FLOW ===
The student is confused. Drop everything else and do this:
1. Acknowledge confusion warmly (1 sentence).
2. Re-explain the LAST concept using a COMPLETELY DIFFERENT method:
   - If you used formula: now use a real-life analogy.
   - If you used steps: now use a visual/diagram description.
   - If abstract: now use numbers first, then generalise.
3. Ask a simpler, more guided question than before.
Keep reply under 130 words.`
      : (phaseInstructions[currentPhase] || phaseInstructions.teach);

    // Mandarin / Tamil: dedicated Nova prompts — return early before BM/EN/ID logic
    if (isMandarin || isTamil) {
      const langPrompt = isMandarin
        ? NOVA_ZH_PROMPT + `\n\n正在教的科目：${subject || 'Mathematics'}${topic ? ` — ${topic}` : ''}`
        : NOVA_TA_PROMPT + `\n\nபடிக்கும் பாடம்: ${subject || 'Mathematics'}${topic ? ` — ${topic}` : ''}`;
      const langMessages = await anthropic.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 1024,
        system: langPrompt,
        messages: history && history.length > 0
          ? [...history.map(m => ({ role: m.role, content: m.content })),
             { role: 'user', content: message }]
          : [{ role: 'user', content: message }],
      });
      const langReply = formatNovaResponse(langMessages.content[0]?.text);
      return res.json({ reply: langReply, subject, topic });
    }

    const novaIdentity = isEnglish
      ? `You are Nova, Learnova's personal A-Level learning assistant. You are like a brilliant senior student who genuinely enjoys helping others understand deeply â€” not just memorise. You teach with academic rigour appropriate for Cambridge A-Level, but in an encouraging, supportive way.`
      : isIndonesian
      ? `Kamu adalah Nova, asisten belajar pribadi Learnova. Kamu kayak kakak/mas senior yang pinter, sabar, dan suka bantu adik-adik ngerti pelajaran dengan bener â€” bukan cuma hafalan. Kamu ngajar pakai Bahasa Indonesia yang natural dan friendly.`
      : `Kamu adalah Nova, pembantu belajar peribadi Learnova. Kamu macam kakak atau abang senior yang bijak, sabar, dan suka bantu pelajar faham benda dengan betul â€” bukan sekadar hafal. Kamu ajar dalam Bahasa Malaysia yang natural dan mesra.`;

    let systemPrompt = `${isEnglish ? `ABSOLUTE RULE #1 â€” MANDATORY EVERY RESPONSE:
You MUST end EVERY single response with one open question that requires the student to TYPE or SPEAK a real answer.
This rule cannot be ignored under any circumstance.
The question must NOT be answerable with yes or no.
The question must relate directly to what you just explained.
CORRECT examples: "Can you explain that back in your own words?", "If this value changed to X, what would happen?", "Show me your working for this step.", "Give me another example you can think of."
WRONG examples (never use): "Do you understand?", "Shall we continue?", "Any questions?" â€” these are yes/no and are forbidden.`
: isIndonesian ? `PERATURAN MUTLAK #1 â€” WAJIB DI SETIAP RESPONS:
Kamu WAJIB mengakhiri SETIAP respons dengan satu pertanyaan terbuka yang mengharuskan siswa mengetik atau berbicara jawaban nyata.
Aturan ini tidak boleh diabaikan dalam keadaan apapun.
Pertanyaan tidak boleh dijawab dengan ya atau tidak.
Pertanyaan harus berkaitan langsung dengan apa yang baru saja kamu jelaskan.
Contoh BENAR: "Bisa kamu jelaskan balik dengan kata-katamu sendiri?", "Kalau nilai ini berubah jadi X, apa yang terjadi?", "Tunjukkan penghitunganmu untuk langkah ini.", "Beri satu contoh lain yang kamu pikirkan."
Contoh SALAH (jangan pakai): "Paham?", "Lanjut?", "Ada pertanyaan?" â€” ini ya/tidak dan dilarang.`
: `PERATURAN MUTLAK #1 â€” WAJIB DALAM SETIAP RESPONS:
Kamu WAJIB mengakhiri SETIAP respons dengan satu soalan terbuka yang memerlukan pelajar menaip atau bertutur jawapan.
Ini tidak boleh diabaikan walau apa pun.
Soalan TIDAK boleh dijawab dengan ya atau tidak.
Soalan mesti berkaitan dengan apa yang baru diterangkan.
Contoh soalan yang BETUL: 'Cuba kamu terangkan balik dalam ayat sendiri?', 'Kalau nilai ini berubah kepada X, apa berlaku?', 'Tunjukkan pengiraan kamu untuk soalan ini.', 'Bagi satu contoh lain yang kamu fikir.'
Soalan yang SALAH (jangan guna): 'Faham?', 'Nak teruskan?', 'Ada soalan?' â€” ini soalan ya/tidak dan dilarang.`}

ABSOLUTE RULE â€” YOU ARE TEACHING: ${subject || 'Mathematics'} â€” ${topic}
You must ONLY teach content related to "${topic}" in ${subject || 'Mathematics'}.
NEVER introduce a new topic. NEVER ask "What do you want to learn?". NEVER restart the session.
You are mid-session. The student has already chosen their topic.

${novaIdentity}

==================================================
WHO YOU ARE â€” NON-NEGOTIABLE
==================================================
You are NOT a chatbot. You are NOT ChatGPT. You are NOT an answer generator.
${isEnglish
  ? 'You behave like an experienced Cambridge A-Level tutor. Patient, rigorous, step-by-step.'
  : isIndonesian
  ? 'Kamu berperilaku seperti kakak/tutor senior yang sabar dan sistematis. Natural, hangat, terstruktur.'
  : 'Kamu bertindak seperti cikgu tuisyen Malaysia yang berpengalaman. Sabar, berstruktur, langkah demi langkah.'}

Teaching personality: ${personalityDesc}
Subject: ${subject || 'Mathematics'}
Topic: ${topic}
Respond in: ${lang}
${textbookContext ? `
==================================================
KONTEKS DARI BUKU TEKS (gunakan untuk mengajar)
==================================================
${textbookContext}

${isEnglish ? 'Use the above textbook content to teach. Do not say "according to the textbook" â€” teach naturally as if you know this yourself.' : isIndonesian ? 'Gunakan konten buku teks di atas untuk mengajar. Jangan bilang "menurut buku teks" â€” ajar secara natural seolah kamu sendiri yang tahu.' : 'Gunakan konteks buku teks di atas untuk mengajar. Jangan sebut "mengikut buku teks" â€” ajar secara natural seolah-olah kamu sendiri yang tahu benda ni.'}
==================================================` : ''}

==================================================
CORE LEARNOVA TEACHING PRINCIPLES â€” ALWAYS ENFORCED
==================================================
1. NEVER dump the full topic explanation in one response. ONE concept per response, then STOP.
2. Always explain WHY a step is used, WHEN to use it, and WHAT mistakes students make.
3. After every teaching segment, ask the student a question. Do not continue until they respond.
4. If student is WRONG: give a hint, not the answer. Make them think first.
5. If student is CONFUSED: switch method entirely. Use analogy, diagram description, or simpler numbers.
6. If student goes off-topic: gently redirect â€” “Let's master this first before moving on.”
7. Match SPM exam format, marking scheme, and Paper 1/Paper 2 expectations.
8. Use Malaysian student-friendly language. BM/Manglish phrases are welcome occasionally.
9. Every response MUST end with a short open question that requires the student to TYPE or SPEAK a real answer â€” not tap a button.
10. UNDERSTANDING > MEMORISATION. THINKING > COPYING. GUIDANCE > ANSWERS.

==================================================
ENDING QUESTION RULES â€” ENFORCED EVERY MESSAGE
==================================================
${isBm ? `Setiap kali kamu selesai menerangkan sesuatu konsep, akhiri dengan soalan pendek yang memerlukan pelajar menaip atau bertutur jawapan mereka.
JANGAN tanya soalan ya/tidak sahaja.
Soalan MESTI berkaitan dengan apa yang baru diterangkan.
Tukar-tukar jenis soalan â€” jangan ulang soalan yang sama setiap mesej.
Contoh soalan bagus:
- "Cuba kamu terangkan balik apa itu [konsep] dalam ayat sendiri?"
- "Kalau [nilai], berapakah [jawapan]? Tunjukkan pengiraan kamu."
- "Apa yang jadi kalau [syarat berubah]? Cuba fikirkan."
- "Di mana kamu selalu keliru dalam bahagian ini?"
- "Boleh kamu bagi satu contoh sendiri?"` : `At the end of every explanation, ask a short open question that requires the student to TYPE or SPEAK their answer.
NEVER ask a yes/no question that can be answered with a tap.
The question MUST relate directly to what was just explained.
Vary the question type â€” do not repeat the same ending every message.
Good examples:
- "Can you explain that back in your own words?"
- "Try solving this: if [value], what is [answer]? Show your working."
- "What would happen if [condition changed]? Think it through."
- "Which part of this are you least confident about?"
- "Give me your own example of this concept."
`}

==================================================
SYMBOL CONSISTENCY RULE
==================================================
${isEnglish
  ? `When explaining mathematical or scientific symbols, always use consistent spoken terms.
Do not alternate between different names for the same symbol in one session.
Standard terms: squared, cubed, square root of, integral of, delta (change in), theta, pi, sigma (sum of).`
  : `Apabila menerangkan simbol matematik atau sains, gunakan istilah yang konsisten.
Jangan tukar-tukar nama untuk simbol yang sama dalam satu sesi.
Istilah piawai: kuasa dua, kuasa tiga, punca kuasa dua, kamiran, delta (perubahan), theta, pi, sigma (hasil tambah).`}
==================================================
==================================================
MANDATORY RESPONSE RULES -- ALL SESSIONS
==================================================
RULE 1 -- ASK FIRST, LECTURE NEVER:
Never start explaining before asking what the student doesn't understand.
First message ALWAYS asks a diagnostic question.

RULE 2 â€” KEEP RESPONSES SHORT:
Max 3-4 sentences, then ONE question. Stop there.
Never write essays. Never use long bullet point lists.
If you catch yourself writing more than 4 sentences: CUT IT.

RULE 3 â€” OPEN QUESTION EVERY TIME (already enforced above, repeat for emphasis):
${isBm ? 'BETUL: "Cuba kamu terangkan balik â€” apa itu elektron?"\nSALAH: "Faham?" atau "Ada soalan lagi?" (soalan ya/tidak)' : 'CORRECT: "Can you explain back â€” what is an electron?"\nWRONG: "Understand?" or "Any questions?" (yes/no)'}

RULE 4 â€” STUDENT ANSWERS CORRECTLY:
${isBm ? '"Betul tu! [pujian spesifik]. Sekarang cuba: [soalan lebih sukar]"' : '"That\'s right! [specific praise]. Now try: [harder question]"'}

RULE 5 â€” STUDENT ANSWERS INCORRECTLY:
${isBm ? '"Hampir! Cuba semak balik [bahagian spesifik]. Hint: [satu hint kecil]. Cuba lagi?"' : '"Almost! Check [specific part] again. Hint: [one small hint]. Try again?"'}

RULE 6 â€” STUDENT SAYS TIDAK FAHAM:
${isBm ? '"Okay takpe! Mula dengan yang paling asas â€” [soalan paling mudah berkaitan]"' : '"No worries! Let\'s start from the very basics â€” [simplest related question]"'}

RULE 7 â€” REDIRECT AFTER 3-4 EXCHANGES:
${isBm ? 'Selepas 3-4 pertukaran mesej dan pelajar dah faham, WAJIB kata:\n"Okay kamu dah faham! Pergi cuba soalan Try It dalam pelajaran tu. Kamu boleh buat!"' : 'After 3-4 exchanges and student understands, MUST say:\n"Great, you\'ve got it! Go try the Try It question in your lesson. You can do this!"'}
==================================================

==================================================
LESSON FLOW (ENFORCED SEQUENCE)
==================================================
Lesson 1 (intro): Hook â†' activate prior knowledge â†' STOP
Lesson 2 (teach Ã— 3): ONE concept â†' worked example â†' common mistake â†' comprehension question â†' STOP â†' assess answer â†' repeat
Lesson 3 (quiz): SPM-style question â†' student answers â†' mark it with scheme â†' summarise

==================================================
CURRENT PHASE INSTRUCTIONS
==================================================
${currentPhaseInstructions}

==================================================
OUTPUT RULES -- HARD LIMITS
==================================================
- Respond in plain teaching text only. NO JSON, NO code blocks, NO curly braces {}, NO brackets [], no programming syntax in your reply.
- NEVER list all sub-topics in one message.
- NEVER give a full lesson summary before teaching.
- NEVER pre-answer questions the student has not asked yet.
- NEVER write more than the word limit specified above.
- If you catch yourself about to explain more than ONE concept: STOP, cut it, save it for next turn.
- NEVER show teaching instructions, phase descriptions, or internal labels to the student.
- ONLY write natural conversational sentences exactly as a teacher would speak out loud.
- Use **bold** for key terms and newlines for steps where helpful -- markdown is allowed in the reply text.
- After your teaching text, call the classify_turn tool exactly once with how the student responded this turn. Do not mention the tool to the student.`;

    // Append strict Bahasa Malaysia rules when subject is BM
    if (isBmSubject) {
      systemPrompt += `

==================================================
PERATURAN MUTLAK â€” BAHASA MALAYSIA
==================================================
Subjek ini adalah Bahasa Malaysia.

1. WAJIB menggunakan Bahasa Malaysia SEPENUHNYA dalam SEMUA respons tanpa pengecualian.

2. DILARANG SAMA SEKALI mencampurkan bahasa Inggeris dalam ayat â€” tiada code-switching, tiada 'Bahasa Malaysia words' diikuti English words.

3. Gunakan bahasa formal dan baku sepertimana dalam Dewan Bahasa dan Pustaka (DBP).

4. DILARANG menggunakan bahasa pasar, bahasa rojak, atau ungkapan tidak formal.

5. Istilah teknikal mestilah dalam Bahasa Malaysia:
   - 'karangan' bukan 'essay'
   - 'kata kerja' bukan 'verb'
   - 'ayat' bukan 'sentence'
   - 'penulisan' bukan 'writing'
   - 'pembacaan' bukan 'reading'
   - 'tatabahasa' bukan 'grammar'
   - 'peribahasa' bukan 'proverb'
   - 'simpulan bahasa' kekal Bahasa Malaysia

6. Soalan pantas (suggestedResponses) MESTI dalam Bahasa Malaysia:
   - 'Faham! Teruskan.'
   - 'Boleh beri contoh lain?'
   - 'Saya kurang faham bahagian ini.'
   BUKAN 'I understand, please continue'

7. Penilaian dan maklum balas mesti menggunakan frasa formal Bahasa Malaysia:
   - 'Tepat sekali!' bukan 'Correct!'
   - 'Baik, cuba lagi.' bukan 'Good try.'
   - 'Jawapan anda kurang tepat.' bukan 'Wrong answer.'

8. Jika pelajar menulis dalam Bahasa Inggeris, balas dalam Bahasa Malaysia dan lembut galakkan mereka: 'Sila gunakan Bahasa Malaysia ya. Mari kita cuba sekali lagi.'
==================================================`;
    }

    // Append strict Sejarah rules when subject is Sejarah
    if (isSejarahSubject) {
      systemPrompt += `

==================================================
PERATURAN MUTLAK â€” SEJARAH
==================================================
Subjek ini adalah Sejarah.

1. WAJIB menggunakan Bahasa Malaysia SEPENUHNYA dalam SEMUA respons tanpa pengecualian.

2. DILARANG mencampurkan bahasa Inggeris â€” tiada code-switching langsung.

3. Gunakan bahasa formal dan baku DBP.

4. Istilah teknikal Sejarah mestilah dalam BM:
   - 'tamadun' bukan 'civilization'
   - 'penjajahan' bukan 'colonization'
   - 'kemerdekaan' bukan 'independence'
   - 'pemberontakan' bukan 'rebellion'
   - 'perjanjian' bukan 'treaty'
   - 'perdagangan' bukan 'trade'
   - 'kerajaan' bukan 'kingdom/government'
   - 'tokoh' bukan 'figure/leader'
   - 'peristiwa' bukan 'event'
   - 'kronologi' bukan 'chronology'

5. Nama tempat dan tokoh sejarah kekal dalam ejaan asal Bahasa Malaysia:
   - 'Parameswara' bukan 'Paramesvara'
   - 'Melaka' bukan 'Malacca'
   - 'Tanah Melayu' bukan 'Malaya'
   - 'Perang Dunia' bukan 'World War'

6. Quick replies (suggestedResponses) MESTI dalam Bahasa Malaysia:
   - 'Faham! Teruskan.'
   - 'Boleh cerita lebih lanjut?'
   - 'Saya kurang faham bahagian ini.'
   BUKAN 'I understand, please continue'

7. Penilaian dan maklum balas mesti menggunakan frasa formal Bahasa Malaysia:
   - 'Tepat sekali!' bukan 'Correct!'
   - 'Baik, cuba lagi.' bukan 'Good try.'
   - 'Jawapan anda kurang tepat.' bukan 'Wrong answer.'

8. Jika pelajar menulis dalam Bahasa Inggeris, balas dalam Bahasa Malaysia dan lembut galakkan mereka: 'Sila gunakan Bahasa Malaysia ya. Mari kita cuba sekali lagi.'
==================================================`;
    }

    // General BM word-substitution rules â€” applied whenever language is BM (all subjects)
    if (isBm) {
      systemPrompt += `

==================================================
BAHASA MALAYSIA â€” PILIHAN PERKATAAN YANG BETUL
==================================================
Gunakan Bahasa Malaysia yang betul dan formal dalam semua respons.
Elakkan mencampur aduk bahasa Inggeris sesuka hati.
Istilah teknikal matematik dan sains yang tiada padanan BM yang kukuh boleh dikekalkan
(contoh: insurans, premium, graf, formula, pecahan, integer, isipadu).

Kata-kata biasa MESTI dalam BM â€” BUKAN Inggeris:
- exposed â†' terdedah
- involve / involving â†' melibatkan
- experience â†' pengalaman
- calculation â†' pengiraan
- real / real-life â†' sebenar / kehidupan sebenar
- accident â†' kemalangan
- coverage â†' perlindungan
- claim â†' tuntutan
- benefit â†' manfaat / faedah
- risk â†' risiko
- value â†' nilai
- amount â†' jumlah
- total â†' jumlah keseluruhan
- method â†' kaedah
- concept â†' konsep
- example â†' contoh
- question â†' soalan
- answer â†' jawapan
- understand â†' faham / memahami
- apply â†' guna / menggunakan / menerapkan
- advantage â†' kelebihan
- survive / survival â†' terus hidup / kemandirian
- scarce / scarcity â†' terhad / kekurangan
- distinction â†' perbezaan
- angle (non-math) â†' sudut pandang
- solid â†' kukuh
- reproduce / reproduction â†' membiak / pembiakan
- inherit / inheritance â†' mewarisi / pewarisan
- environment â†' alam sekitar
- adapt / adaptation â†' menyesuaikan diri / adaptasi

Jika ragu antara BM atau Inggeris, PILIH BM.
==================================================`;
    }

    // Append Kurikulum Merdeka + Pedagogy blocks for Indonesian students
    const studentCountry = req.body.country || 'MY';
    if (studentCountry === 'ID' && subject && topic) {
      // KM Capaian Pembelajaran block
      const cp = await loadStudentCP(subject, req.body.form || 'Kelas 11');
      if (cp.length > 0) {
        const highPriority = cp
          .filter(c => c.snbt_weight === 'tinggi')
          .slice(0, 3)
          .map(c => `- ${c.elemen}: ${c.capaian_pembelajaran.substring(0, 120)}`)
          .join('\n');
        if (highPriority) {
          systemPrompt += `\n\n==================================================\nKURIKULUM MERDEKA (Kemdikbud 2025)\n==================================================\nAjarkan sesuai Capaian Pembelajaran resmi.\nPrioritas SNBT tinggi:\n${highPriority}\nGunakan konteks kehidupan nyata Indonesia.\n==================================================`;
        }
      }

      // Project Garuda pedagogy layer
      const topicKeyword = topic.split(' ').slice(0, 3).join(' ');
      const { data: pedagogy } = await supabase
        .from('pedagogy_methods')
        .select('analogy_used, fear_reduction_phrases, key_shortcuts, teaching_sequence, snbt_relevance')
        .eq('country', 'ID')
        .eq('subject', subject)
        .ilike('topic', `%${topicKeyword}%`)
        .maybeSingle();

      if (pedagogy) {
        const shortcuts = (() => { try { return JSON.parse(pedagogy.key_shortcuts || '[]'); } catch { return []; } })();
        const fears     = (() => { try { return JSON.parse(pedagogy.fear_reduction_phrases || '[]'); } catch { return []; } })();
        // Parse teaching_sequence â€” may be stored as a JSON string (array of phase objects)
        let teachingOrder = 'konsep -> contoh -> latihan';
        if (pedagogy.teaching_sequence) {
          if (typeof pedagogy.teaching_sequence === 'string') {
            try {
              const seq = JSON.parse(pedagogy.teaching_sequence);
              if (Array.isArray(seq)) {
                teachingOrder = seq.map((s, i) => `${i + 1}. ${s.concept || s.name || s.title || JSON.stringify(s)}`).join(' -> ');
              } else {
                teachingOrder = String(pedagogy.teaching_sequence);
              }
            } catch { teachingOrder = String(pedagogy.teaching_sequence); }
          } else if (Array.isArray(pedagogy.teaching_sequence)) {
            teachingOrder = pedagogy.teaching_sequence.map((s, i) => `${i + 1}. ${s.concept || s.name || s.title || s}`).join(' -> ');
          }
        }
        systemPrompt += `\n\n==================================================\nLEARNOVA PEDAGOGY LAYER (Project Garuda)\n==================================================\nGunakan gaya pengajaran ini:\n- Analogi: ${pedagogy.analogy_used || 'gunakan analogi kehidupan sehari-hari'}\n- Urutan: ${teachingOrder}\n${shortcuts.length ? `- Trik: ${shortcuts.slice(0, 3).join(', ')}` : ''}\n${fears.length ? `- Mulai dengan: "${fears[0]}"` : 'Mulai dengan mengurangi kecemasan sebelum masuk materi.'}\n==================================================`;
      }
    }

    const msgs = [];
    if (Array.isArray(history)) {
      for (const h of history.slice(-10)) {
        msgs.push({ role: h.role === 'user' ? 'user' : 'assistant', content: h.content || '' });
      }
    }
    // â”€â”€ Lesson context injection (when opened from LessonScreen) â”€â”€
    if (lessonId && lessonContext) {
      const lc = lessonContext;
      systemPrompt += `\n\n==================================================
KONTEKS PELAJARAN SEMASA â€” BACA DAN IKUT
==================================================
Tajuk Pelajaran: ${lc.lesson_title || topic}
Topik: ${lc.topic || topic}

Konsep yang diajar dalam pelajaran:
${lc.concept_explanation || ''}

Contoh yang diberikan dalam pelajaran:
${lc.worked_example || ''}

Soalan Try It yang pelajar perlu selesaikan:
${lc.try_it_question || ''}

==================================================
TUGAS KAMU â€” WAJIB IKUT SEMUA PERATURAN INI:
==================================================
1. Bantu pelajar faham KONSEP DALAM PELAJARAN INI sahaja.
2. JANGAN ajar topik lain atau konsep di luar pelajaran ini.
3. JANGAN beri jawapan terus untuk Soalan Try It di atas.
4. Gunakan soalan Socratic â€” pandu pelajar berfikir sendiri.
5. Nova BUKAN pengganti pelajaran â€” Nova PEMBANTU pelajaran.
6. Selepas 3-4 pertukaran mesej DAN pelajar dah faham, WAJIB tulis:
   "Okay bagus! Cuba selesaikan soalan tu sekarang. Kamu boleh buat ni! Kembali ke Pelajaran."
7. Jika pelajar tanya soalan di luar topik ini, balas:
   "Jom fokus dulu pada [lesson_title] ni. Selesaikan dulu, baru kita boleh explore topik lain!"
==================================================`
      ;
    }

    const userMsg = message === 'start'
      ? `Start teaching me about "${topic}" in ${subject}.`
      : (message || 'continue');
    msgs.push({ role: 'user', content: userMsg });

    const claudeRes = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: maxTokens,
      system: systemPrompt,
      messages: msgs,
      tools: [TUTOR_CLASSIFY_TOOL],
      tool_choice: { type: 'tool', name: 'classify_turn' },
    });

    const blocks = Array.isArray(claudeRes.content) ? claudeRes.content : [];
    const _raw = blocks.filter(b => b.type === 'text').map(b => (b.text || '')).join('').trim();
    const _braceIdx = _raw.indexOf('{');
    const reply = _braceIdx > 0
      ? (safeReply(_raw.slice(_braceIdx)) || _raw.slice(0, _braceIdx).trim())
      : safeReply(_raw);
    const toolBlock = blocks.find(b => b.type === 'tool_use' && b.name === 'classify_turn');
    const classification = (toolBlock && toolBlock.input) || { student_signal: 'continue', ready_for_quiz: false };
    const signal = classification.student_signal || 'continue';
    const readyForQuiz = classification.ready_for_quiz === true;

    const newPhase = nextPhase(currentPhase, signal, currentSegment, totalChunks, readyForQuiz, topicDone);
    const newSegment = nextSegment(currentPhase, newPhase, currentSegment);
    const hasActiveQuestion = newPhase === 'quiz_setup';
    const chips = chipsForPhase(newPhase, isBm, isIndonesian, isBmSubject, isSejarahSubject);

    triggerBackup();
    return res.json({
      reply,
      phase: newPhase,
      segment: newSegment,
      suggestedResponses: chips,
      hasActiveQuestion,
      activeQuestion: hasActiveQuestion ? {} : null,
      isCheckIn: newPhase === 'check' || newPhase === 'quiz_answer',
      source: 'claude',
    });
  } catch (e) {
    console.error('Tutor session error:', e);
    res.status(500).json({ error: e.message });
  }
});

// â”€â”€ KM CURRICULUM HELPERS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
async function loadStudentCP(subject, studentForm) {
  const fase = (studentForm || '').includes('10') ? 'Fase E' : 'Fase F';
  const { data } = await supabase
    .from('curriculum_structure')
    .select('elemen, sub_elemen, capaian_pembelajaran, snbt_weight, learnova_method')
    .eq('country', 'ID')
    .eq('subject', subject)
    .eq('fase', fase)
    .order('snbt_weight', { ascending: false });
  return data || [];
}

async function updateCPMastery(studentId, subject, fase, cpCode, isCorrect) {
  try {
    const { data: current } = await supabase
      .from('student_cp_progress')
      .select('evidence_count, mastery_level')
      .eq('student_id', studentId)
      .eq('subject', subject)
      .eq('cp_code', cpCode)
      .maybeSingle();

    const prevCount = current?.evidence_count || 0;
    const newCount  = prevCount + 1;
    const prevRate  = { mahir: 0.90, cakap: 0.75, layak: 0.60, berkembang: 0.45, belum: 0.0 }[current?.mastery_level || 'belum'];
    const prevCorrect  = prevRate * prevCount;
    const newAccuracy  = (prevCorrect + (isCorrect ? 1 : 0)) / newCount;

    let mastery = 'belum';
    if (newAccuracy >= 0.85)      mastery = 'mahir';
    else if (newAccuracy >= 0.70) mastery = 'cakap';
    else if (newAccuracy >= 0.55) mastery = 'layak';
    else if (newAccuracy >= 0.40) mastery = 'berkembang';

    await supabase.from('student_cp_progress').upsert({
      student_id: studentId, country: 'ID',
      subject, fase, cp_code: cpCode,
      mastery_level: mastery,
      evidence_count: newCount,
      last_assessed: new Date().toISOString(),
    }, { onConflict: 'student_id,subject,fase,cp_code' });
  } catch (e) {
    console.error('[CP] mastery update error:', e.message);
  }
}

// -- UPDATE FORM -----------------------------------------------
app.patch('/api/auth/update-form', authStudent, async (req, res) => {
  try {
    const { student_id, form_level, subjects } = req.body;
    await supabase.from('students').update({ form_level, onboarding_complete: true }).eq('id', student_id);
    res.json({ ok: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// â”€â”€ CONTENT CHUNKS (topic intro screen) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.get('/api/tutor/content-chunks', async (req, res) => {
  try {
    const { subject: rawSubject, topic } = req.query;
    const subject = normalizeSubject(rawSubject);
    if (!subject) return res.json({ chunks: [] });

    const cols = 'concept_title,concept_explanation,worked_example,common_mistakes,keywords,difficulty_level';

    // 1. ILIKE subject + ILIKE topic
    if (topic) {
      const { data: exact } = await supabase
        .from('concept_chunks').select(cols)
        .ilike('subject', '%' + subject + '%').ilike('topic', '%' + topic + '%')
        .order('difficulty_level', { ascending: true }).limit(6);
      if (exact && exact.length > 0) return res.json({ chunks: exact });

      // 2. Keyword fallback â€” longest word in topic name (>3 chars)
      const keyword = topic.split(/\s+/).filter(w => w.length > 3).sort((a, b) => b.length - a.length)[0];
      if (keyword) {
        const { data: kw } = await supabase
          .from('concept_chunks').select(cols)
          .ilike('subject', '%' + subject + '%').ilike('topic', '%' + keyword + '%')
          .order('difficulty_level', { ascending: true }).limit(6);
        if (kw && kw.length > 0) return res.json({ chunks: kw });
      }
    }

    // 3. No topic match â€” return empty so UI shows "coming soon" gracefully
    return res.json({ chunks: [] });
  } catch (err) {
    return res.json({ chunks: [] });
  }
});

// â”€â”€ TOPIC ILLUSTRATIONS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.get('/api/tutor/illustrations', async (req, res) => {
  try {
    const { subject, topic } = req.query;
    if (!subject || !topic) return res.json({ illustrations: [] });

    // 1. Exact subject match + topic ilike
    const { data: exact } = await supabase
      .from('topic_illustrations')
      .select('title, svg_code, description')
      .eq('subject', subject)
      .ilike('topic', '%' + topic + '%')
      .limit(3);
    if (exact && exact.length > 0) return res.json({ illustrations: exact });

    // 2. ILIKE fallback â€” handles subject variations (e.g. "Add Maths" vs "Mathematics")
    const { data: fuzzy } = await supabase
      .from('topic_illustrations')
      .select('title, svg_code, description')
      .ilike('subject', '%' + subject + '%')
      .ilike('topic', '%' + topic + '%')
      .limit(3);
    if (fuzzy && fuzzy.length > 0) return res.json({ illustrations: fuzzy });

    return res.json({ illustrations: [] });
  } catch (err) {
    return res.json({ illustrations: [] });
  }
});

// â”€â”€ ADMIN BACKUP ENDPOINT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.get('/api/admin/backup', (req, res) => {
  const secret = req.headers['admin_secret_key'] || req.headers['admin-secret-key'];
  if (!secret || secret !== process.env.ADMIN_SECRET_KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  triggerBackup();
  res.json({ status: 'backup started' });
});

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// PARENT PROGRESS ENGINE
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

// Student: return own LRN code + name + form (used by StudentIdScreen)
app.get('/api/student/my-id', authStudent, async (req, res) => {
  try {
    const { data: s } = await supabase.from('students').select('learnova_id,name,form_level').eq('id', req.user.student_id).single();
    if (!s) return res.status(404).json({ error: 'Student not found' });
    res.json({ student_code: s.learnova_id, name: s.name, form: s.form_level });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// Student: get link code (same as my-id, for parent linking flow)
app.get('/api/student/link-code', authStudent, async (req, res) => {
  try {
    const { data: s } = await supabase.from('students').select('learnova_id,name').eq('id', req.user.student_id).single();
    if (!s) return res.status(404).json({ error: 'Student not found' });
    res.json({ link_code: s.learnova_id, name: s.name });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// Parent: enter student LRN code to link
app.post('/api/parent/connect', authParent, async (req, res) => {
  try {
    const { student_code } = req.body;
    if (!student_code) return res.status(400).json({ error: 'student_code required' });
    const code = student_code.trim().toUpperCase();
    const { data: student } = await supabase.from('students').select('id,name,learnova_id').eq('learnova_id', code).maybeSingle();
    if (!student) return res.status(404).json({ error: 'Kod pelajar tidak dijumpai. Semak semula kod yang diberikan.' });
    // Link via parent_email on student record
    const { data: parent } = await supabase.from('parents').select('email').eq('id', req.user.parent_id).single();
    if (parent) await supabase.from('students').update({ parent_email: parent.email }).eq('id', student.id);
    // Also upsert into parent_child_links if it exists
    try { await supabase.from('parent_child_links').upsert([{ parent_id: req.user.parent_id, student_id: student.id }], { onConflict: 'parent_id,student_id' }); } catch (_) {}
    res.json({ success: true, message: `Berjaya disambungkan dengan ${student.name}!`, student_name: student.name });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ── Parent Portal (no-auth) ────────────────────────────────────────────────

// Link: validate LRN-XXXXXX, return student basics
app.post('/api/parent/link', async (req, res) => {
  try {
    const { learnovaId } = req.body;
    if (!learnovaId) return res.status(400).json({ error: 'learnovaId required' });
    const code = learnovaId.toString().toUpperCase().trim();
    const { data: student } = await supabase
      .from('students')
      .select('id, name, form_level, selected_subjects, learnova_id')
      .eq('learnova_id', code)
      .maybeSingle();
    if (!student) return res.status(404).json({ error: 'Pelajar tidak dijumpai' });
    res.json({
      ok: true,
      studentId: student.id,
      name: student.name,
      level: `Form ${student.form_level || 5}`,
      subjects: student.selected_subjects || [],
      learnovaId: student.learnova_id,
    });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// Dashboard: full progress for a student (by internal UUID)
app.get('/api/parent/child-progress', async (req, res) => {
  try {
    const { studentId } = req.query;
    if (!studentId) return res.status(400).json({ error: 'studentId required' });

    const { data: student } = await supabase
      .from('students')
      .select('id, name, form_level, selected_subjects, learnova_id, created_at')
      .eq('id', studentId)
      .maybeSingle();
    if (!student) return res.status(404).json({ error: 'Student not found' });

    const sid = student.id;
    const now = new Date();
    const today = now.toISOString().substring(0, 10);

    // Week boundaries (Mon=start)
    const dow = now.getDay(); // 0=Sun
    const weekStart = new Date(now);
    weekStart.setDate(now.getDate() - ((dow + 6) % 7));
    weekStart.setHours(0, 0, 0, 0);
    const lastWeekStart = new Date(weekStart);
    lastWeekStart.setDate(weekStart.getDate() - 7);

    const [sessRes, progressRes, loginsRes, novaRes, quizRes, subjProgRes] = await Promise.all([
      supabase.from('lesson_sessions')
        .select('id, lesson_id, subject, topic, started_at, ended_at, duration_seconds, completed')
        .eq('student_id', sid)
        .gte('started_at', lastWeekStart.toISOString())
        .order('started_at', { ascending: false }),
      supabase.from('student_lesson_progress')
        .select('lesson_id, subject, topic, status, completed_at, updated_at')
        .eq('student_id', sid),
      supabase.from('student_logins')
        .select('logged_at')
        .eq('student_id', sid)
        .order('logged_at', { ascending: false })
        .limit(60),
      supabase.from('nova_sessions')
        .select('id, subject, topic, messages_count, duration_minutes, started_at')
        .eq('student_id', sid)
        .gte('started_at', lastWeekStart.toISOString())
        .order('started_at', { ascending: false }),
      supabase.from('quiz_attempts')
        .select('id, subject, topic, score, total, started_at, created_at')
        .eq('student_id', sid)
        .order('started_at', { ascending: false })
        .limit(20),
      supabase.from('subject_progress')
        .select('subject, lessons_completed')
        .eq('student_id', sid),
    ]);

    const sessions   = sessRes.data     || [];
    const progress   = progressRes.data || [];
    const logins     = loginsRes.data   || [];
    const novas      = novaRes.data     || [];
    const quizzes    = quizRes.data     || [];
    const subjProgData = subjProgRes.data || [];

    // Activity days set (for streak)
    const activityDays = new Set([
      ...sessions.map(s => s.started_at?.substring(0, 10)),
      ...logins.map(l => l.logged_at?.substring(0, 10)),
      ...novas.map(n => n.started_at?.substring(0, 10)),
    ].filter(Boolean));

    // ── Today ─────────────────────────────────────────────────────────────────
    const todaySess  = sessions.filter(s => s.started_at?.startsWith(today));
    const todayNovas = novas.filter(n => n.started_at?.startsWith(today));
    const studyMinutes = todaySess.reduce((a, s) => a + Math.round((s.duration_seconds || 0) / 60), 0)
                       + todayNovas.reduce((a, n) => a + (n.duration_minutes || 0), 0);
    const lessonsCompleted = todaySess.filter(s => s.completed).length;
    const topicsCompleted  = progress.filter(p => p.status === 'completed').length;
    const novaQuestions    = todayNovas.reduce((a, n) => a + (n.messages_count || 0), 0);

    let streak = 0;
    const d0 = new Date(); d0.setHours(0, 0, 0, 0);
    while (activityDays.has(d0.toISOString().substring(0, 10))) {
      streak++;
      d0.setDate(d0.getDate() - 1);
    }

    const allTimes = [
      ...sessions.map(s => s.started_at),
      ...logins.map(l => l.logged_at),
      ...novas.map(n => n.started_at),
    ].filter(Boolean).sort().reverse();
    const lastActive   = allTimes[0] || null;
    const isActiveToday = allTimes.some(t => t?.startsWith(today));

    // ── This week vs last week ─────────────────────────────────────────────────
    const thisWeekSess  = sessions.filter(s => new Date(s.started_at) >= weekStart);
    const lastWeekSess  = sessions.filter(s => { const d = new Date(s.started_at); return d >= lastWeekStart && d < weekStart; });
    const thisWeekNovas = novas.filter(n => new Date(n.started_at) >= weekStart);
    const lastWeekNovas = novas.filter(n => { const d = new Date(n.started_at); return d >= lastWeekStart && d < weekStart; });

    const thisWeekMinutes = thisWeekSess.reduce((a, s) => a + Math.round((s.duration_seconds || 0) / 60), 0)
                          + thisWeekNovas.reduce((a, n) => a + (n.duration_minutes || 0), 0);
    const lastWeekMinutes = lastWeekSess.reduce((a, s) => a + Math.round((s.duration_seconds || 0) / 60), 0)
                          + lastWeekNovas.reduce((a, n) => a + (n.duration_minutes || 0), 0);
    const thisWeekTopics  = new Set(thisWeekSess.filter(s => s.completed).map(s => `${s.subject}|${s.topic}`)).size;
    const lastWeekTopics  = new Set(lastWeekSess.filter(s => s.completed).map(s => `${s.subject}|${s.topic}`)).size;
    const thisWeekLessons = thisWeekSess.filter(s => s.completed).length;
    const minutesDiff = thisWeekMinutes - lastWeekMinutes;
    const topicsDiff  = thisWeekTopics - lastWeekTopics;
    const trend = minutesDiff > 5 ? 'up' : minutesDiff < -5 ? 'down' : 'same';

    const BM_DAYS = ['Isnin', 'Selasa', 'Rabu', 'Khamis', 'Jumaat', 'Sabtu', 'Ahad'];
    const dailyActivity = [];
    for (let i = 0; i < 7; i++) {
      const day = new Date(weekStart); day.setDate(weekStart.getDate() + i);
      const dayStr = day.toISOString().substring(0, 10);
      const dayMins = sessions.filter(s => s.started_at?.startsWith(dayStr))
          .reduce((a, s) => a + Math.round((s.duration_seconds || 0) / 60), 0)
        + novas.filter(n => n.started_at?.startsWith(dayStr))
          .reduce((a, n) => a + (n.duration_minutes || 0), 0);
      dailyActivity.push({ date: dayStr, dayName: BM_DAYS[i], minutes: dayMins, studied: dayMins > 0 || activityDays.has(dayStr) });
    }

    // ── Subject progress ──────────────────────────────────────────────────────
    const selectedSubjects = student.selected_subjects || [];

    // Get actual lesson totals per subject from structured_lessons
    const { data: lessonCountData } = selectedSubjects.length > 0
      ? await supabase.from('structured_lessons').select('subject').in('subject', selectedSubjects)
      : { data: [] };
    const lessonTotalsBySubject = {};
    (lessonCountData || []).forEach(l => {
      lessonTotalsBySubject[l.subject] = (lessonTotalsBySubject[l.subject] || 0) + 1;
    });

    // subject_progress gives more accurate completed count for new tracking system
    const subjProgMap = {};
    subjProgData.forEach(sp => { subjProgMap[sp.subject] = sp.lessons_completed || 0; });

    const subjectData = selectedSubjects.map(subj => {
      const subjProg  = progress.filter(p => p.subject === subj);
      const completed = subjProg.filter(p => p.status === 'completed');
      const completedByTopic = {}, totalByTopic = {};
      subjProg.forEach(p => {
        if (!p.topic) return;
        totalByTopic[p.topic]    = (totalByTopic[p.topic]    || 0) + 1;
        if (p.status === 'completed') completedByTopic[p.topic] = (completedByTopic[p.topic] || 0) + 1;
      });
      const strongTopics = Object.entries(completedByTopic)
        .filter(([t, c]) => c >= (totalByTopic[t] || 1)).map(([t]) => t).slice(0, 3);
      const weakTopics = Object.entries(totalByTopic)
        .filter(([t, total]) => (completedByTopic[t] || 0) < total * 0.5)
        .sort((a, b) => b[1] - a[1]).map(([t]) => t).slice(0, 3);
      const lastStudiedRec = [...completed].sort((a, b) => new Date(b.completed_at || 0) - new Date(a.completed_at || 0))[0];
      const minutesThisWeek = thisWeekSess.filter(s => s.subject === subj)
        .reduce((a, s) => a + Math.round((s.duration_seconds || 0) / 60), 0);
      const lessonsCompletedCount = subjProgMap[subj] !== undefined ? subjProgMap[subj] : completed.length;
      const totalLessons = lessonTotalsBySubject[subj] || 24;
      const percentComplete = Math.min(100, Math.round((lessonsCompletedCount / totalLessons) * 100));
      return {
        subject: subj,
        displayName: subjectEngine.getDisplayName(subj),
        topicsCompleted: lessonsCompletedCount,
        topicsTotal: totalLessons,
        percentComplete,
        lastStudied: lastStudiedRec?.completed_at || null,
        minutesThisWeek,
        strongTopics,
        weakTopics,
      };
    });

    // ── SPM Readiness ─────────────────────────────────────────────────────────
    const SPM_DATE = new Date('2026-11-14T00:00:00+08:00');
    const daysRemaining = Math.max(0, Math.floor((SPM_DATE - now) / 86400000));
    const overallPercent = subjectData.length > 0
      ? Math.round(subjectData.reduce((a, s) => a + s.percentComplete, 0) / subjectData.length) : 0;
    const predictedGrade = overallPercent >= 90 ? 'A+' : overallPercent >= 75 ? 'A'
      : overallPercent >= 60 ? 'B+' : overallPercent >= 45 ? 'B' : overallPercent >= 30 ? 'C' : 'Perlu Usaha';
    const totalRemaining = subjectData.reduce((a, s) => a + (s.topicsTotal - s.topicsCompleted), 0);
    const hoursNeededToComplete = Math.round(totalRemaining * 15 / 60);
    const subjectReadiness = subjectData.map(s => ({
      subject: s.displayName,
      percent: s.percentComplete,
      status: s.minutesThisWeek >= 30 ? 'ahead' : s.percentComplete < 20 ? 'behind' : 'on_track',
    }));

    // ── Recent activity ───────────────────────────────────────────────────────
    const recentRaw = [
      ...sessions.slice(0, 10).map(s => ({
        type: 'lesson', subject: subjectEngine.getDisplayName(s.subject || ''),
        topic: s.topic || '', title: '', time: new Date(s.started_at), score: null, lesson_id: s.lesson_id,
      })),
      ...novas.slice(0, 5).map(n => ({
        type: 'nova', subject: subjectEngine.getDisplayName(n.subject || ''),
        topic: n.topic || '', title: `${n.messages_count || 0} soalan`, time: new Date(n.started_at), score: null, lesson_id: null,
      })),
      ...quizzes.slice(0, 5).map(q => ({
        type: 'quiz', subject: subjectEngine.getDisplayName(q.subject || ''),
        topic: q.topic || '', title: '', time: new Date(q.started_at || q.created_at), score: q.total > 0 ? Math.round((q.score / q.total) * 100) : null, lesson_id: null,
      })),
    ].sort((a, b) => b.time - a.time).slice(0, 5);

    for (const item of recentRaw) {
      if (item.type === 'lesson' && item.lesson_id) {
        const { data: ld } = await supabase.from('structured_lessons')
          .select('lesson_title, topic').eq('id', item.lesson_id).maybeSingle();
        if (ld) { item.title = ld.lesson_title || ''; if (!item.topic) item.topic = ld.topic || ''; }
      }
    }
    const recentActivity = recentRaw.map(({ lesson_id, time, ...rest }) => ({
      ...rest, minutesAgo: Math.floor((now - time) / 60000),
    }));

    // ── BM summary (Claude-generated) ─────────────────────────────────────────
    const firstName = (student.name || 'Pelajar').split(' ')[0];
    const level = `Form ${student.form_level || 5}`;
    const lastSubjectName = sessions[0] ? subjectEngine.getDisplayName(sessions[0].subject || '') : '';
    const lastTopic = sessions[0]?.topic || '';

    let summaryBm = '';
    if (claudeApiKey) {
      try {
        const { default: Anthropic } = await import('@anthropic-ai/sdk');
        const anthropic = new Anthropic({ apiKey: claudeApiKey });
        const msg = await anthropic.messages.create({
          model: 'claude-haiku-4-5-20251001', max_tokens: 250,
          messages: [{ role: 'user', content: `Kamu adalah sistem pelaporan untuk platform pembelajaran Learnova. Tulis ringkasan pembelajaran dalam 3-4 ayat BM yang natural dan informatif untuk ibu bapa.\n\nData pelajar:\n- Nama: ${firstName}\n- Tahap: ${level}\n- Hari ini: ${studyMinutes} minit belajar, ${lessonsCompleted} pelajaran selesai\n- Streak: ${streak} hari berturut-turut\n- Subjek terkini: ${lastSubjectName || 'tiada'}\n- Topik terkini: ${lastTopic || 'tiada'}\n- Kemajuan keseluruhan: ${overallPercent}%\n- Hari ke SPM: ${daysRemaining}\n\nTulis dalam BM yang mudah difahami ibu bapa. Jangan guna jargon teknikal. Mulakan dengan nama pelajar. Akhiri dengan nota motivasi. Jawab hanya ringkasan sahaja.` }],
        });
        summaryBm = msg.content[0]?.text?.trim() || '';
      } catch (_) {}
    }
    if (!summaryBm) {
      summaryBm = `${firstName} sedang belajar pada peringkat ${level} dengan ${selectedSubjects.length} subjek terpilih.`;
      if (studyMinutes > 0) summaryBm += ` Hari ini beliau telah belajar selama ${studyMinutes} minit.`;
      if (streak > 1) summaryBm += ` Streak semasa: ${streak} hari berturut-turut.`;
      if (studyMinutes === 0 && streak === 0) summaryBm += ' Galakkan beliau untuk membuka app dan belajar hari ini.';
    }
    const summaryEn = `${firstName} is studying at ${level} with ${selectedSubjects.length} subjects. Overall progress: ${overallPercent}%. ${daysRemaining} days until SPM.`;

    const joinedDays = student.created_at
      ? Math.floor((now - new Date(student.created_at)) / 86400000) : 0;

    res.json({
      child:         { name: student.name, level, studentId: student.learnova_id, subjects: selectedSubjects, joinedDays },
      today:         { studyMinutes, topicsCompleted, lessonsCompleted, novaQuestions, streak, lastActive, isActiveToday },
      thisWeek:      { totalMinutes: thisWeekMinutes, totalTopics: thisWeekTopics, totalLessons: thisWeekLessons, dailyActivity, vsLastWeek: { minutesDiff, topicsDiff, trend } },
      subjects:      subjectData,
      spmReadiness:  { daysRemaining, overallPercent, predictedGrade, hoursNeededToComplete, subjectReadiness },
      recentActivity,
      summary:       { bm: summaryBm, en: summaryEn },
    });
  } catch (err) { console.error('child-progress:', err); res.status(500).json({ error: err.message }); }
});

// Student: log login activity
app.post('/api/activity/login', async (req, res) => {
  try {
    const { studentId } = req.body;
    if (!studentId) return res.json({ ok: false });
    await supabase.from('student_logins').insert([{ student_id: studentId, logged_at: new Date().toISOString() }]);
    res.json({ ok: true });
  } catch (_) { res.json({ ok: false }); }
});

// Lesson: start a session â€” returns sessionId
app.post('/api/lesson/start', async (req, res) => {
  try {
    const { studentId, lessonId, subject } = req.body;
    if (!studentId || !lessonId) return res.status(400).json({ error: 'studentId and lessonId required' });
    const { data } = await supabase.from('lesson_sessions').insert([{
      student_id: studentId, lesson_id: lessonId, subject: subject || '',
      started_at: new Date().toISOString(), completed: false,
    }]).select('id').single();
    res.json({ sessionId: data?.id || null, ok: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// Lesson: end a session — updates duration + completed flag
app.post('/api/lesson/end', async (req, res) => {
  try {
    const { sessionId, studentId, completed = false, durationSeconds, topic } = req.body;
    if (!sessionId) return res.json({ ok: false });
    const now = new Date().toISOString();
    const update = { ended_at: now, completed, duration_seconds: durationSeconds ?? 0 };
    if (topic) update.topic = topic;
    await supabase.from('lesson_sessions').update(update).eq('id', sessionId);
    res.json({ ok: true });
  } catch (_) { res.json({ ok: false }); }
});

// Nova: contextual session init — returns lesson-aware opening message
app.post('/api/nova/init', async (req, res) => {
  try {
    const { studentId, lastLessonId, subject, studentName } = req.body;
    const firstName = (studentName || '').split(' ')[0] || 'pelajar';

    let lessonTitle = '';
    let conceptSnippet = '';
    let lastSection = 'concept';

    if (lastLessonId) {
      const { data: lesson } = await supabase
        .from('structured_lessons')
        .select('lesson_title, topic, concept_explanation')
        .eq('id', lastLessonId)
        .maybeSingle();
      if (lesson) {
        lessonTitle = lesson.lesson_title || lesson.topic || '';
        conceptSnippet = (lesson.concept_explanation || '').slice(0, 300);
      }
      const { data: prog } = await supabase
        .from('student_lesson_progress')
        .select('last_section')
        .eq('student_id', studentId)
        .eq('lesson_id', lastLessonId)
        .maybeSingle();
      if (prog) lastSection = prog.last_section || 'concept';
    }

    const sectionLabels = { concept: 'bahagian konsep', try_it: 'soalan Cuba Kamu', completed: 'selesai' };
    const greeting = lessonTitle
      ? `Assalamualaikum, ${firstName}. Mari kita sambung "${lessonTitle}".`
      : `Assalamualaikum, ${firstName}. Apa yang kamu nak belajar hari ini?`;

    let reply = greeting;
    const suggestedResponses = ['Sambung belajar', 'Terangkan semula', 'Soalan baru'];

    if (lessonTitle && conceptSnippet) {
      const { default: Anthropic } = await import('@anthropic-ai/sdk');
      const anthropic = new Anthropic({ apiKey: claudeApiKey });
      const resp = await anthropic.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 200,
        system: `You are Nova, warm SPM tutor. Student paused at: ${sectionLabels[lastSection] || lastSection} of lesson "${lessonTitle}". Concept so far: ${conceptSnippet.slice(0, 200)}. Give 2-3 sentence contextual continuation in BM+English mix. End with ONE open question. Never say "Apa yang kamu nak belajar?"`,
        messages: [{ role: 'user', content: 'continue' }],
      });
      reply = resp.content[0].text;
    }

    res.json({ greeting, reply, suggestedResponses });
  } catch (e) {
    console.error('[nova/init] error:', e);
    res.json({
      greeting: 'Assalamualaikum. Mari kita belajar.',
      reply: 'Assalamualaikum. Mari kita sambung pelajaran kamu.',
      suggestedResponses: ['Sambung belajar', 'Soalan baru'],
    });
  }
});

// Nova: record session end
app.post('/api/nova/session-end', async (req, res) => {
  try {
    const { studentId, subject, topic, messagesCount, durationMinutes } = req.body;
    if (!studentId) return res.json({ ok: false });
    await supabase.from('nova_sessions').insert([{
      student_id: studentId,
      subject: subject || '',
      topic: topic || '',
      messages_count: messagesCount || 0,
      duration_minutes: durationMinutes || 0,
      started_at: new Date(Date.now() - (durationMinutes || 0) * 60000).toISOString(),
    }]);
    res.json({ ok: true });
  } catch (_) { res.json({ ok: false }); }
});

// ── Progress / Session Continuity ────────────────────────────────────────────

function calculateStreak(logins) {
  if (!logins || !logins.length) return 0;
  let streak = 0;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  for (let i = 0; i < logins.length; i++) {
    const loginDate = new Date(logins[i].date || logins[i].logged_at);
    loginDate.setHours(0, 0, 0, 0);
    const expected = new Date(today); expected.setDate(today.getDate() - i);
    if (loginDate.getTime() === expected.getTime()) streak++;
    else break;
  }
  return streak;
}

// Called when student opens a lesson
app.post('/api/progress/lesson-open', async (req, res) => {
  try {
    const { studentId, lessonId, subject, topic, lessonTitle } = req.body;
    if (!studentId || !lessonId) return res.status(400).json({ error: 'studentId and lessonId required' });
    const now = new Date().toISOString();
    const today = now.split('T')[0];

    const [sessResult] = await Promise.all([
      supabase.from('lesson_sessions').insert({
        student_id: studentId, lesson_id: lessonId,
        subject: subject || '', topic: topic || '',
        lesson_title: lessonTitle || '',
        started_at: now, completed: false,
      }).select('id').maybeSingle(),
      supabase.from('subject_progress').upsert({
        student_id: studentId, subject: subject || '',
        last_topic: topic || '', last_lesson_id: lessonId,
        last_accessed: now,
      }, { onConflict: 'student_id,subject' }),
      supabase.from('student_logins').upsert({
        student_id: studentId, date: today, logged_at: now,
      }, { onConflict: 'student_id,date' }).catch(() =>
        supabase.from('student_logins').insert({ student_id: studentId, date: today, logged_at: now })
      ),
    ]);

    res.json({ success: true, sessionId: sessResult.data?.id || null });
  } catch (err) { console.error('lesson-open:', err); res.status(500).json({ error: err.message }); }
});

// Called periodically (every 30s) or on section change
app.post('/api/progress/lesson-update', async (req, res) => {
  try {
    const { studentId, lessonId, subject, topic, sessionId, lastSection, scrollPosition, durationMinutes } = req.body;
    if (!studentId || !lessonId) return res.json({ success: false });
    const now = new Date().toISOString();

    const updates = [
      supabase.from('student_progress').upsert({
        student_id: studentId, lesson_id: lessonId,
        subject: subject || '', topic: topic || '',
        last_section: lastSection || 'concept',
        scroll_position: scrollPosition || 0,
        total_minutes: durationMinutes || 0,
        last_accessed: now,
      }, { onConflict: 'student_id,lesson_id' }),
    ];
    if (sessionId) {
      updates.push(
        supabase.from('lesson_sessions').update({
          duration_minutes: durationMinutes || 0,
          last_section: lastSection || 'concept',
          ended_at: now,
        }).eq('id', sessionId)
      );
    }
    await Promise.all(updates);
    res.json({ success: true });
  } catch (_) { res.json({ success: false }); }
});

// Called when student taps Selesai
app.post('/api/progress/lesson-complete', async (req, res) => {
  try {
    const { studentId, lessonId, subject, topic, sessionId, durationMinutes } = req.body;
    if (!studentId || !lessonId) return res.status(400).json({ error: 'studentId and lessonId required' });
    const now = new Date().toISOString();

    const { data: existing } = await supabase.from('subject_progress')
      .select('lessons_completed, total_minutes')
      .eq('student_id', studentId).eq('subject', subject || '').maybeSingle();

    await Promise.all([
      supabase.from('student_progress').upsert({
        student_id: studentId, lesson_id: lessonId,
        subject: subject || '', topic: topic || '',
        last_section: 'completed', is_completed: true,
        completed_at: now, total_minutes: durationMinutes || 0, last_accessed: now,
      }, { onConflict: 'student_id,lesson_id' }),
      sessionId ? supabase.from('lesson_sessions').update({
        completed: true, duration_minutes: durationMinutes || 0, ended_at: now,
      }).eq('id', sessionId) : Promise.resolve(),
      supabase.from('subject_progress').upsert({
        student_id: studentId, subject: subject || '',
        last_topic: topic || '', last_lesson_id: lessonId,
        lessons_completed: (existing?.lessons_completed ?? 0) + 1,
        total_minutes: (existing?.total_minutes ?? 0) + (durationMinutes || 0),
        last_accessed: now,
      }, { onConflict: 'student_id,subject' }),
    ]);
    res.json({ success: true });
  } catch (err) { console.error('lesson-complete:', err); res.status(500).json({ error: err.message }); }
});

// Get student's last position — called on app open / home screen
app.get('/api/progress/resume', async (req, res) => {
  try {
    const { studentId } = req.query;
    if (!studentId) return res.status(400).json({ error: 'studentId required' });

    const [progressResult, loginsResult, todayResult, subjectProgressResult] = await Promise.all([
      supabase.from('student_progress')
        .select('*, structured_lessons(id, subject, topic, lesson_title, lesson_number, difficulty, estimated_minutes)')
        .eq('student_id', studentId)
        .eq('is_completed', false)
        .order('last_accessed', { ascending: false })
        .limit(1),
      supabase.from('student_logins')
        .select('date, logged_at')
        .eq('student_id', studentId)
        .order('date', { ascending: false })
        .limit(30),
      supabase.from('lesson_sessions')
        .select('duration_minutes, duration_seconds')
        .eq('student_id', studentId)
        .gte('started_at', new Date().toISOString().split('T')[0]),
      supabase.from('subject_progress')
        .select('lessons_completed')
        .eq('student_id', studentId),
    ]);

    const lastProgress = progressResult.data?.[0] || null;
    const streak = calculateStreak(loginsResult.data || []);
    const todayMinutes = (todayResult.data || []).reduce(
      (sum, s) => sum + (s.duration_minutes || Math.round((s.duration_seconds || 0) / 60)), 0
    );
    const totalLessonsCompleted = (subjectProgressResult.data || [])
      .reduce((sum, sp) => sum + (sp.lessons_completed || 0), 0);

    res.json({
      hasResume: !!lastProgress,
      resume: lastProgress ? {
        lessonId:     lastProgress.lesson_id,
        subject:      lastProgress.structured_lessons?.subject || lastProgress.subject,
        topic:        lastProgress.structured_lessons?.topic   || lastProgress.topic,
        lessonTitle:  lastProgress.structured_lessons?.lesson_title || '',
        lessonNumber: lastProgress.structured_lessons?.lesson_number || 1,
        lastSection:  lastProgress.last_section,
        minutesSpent: lastProgress.total_minutes,
        lastAccessed: lastProgress.last_accessed,
      } : null,
      streak,
      todayMinutes,
      totalLessonsCompleted,
    });
  } catch (err) { console.error('resume:', err); res.status(500).json({ error: err.message }); }
});

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// LESSONS ENGINE
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

// Get lesson path (all topics + lessons) for a subject
app.get('/api/lessons/path', async (req, res) => {
  const { subject: rawSubject, form } = req.query;
  const subject = normalizeSubject(rawSubject);
  const { data: lessons } = await supabase
    .from('structured_lessons')
    .select('id, topic, lesson_number, lesson_title, difficulty, estimated_minutes')
    .eq('subject', subject)
    .eq('form', form || 'Form 5')
    .eq('is_published', true)
    .order('topic')
    .order('lesson_number');
  const path = {};
  (lessons || []).forEach(l => {
    if (!path[l.topic]) path[l.topic] = [];
    path[l.topic].push(l);
  });
  res.json({ subject, form: form || 'Form 5', path });
});

// Get single lesson with student progress
app.get('/api/lessons/lesson', async (req, res) => {
  const { lessonId, studentId } = req.query;
  const { data: lesson } = await supabase
    .from('structured_lessons')
    .select('*')
    .eq('id', lessonId)
    .single();
  if (!lesson) return res.status(404).json({ error: 'Lesson not found' });
  let progress = null;
  if (studentId) {
    const { data } = await supabase
      .from('student_lesson_progress')
      .select('*')
      .eq('student_id', studentId)
      .eq('lesson_id', lessonId)
      .single();
    progress = data;
    if (!progress) {
      await supabase.from('student_lesson_progress').insert({
        student_id: studentId,
        lesson_id: lessonId,
        subject: lesson.subject,
        topic: lesson.topic,
        status: 'in_progress',
        started_at: new Date().toISOString()
      });
    }
  }
  res.json({
    lesson: {
      ...lesson,
      hook_sentence:       stripEmojis(lesson.hook_sentence),
      objective:           stripEmojis(lesson.objective),
      concept_explanation: stripEmojis(lesson.concept_explanation),
      worked_example:      stripEmojis(lesson.worked_example),
      try_it_question:     stripEmojis(lesson.try_it_question),
      try_it_answer:       stripEmojis(lesson.try_it_answer),
      common_mistakes:     stripEmojis(lesson.common_mistakes),
      exam_technique:      stripEmojis(lesson.exam_technique),
    },
    progress,
  });
});

// Mark lesson complete
app.post('/api/lessons/complete', async (req, res) => {
  const { lessonId, studentId, tryItCorrect, timeSpentSeconds } = req.body;
  if (!lessonId || !studentId) return res.status(400).json({ error: 'Missing lessonId or studentId' });
  const { error } = await supabase.from('student_lesson_progress').upsert({
    student_id: studentId,
    lesson_id: lessonId,
    status: 'completed',
    completed_at: new Date().toISOString(),
    try_it_attempted: true,
    try_it_correct: tryItCorrect || false,
    time_spent_seconds: timeSpentSeconds || 0
  }, { onConflict: 'student_id,lesson_id' });
  res.json({ success: !error });
});

// Get student progress across all lessons for a subject
app.get('/api/lessons/progress', async (req, res) => {
  const { studentId, subject: rawSubject } = req.query;
  const subject = normalizeSubject(rawSubject);
  const { data: progress } = await supabase
    .from('student_lesson_progress')
    .select('*, structured_lessons(*)')
    .eq('student_id', studentId)
    .eq('subject', subject);
  const completed = (progress || []).filter(p => p.status === 'completed').length;
  const total = (progress || []).length;
  res.json({ progress, completed, total, percentage: total > 0 ? Math.round((completed / total) * 100) : 0 });
});

// Get next incomplete lesson for student
app.get('/api/lessons/next', async (req, res) => {
  const { studentId, subject: rawSubject } = req.query;
  const subject = normalizeSubject(rawSubject);
  const { data: allLessons } = await supabase
    .from('structured_lessons')
    .select('id, topic, lesson_number, lesson_title, estimated_minutes')
    .eq('subject', subject)
    .eq('is_published', true)
    .order('topic')
    .order('lesson_number');
  const { data: completed } = await supabase
    .from('student_lesson_progress')
    .select('lesson_id')
    .eq('student_id', studentId)
    .eq('status', 'completed');
  const completedIds = new Set((completed || []).map(c => c.lesson_id));
  const nextLesson = (allLessons || []).find(l => !completedIds.has(l.id)) || null;
  res.json({ nextLesson, subject });
});

app.get('/api/home/dashboard', authStudent, async (req, res) => {
  try {
    const daysToSPM = Math.ceil((new Date('2026-11-20') - new Date()) / (1000 * 60 * 60 * 24));
    const studentId = req.user.student_id;
    const { data: sessions } = await supabase
      .from('lesson_sessions')
      .select('duration_seconds, completed')
      .eq('student_id', studentId)
      .gte('started_at', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString());
    const { data: logins } = await supabase
      .from('student_logins')
      .select('logged_at')
      .eq('student_id', studentId)
      .order('logged_at', { ascending: false })
      .limit(30);

    let streak = 0;
    if (logins && logins.length > 0) {
      const days = new Set(logins.map(l => l.logged_at.slice(0, 10)));
      const check = new Date();
      while (days.has(check.toISOString().slice(0, 10))) {
        streak++;
        check.setDate(check.getDate() - 1);
      }
    }

    const studyMinutes = sessions
      ? Math.round(sessions.reduce((s, r) => s + (r.duration_seconds || 0), 0) / 60) : 0;
    const topicsCompleted = sessions ? sessions.filter(r => r.completed).length : 0;

    res.json({
      spm_days_remaining: daysToSPM,
      streak,
      weekly_stats: { study_minutes: studyMinutes, topics_completed: topicsCompleted },
      predicted_grade: 'B+',
      hours_to_complete: 78,
      daily_missions: [],
      resume_session: null,
    });
  } catch (e) {
    const daysToSPM = Math.ceil((new Date('2026-11-20') - new Date()) / 86400000);
    res.json({ spm_days_remaining: daysToSPM, streak: 0, weekly_stats: { study_minutes: 0, topics_completed: 0 }, predicted_grade: 'B+', hours_to_complete: 78, daily_missions: [], resume_session: null });
  }
});

app.get('/api/student/notifications', authStudent, async (req, res) => {
  res.json({ notifications: [] });
});

app.listen(PORT, () => {
  console.log(`\nLearnova v2.2 running on port ${PORT}`);
  console.log(`FAQ loaded: ${Object.keys(FAQ_DATA).length} Maths questions`);
  console.log(`Multi-subject FAQ: faq_cache table (8 subjects)`);
  console.log(`PregenLookup: question_bank + faq_bank + concept_explanations (ID + MY)`);
  console.log(`Claude API: ${claudeApiKey ? 'ready' : 'FAQ-only mode'}\n`);
});
// â”€â”€ MARKING ENGINE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function markWorking(studentWorking, markingKeywords, correctAnswer, studentAnswer) {
  const working = (studentWorking || '').toLowerCase();
  const answer = (studentAnswer || '').toLowerCase().trim();
  const correct = (correctAnswer || '').toLowerCase().trim();
  const answerCorrect = answer === correct || answer.replace(/\s/g,'') === correct.replace(/\s/g,'');
  const keywords = markingKeywords || [];
  const foundKeywords = keywords.filter(kw => working.includes(kw.toLowerCase()));
  const methodScore = keywords.length > 0 ? Math.round((foundKeywords.length / keywords.length) * 100) : (answerCorrect ? 100 : 0);
  let feedback = '';
  if (answerCorrect && methodScore >= 60) feedback = 'Correct answer with good working shown.';
  else if (answerCorrect) feedback = 'Correct answer! Try showing more working steps next time.';
  else if (!answerCorrect && methodScore >= 60) feedback = 'Good method! Right approach but check your calculation.';
  else if (!answerCorrect && methodScore > 0) feedback = 'Partially correct method. Review the worked solution below.';
  else feedback = 'Incorrect. Study the worked solution carefully.';
  return { answerCorrect, methodScore, feedback };
}

app.post('/api/quiz/:id/submit', authStudent, async (req, res) => {
  try {
    const { answers, working_notes } = req.body;
    const { data: quiz } = await supabase.from('quizzes').select('*').eq('id', req.params.id).single();
    if (!quiz) return res.status(404).json({ error: 'Quiz not found' });
    const { data: questions } = await supabase.from('quiz_questions')
      .select('id, correct_answer, worked_solution, marking_keywords, question_type')
      .eq('quiz_id', req.params.id);
    if (!questions || questions.length === 0) return res.status(404).json({ error: 'No questions found' });

    let correct = 0;
    let totalMethodScore = 0;
    const questionFeedback = {};

    for (const q of questions) {
      const studentAnswer = answers[q.id] || answers[q.id.toString()] || '';
      const studentWorking = working_notes ? (working_notes[q.id] || working_notes[q.id.toString()] || '') : '';
      const marking = markWorking(studentWorking, q.marking_keywords, q.correct_answer, studentAnswer);
      if (marking.answerCorrect) correct++;
      totalMethodScore += marking.methodScore;
      questionFeedback[q.id] = {
        correct: marking.answerCorrect,
        correct_answer: q.correct_answer,
        worked_solution: q.worked_solution || '',
        feedback: marking.feedback,
        method_score: marking.methodScore,
      };
    }

    const avgMethodScore = Math.round(totalMethodScore / questions.length);
    const percentage = Math.round((correct / questions.length) * 100);
    const overallFeedback = correct === questions.length ? 'Perfect score! Excellent work!' :
      percentage >= 70 ? 'Great work! Review the questions you missed.' :
      percentage >= 50 ? 'Good effort. Study the worked solutions carefully.' :
      'Keep practising! Review all the worked solutions below.';

    const workingText = working_notes ? Object.values(working_notes).filter(Boolean).join('\n---\n') : '';

    await supabase.from('quiz_results').insert({
      student_id: req.user.id,
      quiz_id: req.params.id,
      score: correct,
      total_questions: questions.length,
      working_notes: workingText,
      method_feedback: overallFeedback,
      method_score: avgMethodScore,
    });

    // CP mastery tracking for Indonesian students
    if (quiz.country === 'ID' || req.body.country === 'ID') {
      const fase = (quiz.form || '').includes('10') ? 'Fase E' : 'Fase F';
      const cpCode = `${quiz.subject || 'General'}:${quiz.topic || 'General'}`;
      const isCorrect = percentage >= 70;
      updateCPMastery(req.user.id, quiz.subject, fase, cpCode, isCorrect).catch(() => {});
    }

    res.json({
      score: correct,
      total: questions.length,
      percentage,
      method_score: avgMethodScore,
      overall_feedback: overallFeedback,
      question_feedback: questionFeedback,
    });
    triggerBackup();
  } catch (e) {
    console.error('Quiz submit error:', e);
    res.status(500).json({ error: e.message });
  }
});















