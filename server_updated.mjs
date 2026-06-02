import learningEngineRouter, { init as initLearningEngine } from './learning_engine.mjs';
import PregenLookup from './PregenLookup.mjs';
import express from 'express';
import { createClient } from '@supabase/supabase-js';
import jwt from 'jsonwebtoken';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import rateLimit from 'express-rate-limit';
import { exec } from 'child_process';

const app = express();
const PORT = process.env.PORT || 3000;

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;
const claudeApiKey = process.env.CLAUDE_API_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error('FATAL: Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

console.log('Supabase connected:', supabaseUrl);
// Service role key bypasses RLS — correct for a trusted backend server
const supabase = createClient(supabaseUrl, supabaseKey);
const pregen = new PregenLookup(supabase);
initLearningEngine(supabase);
const JWT_SECRET = process.env.JWT_SECRET || 'learnova-dev-secret-2025';

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

// ── RATE LIMITING ─────────────────────────────────────────────────
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
// ──────────────────────────────────────────────────────────────────

app.get('/', (req, res) => res.send('Learnova API v2.2'));
app.get('/health', (req, res) => res.json({ status: 'ok', version: '2.2', timestamp: new Date() }));

// ── AUTO BACKUP ───────────────────────────────────────────────────
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

// ── FAQ DATA (Maths hardcoded, zero cost AI) ─────────────────────
const FAQ_DATA = {
  "what is a function": { answer: "A function is a relation where every input (x-value) has exactly ONE output (y-value). If one input gives two different outputs, it's NOT a function.", topic: "Functions", example: "f(x) = 2x + 1. When x = 3, f(3) = 7. Only one answer!" },
  "what is domain and range": { answer: "Domain = all possible INPUT values (x-values). Range = all possible OUTPUT values (y-values). For f(x) = sqrt(x), domain is x >= 0, range is y >= 0.", topic: "Functions", example: "f(x) = 1/x — Domain: all x except 0. Range: all y except 0." },
  "how to find inverse function": { answer: "Step 1: Replace f(x) with y. Step 2: Swap x and y. Step 3: Solve for y. Step 4: Replace y with f-inverse(x). The inverse undoes what the function does.", topic: "Functions", example: "f(x) = 2x + 3 → swap → x = 2y + 3 → f-inv(x) = (x-3)/2" },
  "what is composite function": { answer: "fg(x) means apply g first, then f. Written as f(g(x)). Work from RIGHT to LEFT.", topic: "Functions", example: "f(x)=x², g(x)=x+1. fg(x) = f(x+1) = (x+1)²" },
  "how to find fg x": { answer: "fg(x) = f(g(x)). Apply g first, substitute result into f.", topic: "Functions", example: "f(x)=3x, g(x)=x-2. fg(x) = f(x-2) = 3(x-2) = 3x-6" },
  "what is absolute value": { answer: "|x| always gives a positive value or zero. |x| = x if x >= 0, |x| = -x if x < 0. Distance from zero on number line.", topic: "Functions", example: "|5|=5, |-3|=3, |0|=0" },
  "how to graph a function": { answer: "1) Make a table of x and y values. 2) Plot points. 3) Connect smoothly. Find x-intercepts (y=0), y-intercept (x=0).", topic: "Functions", example: "f(x)=x²: x=-2→4, x=-1→1, x=0→0, x=1→1, x=2→4. U-shape parabola!" },
  "what is quadratic equation": { answer: "ax² + bx + c = 0 where a ≠ 0. Highest power is 2. Has at most 2 solutions.", topic: "Quadratic Equations", example: "x² - 5x + 6 = 0 has solutions x=2 and x=3" },
  "how to use quadratic formula": { answer: "x = (-b ± sqrt(b²-4ac)) / 2a. Identify a, b, c from ax² + bx + c = 0 and substitute.", topic: "Quadratic Equations", example: "x²-5x+6=0: a=1,b=-5,c=6. x=(5±1)/2. So x=3 or x=2" },
  "what is discriminant": { answer: "b²-4ac tells you about roots: >0 means two real roots, =0 means one repeated root, <0 means no real roots.", topic: "Quadratic Equations", example: "x²-4x+4=0: disc=16-16=0. One root: x=2" },
  "how to factorise quadratic": { answer: "Find two numbers that MULTIPLY to c and ADD to b in x²+bx+c. Write as (x+p)(x+q).", topic: "Quadratic Equations", example: "x²+5x+6: need ×=6, +=5. That's 2 and 3. Answer: (x+2)(x+3)" },
  "how to complete the square": { answer: "x²+bx+c: add (b/2)² to both sides to get (x+b/2)²=something. Then solve.", topic: "Quadratic Equations", example: "x²+6x+5=0 → (x+3)²=4 → x=-1 or x=-5" },
  "what is vertex of parabola": { answer: "Turning point of parabola. For ax²+bx+c, x-coord of vertex = -b/2a. If a>0, it's minimum. If a<0, it's maximum.", topic: "Quadratic Equations", example: "f(x)=x²-4x+3: vertex x=2, y=-1. Vertex: (2,-1)" },
  "sum and product of roots": { answer: "For ax²+bx+c=0 with roots α and β: α+β = -b/a, αβ = c/a.", topic: "Quadratic Equations", example: "x²-5x+6=0: sum=5, product=6. Roots 2,3 check: 2+3=5✓, 2×3=6✓" },
  "what are laws of indices": { answer: "aᵐ×aⁿ=aᵐ⁺ⁿ, aᵐ÷aⁿ=aᵐ⁻ⁿ, (aᵐ)ⁿ=aᵐⁿ, a⁰=1, a⁻ⁿ=1/aⁿ, a^(1/n)=nth root of a, a^(m/n)=nth root of aᵐ", topic: "Indices and Surds", example: "2³×2⁴=2⁷=128. 5⁰=1. 2⁻³=1/8" },
  "what is a surd": { answer: "An irrational square root that cannot simplify to a whole number. sqrt(2), sqrt(3), sqrt(5) are surds. sqrt(4)=2 is NOT a surd.", topic: "Indices and Surds", example: "sqrt(12)=2sqrt(3) (surd). sqrt(9)=3 (not a surd)" },
  "how to simplify surds": { answer: "Find the largest perfect square factor: sqrt(n) = sqrt(a²×m) = a×sqrt(m). Look for 4, 9, 16, 25, 36...", topic: "Indices and Surds", example: "sqrt(48)=4sqrt(3), sqrt(75)=5sqrt(3), sqrt(200)=10sqrt(2)" },
  "how to rationalise denominator": { answer: "Remove surds from denominator. For 1/sqrt(a): multiply by sqrt(a)/sqrt(a). For 1/(a+sqrt(b)): multiply by conjugate (a-sqrt(b))/(a-sqrt(b)).", topic: "Indices and Surds", example: "3/sqrt(2) = 3sqrt(2)/2. 1/(1+sqrt(3)) = (sqrt(3)-1)/2" },
  "how to add surds": { answer: "Only add LIKE surds (same number under root). Simplify first, then combine.", topic: "Indices and Surds", example: "2sqrt(3)+5sqrt(3)=7sqrt(3). sqrt(12)+sqrt(3)=2sqrt(3)+sqrt(3)=3sqrt(3)" },
  "what is negative index": { answer: "a⁻ⁿ = 1/aⁿ. Flip it! Never makes the number negative. 2⁻³ = 1/8 (still positive).", topic: "Indices and Surds", example: "3⁻²=1/9. (1/2)⁻³=8. x⁻¹=1/x" },
  "what is fractional index": { answer: "a^(m/n) = nth_root(aᵐ). Denominator=ROOT, numerator=POWER.", topic: "Indices and Surds", example: "8^(2/3)=(cube_root 8)²=2²=4. 27^(1/3)=3. 16^(3/4)=2³=8" },
  "what is linear inequality": { answer: "Like a linear equation but with <, >, ≤, ≥ instead of =. Solution is a RANGE of values.", topic: "Linear Inequalities", example: "2x+3>7 → 2x>4 → x>2" },
  "how to solve linear inequality": { answer: "Solve like equation EXCEPT: multiplying or dividing by NEGATIVE number FLIPS the inequality sign!", topic: "Linear Inequalities", example: "-2x>6 → x<-3 (flipped!). But 2x>6 → x>3 (no flip)" },
  "how to show inequality on number line": { answer: "Open circle = strict inequality (< or >) endpoint NOT included. Closed circle = ≤ or ≥ endpoint IS included.", topic: "Linear Inequalities", example: "x>3: open circle at 3, arrow right. x≤-1: closed circle at -1, arrow left." },
  "what is combined inequality": { answer: "Has TWO conditions like a<x<b. Solve each part separately, find where BOTH satisfied.", topic: "Linear Inequalities", example: "-2<2x+4≤10 → -3<x≤3" },
  "what is arithmetic progression": { answer: "AP: sequence where each term increases by constant COMMON DIFFERENCE d. General term: Tn = a+(n-1)d", topic: "Progressions", example: "3,7,11,15 is AP with a=3, d=4. T₅=3+4(4)=19" },
  "what is common difference": { answer: "d = any term minus the previous term. Constant throughout AP. Can be positive, negative, or zero.", topic: "Progressions", example: "5,8,11: d=3. 20,15,10: d=-5" },
  "sum of arithmetic progression": { answer: "Sn = n/2 × (2a+(n-1)d) OR Sn = n/2 × (first+last). Use whichever info you have!", topic: "Progressions", example: "AP: 2,5,8. S10 = 10/2×(4+27) = 155" },
  "what is geometric progression": { answer: "GP: each term multiplied by constant RATIO r. General term: Tn = ar^(n-1)", topic: "Progressions", example: "2,6,18,54 is GP with a=2, r=3. T₅=2×81=162" },
  "what is common ratio": { answer: "r = any term divided by previous term. If |r|<1 terms decrease. If |r|>1 terms grow.", topic: "Progressions", example: "4,12,36: r=3. 100,10,1: r=0.1" },
  "sum of geometric progression": { answer: "Sn = a(rⁿ-1)/(r-1) when r>1. Sn = a(1-rⁿ)/(1-r) when r<1.", topic: "Progressions", example: "GP: 3,6,12. S5 = 3(32-1)/1 = 93" },
  "sum to infinity gp": { answer: "For |r|<1: S∞ = a/(1-r). Only works when -1<r<1 (terms shrink to zero).", topic: "Progressions", example: "1,0.5,0.25: S∞=1/(1-0.5)=2" },
  "how to find nth term": { answer: "AP: Tn=a+(n-1)d. GP: Tn=ar^(n-1). Identify AP or GP first: constant difference=AP, constant ratio=GP.", topic: "Progressions", example: "T8 of 2,5,8: a=2,d=3, T8=2+7(3)=23" },
  "what is a matrix": { answer: "Rectangular array of numbers in rows and columns. Order = m×n (rows × columns).", topic: "Matrices", example: "2×3 matrix has 2 rows, 3 columns: [[1,2,3],[4,5,6]]" },
  "how to multiply matrices": { answer: "(m×n)×(n×p)=(m×p). Inner dimensions must match. Row times Column: multiply element by element then add.", topic: "Matrices", example: "[[1,2],[3,4]]×[[5],[6]] = [[17],[39]]" },
  "what is inverse matrix": { answer: "A×A⁻¹=I. For 2×2: A⁻¹=(1/det)×[[d,-b],[-c,a]] where det=ad-bc.", topic: "Matrices", example: "A=[[2,1],[5,3]]: det=1. A⁻¹=[[3,-1],[-5,2]]" },
  "what is determinant": { answer: "For [[a,b],[c,d]]: det = ad-bc. If det=0, no inverse exists (singular matrix).", topic: "Matrices", example: "[[3,2],[1,4]]: det=12-2=10. [[2,4],[1,2]]: det=4-4=0 (no inverse)" },
  "what is gradient of line": { answer: "m = (y₂-y₁)/(x₂-x₁) = rise/run. Positive=up, Negative=down, Zero=horizontal, Undefined=vertical.", topic: "Coordinate Geometry", example: "Points (1,2)(3,6): m=(6-2)/(3-1)=2" },
  "equation of straight line": { answer: "y=mx+c (gradient-intercept), y-y₁=m(x-x₁) (point-slope), ax+by=c (general). m=gradient, c=y-intercept.", topic: "Coordinate Geometry", example: "m=3, passes (1,2): y=3x-1" },
  "how to find midpoint": { answer: "M = ((x₁+x₂)/2, (y₁+y₂)/2). Average the coordinates.", topic: "Coordinate Geometry", example: "Midpoint of (2,4)(8,10): M=(5,7)" },
  "distance between two points": { answer: "d = sqrt((x₂-x₁)²+(y₂-y₁)²). Pythagoras theorem!", topic: "Coordinate Geometry", example: "(1,2) to (4,6): sqrt(9+16)=5" },
  "parallel and perpendicular lines": { answer: "Parallel: same gradient (m₁=m₂). Perpendicular: m₁×m₂=-1, so m₂=-1/m₁.", topic: "Coordinate Geometry", example: "Line y=2x+3. Parallel: y=2x-1. Perpendicular: y=-x/2+5" },
  "what is mean median mode": { answer: "Mean=sum/count. Median=middle value when sorted. Mode=most frequent value.", topic: "Statistics", example: "3,5,5,7,9: Mean=5.8, Median=5, Mode=5" },
  "what is standard deviation": { answer: "Measures how spread out data is from mean. Small SD=data close to mean. Large SD=widely spread.", topic: "Statistics", example: "SD=0 means all values identical. SD=5 means values typically 5 units from mean." },
  "soh cah toa": { answer: "Sin=Opposite/Hypotenuse, Cos=Adjacent/Hypotenuse, Tan=Opposite/Adjacent. Right-angled triangles only!", topic: "Trigonometry", example: "Opp=3, Hyp=5, Adj=4: Sin=0.6, Cos=0.8, Tan=0.75" },
  "sine rule": { answer: "a/sinA=b/sinB=c/sinC. Use with 2 angles+1 side, or 2 sides+non-included angle.", topic: "Trigonometry", example: "a/sin30°=b/sin45°. If a=5: b=5×sin45°/sin30°≈7.07" },
  "cosine rule": { answer: "a²=b²+c²-2bc·cosA. Use with 3 sides or 2 sides+included angle. cosA=(b²+c²-a²)/(2bc)", topic: "Trigonometry", example: "b=5,c=7,A=60°: a²=74-35=39, a≈6.24" },
  "area of triangle": { answer: "Area=½ab·sinC for any triangle. For right triangles: ½×base×height.", topic: "Trigonometry", example: "Sides 6,8 with 30° between: Area=½×6×8×0.5=12 units²" },
  "equation of circle": { answer: "(x-h)²+(y-k)²=r². Centre (h,k), radius r. Or x²+y²+2gx+2fy+c=0, centre(-g,-f), radius=sqrt(g²+f²-c).", topic: "Circles", example: "Centre(3,-2), r=5: (x-3)²+(y+2)²=25" },
  "what is a vector": { answer: "Has both MAGNITUDE and DIRECTION. |a|=magnitude. -a reverses direction.", topic: "Vectors", example: "A(1,2) to B(4,6): AB=(3,4). |AB|=5" },
  "how to add vectors": { answer: "Add tip-to-tail. Algebraically: (a₁,a₂)+(b₁,b₂)=(a₁+b₁,a₂+b₂).", topic: "Vectors", example: "(2,3)+(4,-1)=(6,2). (5,7)-(2,3)=(3,4)" },
  "how to study maths": { answer: "1) Understand concepts, don't memorise. 2) Practice daily. 3) Do past papers. 4) Focus on weak topics. 5) Show all working for method marks!", topic: "Study Tips", example: "20 mins daily practice beats 3 hours on exam eve!" },
  "how to pass spm maths": { answer: "1) Master Form 4 topics. 2) Do 5+ past papers. 3) Time yourself. 4) Never leave blank. 5) Check your work!", topic: "Study Tips", example: "Students who do 5+ past papers average 30% higher marks." },
  "what is probability": { answer: "P(event) = favourable outcomes / total outcomes. Always between 0 and 1. P=0 means impossible, P=1 means certain.", topic: "Probability", example: "P(heads)=1/2. P(rolling 6)=1/6. P(red from 3R,2B)=3/5" },
  "what is permutation": { answer: "Arrangement where ORDER matters. nPr = n!/(n-r)!. Used for passwords, rankings, sequences.", topic: "Probability", example: "3 people in 3 seats: 3P3=3!=6 arrangements" },
  "what is combination": { answer: "Selection where ORDER does NOT matter. nCr = n!/(r!(n-r)!). Used for choosing teams, committees.", topic: "Probability", example: "Choose 3 from 5: 5C3=10 ways" },
  "what is normal distribution": { answer: "Bell-shaped curve symmetric about mean. 68% data within 1 SD, 95% within 2 SD, 99.7% within 3 SD.", topic: "Statistics", example: "Height data: mean=165cm, SD=5cm. 68% have height 160-170cm" },
  "what is set notation": { answer: "∪=union (or), ∩=intersection (and), A'=complement (not A), ∅=empty set, ∈=is element of, ⊂=subset.", topic: "Sets", example: "A={1,2,3}, B={2,3,4}. A∪B={1,2,3,4}. A∩B={2,3}" },
  "what is venn diagram": { answer: "Circles overlapping to show sets. Overlapping region=intersection. Total area=union. Outside all circles=complement.", topic: "Sets", example: "Two circles A and B: middle overlap is A∩B, everything is A∪B" },
  "how to solve simultaneous equations": { answer: "Two methods: Substitution (express one variable, substitute) or Elimination (add/subtract to remove one variable).", topic: "Simultaneous Equations", example: "x+y=5, x-y=1. Add: 2x=6, x=3. So y=2." },
  "what is linear programming": { answer: "Optimising (max or min) an objective function subject to constraints (inequalities). Plot region, find vertices, test objective at each vertex.", topic: "Linear Programming", example: "Maximise P=3x+2y subject to x+y≤10, x≥0, y≥0. Check corner points." },
  "what is a logarithm": { answer: "log_a(x)=y means a^y=x. Log is the inverse of exponent. log_10 is common log, ln is natural log (base e).", topic: "Logarithms", example: "log_2(8)=3 because 2³=8. log_10(100)=2 because 10²=100" },
  "laws of logarithms": { answer: "log(AB)=logA+logB, log(A/B)=logA-logB, log(Aⁿ)=nlogA, log_a(a)=1, log_a(1)=0, change base: log_a(b)=log(b)/log(a)", topic: "Logarithms", example: "log(6)=log(2×3)=log2+log3. log(2⁵)=5log2" },
  "how to solve exponential equation": { answer: "If bases can be matched: equal bases means equal powers. If not, take log of both sides.", topic: "Logarithms", example: "2^x=8 → 2^x=2³ → x=3. 3^x=10 → xlog3=log10 → x=1/log3≈2.096" },
  "what is a polynomial": { answer: "Expression with non-negative integer powers: anxⁿ+...+a1x+a0. Degree=highest power. Polynomial division uses long division or synthetic.", topic: "Polynomials", example: "3x³-2x²+5x-1 is degree 3 polynomial" },
  "remainder theorem": { answer: "When polynomial f(x) divided by (x-a), remainder = f(a). No need to do full division!", topic: "Polynomials", example: "f(x)=x³-2x+1 divided by (x-2): remainder=f(2)=8-4+1=5" },
  "factor theorem": { answer: "If f(a)=0, then (x-a) is a factor of f(x). Use to find factors without full division.", topic: "Polynomials", example: "f(x)=x³-6x²+11x-6. f(1)=0, so (x-1) is a factor" },
  "what is partial fractions": { answer: "Breaking a complex fraction into simpler parts. For (px+q)/((ax+b)(cx+d)) = A/(ax+b) + B/(cx+d). Find A,B by substituting.", topic: "Partial Fractions", example: "5/(x²-1) = A/(x-1) + B/(x+1). Solve: A=5/2, B=-5/2" },
  "what is binomial expansion": { answer: "(a+b)ⁿ = sum of nCr × aⁿ⁻ʳ × bʳ for r=0 to n. Coefficients from Pascal's Triangle or nCr.", topic: "Binomial Expansion", example: "(1+x)³ = 1+3x+3x²+x³. Coefficients: 1,3,3,1 from Pascal's row 3" },
  "what is differentiation": { answer: "Finding the rate of change (gradient) of a function. d/dx(xⁿ)=nxⁿ⁻¹. Differentiation = finding f'(x) = slope at any point.", topic: "Differentiation", example: "f(x)=x³: f'(x)=3x². At x=2: gradient=12" },
  "what is integration": { answer: "Reverse of differentiation. ∫xⁿ dx = xⁿ⁺¹/(n+1) + C. Definite integral gives area under curve between two x values.", topic: "Integration", example: "∫x² dx = x³/3 + C. ∫₀² x² dx = [x³/3]₀² = 8/3" },
  "how to find stationary points": { answer: "Set f'(x)=0 and solve for x. Then find y-value. Use f''(x) to determine: f''(x)>0 means minimum, f''(x)<0 means maximum.", topic: "Differentiation", example: "f(x)=x²-4x: f'(x)=2x-4=0 → x=2. f''(2)=2>0 so minimum at (2,-4)" }
};

// ── FUZZY MATCH for hardcoded FAQ ────────────────────────────────
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

// ── SEARCH faq_cache table (multi-subject) ───────────────────────
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

// ── AI ASK ENDPOINT (updated: FAQ → faq_cache → Claude) ─────────
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

// ── FAQ LIST (combined: hardcoded + faq_cache) ───────────────────
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

// ── SUBJECTS LIST endpoint ───────────────────────────────────────
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

// ── STUDENT ROUTES ────────────────────────────────────────────────
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
    const { data: student } = await supabase.from('students').select('*').eq('id', req.user.student_id).single();
    const { data: results } = await supabase.from('quiz_results').select('score, total, percentage, created_at').eq('student_id', req.user.student_id);
    const { data: sessions } = await supabase.from('study_sessions').select('duration_minutes, topic').eq('student_id', req.user.student_id);
    const totalQuizzes = results?.length || 0;
    const avgScore = totalQuizzes > 0 ? Math.round(results.reduce((s, r) => s + r.percentage, 0) / totalQuizzes) : 0;
    const totalStudyTime = sessions?.reduce((s, ss) => s + (ss.duration_minutes || 0), 0) || 0;
    res.json({ student: { id: student.id, name: student.name, email: student.email, form_level: student.form_level, selected_subjects: student.selected_subjects, onboarding_completed: student.onboarding_completed, current_topic: student.current_topic, profile_complete: !!(student.form_level && student.selected_subjects?.length) }, stats: { totalQuizzes, avgScore, totalStudyTime } });
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

// ── LESSON ROUTES ─────────────────────────────────────────────────
app.get('/api/lessons', async (req, res) => {
  try {
    const { subject, form_level, limit } = req.query;
    const cols = 'id,title,topic,subject,form_level,teacher_id,created_at,introduction,content,summary,worked_examples,common_mistakes,keywords';
    let query = supabase.from('lessons').select(cols).eq('is_published', true);
    if (subject) query = query.eq('subject', subject);
    if (form_level) query = query.eq('form_level', form_level);
    query = query.order('created_at', { ascending: false });
    if (limit) query = query.limit(parseInt(limit));
    const { data, error } = await query;
    if (error) return res.status(400).json({ error: error.message });
    res.json(data || []);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.get('/api/lessons/:id', async (req, res) => {
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

// ── QUIZ ROUTES ───────────────────────────────────────────────────
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

// ── TEACHER ROUTES ────────────────────────────────────────────────
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

// ── PARENT ROUTES ─────────────────────────────────────────────────
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
    const { data: children } = await supabase.from('students').select('*').eq('parent_email', req.user.email);
    if (!children?.length) return res.json({ children: [], message: 'No linked children. Ask your child to sign up with your email address.' });
    const dashData = await Promise.all(children.map(async (child) => {
      const { data: results } = await supabase.from('quiz_results').select('*, quizzes(title,topic)').eq('student_id', child.id).order('created_at', { ascending: false }).limit(10);
      const { data: sessions } = await supabase.from('study_sessions').select('topic,duration_minutes,created_at').eq('student_id', child.id).order('created_at', { ascending: false }).limit(20);
      const { data: views } = await supabase.from('lesson_views').select('lesson_id,created_at').eq('student_id', child.id).order('created_at', { ascending: false }).limit(10);
      const totalQuizzes = results?.length || 0;
      const avgScore = totalQuizzes > 0 ? Math.round(results.reduce((s, r) => s + r.percentage, 0) / totalQuizzes) : 0;
      const totalStudyMins = sessions?.reduce((s, ss) => s + (ss.duration_minutes || 0), 0) || 0;
      const topicScores = {};
      (results || []).forEach(r => { const t = r.quizzes?.topic || 'General'; if (!topicScores[t]) topicScores[t] = { total: 0, count: 0 }; topicScores[t].total += r.percentage; topicScores[t].count++; });
      const topicBreakdown = Object.entries(topicScores).map(([topic, s]) => ({ topic, avgScore: Math.round(s.total / s.count) })).sort((a, b) => b.avgScore - a.avgScore);
      const lastActivity = sessions?.[0]?.created_at || results?.[0]?.created_at;
      const daysInactive = lastActivity ? Math.floor((Date.now() - new Date(lastActivity)) / 86400000) : null;
      return { student: { id: child.id, name: child.name, email: child.email }, stats: { totalQuizzes, avgScore, totalStudyMins, daysInactive }, recentResults: results?.slice(0, 5) || [], topicBreakdown, recentSessions: sessions?.slice(0, 5) || [] };
    }));
    res.json({ children: dashData });
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

// ── LEADERBOARD ───────────────────────────────────────────────────
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


// ── PRICING ───────────────────────────────────────────────────────
app.get('/api/pricing', async (req, res) => {
  try {
    const { data } = await supabase.from('subject_pricing').select('*').eq('is_active', true).order('subject');
    res.json({ pricing: data || [] });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ── SUBSCRIPTIONS ─────────────────────────────────────────────────
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

// ── SPONSORSHIP ───────────────────────────────────────────────────
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

// ── TEACHER PROFILE ───────────────────────────────────────────────
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

// ── PARENT-CHILD LINK ─────────────────────────────────────────────
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

app.post('/api/tts', async (req, res) => {
  try {
    const { text, voice = 'nova', language = 'bm' } = req.body;
    if (!text) return res.status(400).json({ error: 'text required' });
    const speedMap = { bm: 0.80, ms: 0.80, id: 0.80, en: 0.85, zh: 0.85, ta: 0.85 };
    const speed = speedMap[language] || 0.80;
    const r = await fetch('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'tts-1', input: text.slice(0, 4000), voice, speed }),
    });
    if (!r.ok) return res.status(500).json({ error: 'TTS failed' });
    const buf = Buffer.from(await r.arrayBuffer());
    res.set('Content-Type', 'audio/mpeg');
    res.send(buf);
  } catch (e) { res.status(500).json({ error: e.message }); }
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

// -- TTS (duplicate removed — active route is above) -----------

// -- TUTOR TOPICS ----------------------------------------------
app.get('/api/tutor/topics', async (req, res) => {
  try {
    const { subject } = req.query;
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

// Strip JSON artifacts from a reply string — catches double-encoding where
// Claude wraps its reply text inside another JSON object
function safeReply(text) {
  if (!text || typeof text !== 'string') return text || '';
  const trimmed = text.trim();
  if (trimmed.startsWith('{')) {
    try {
      const inner = JSON.parse(trimmed);
      const extracted = inner.reply || inner.answer || inner.content || inner.text || inner.message;
      if (extracted && typeof extracted === 'string') return extracted;
    } catch {}
  }
  return text;
}

app.post('/api/tutor/session', authStudent, async (req, res) => {
  try {
    const { subject, topic, message, history, phase, segment, language, activeQuestion, question } = req.body;
    const isBm = language === 'ms' || language === 'bm';
    const lang = isBm ? 'Bahasa Malaysia' : 'English';

    const isBmSubject = subject === 'Bahasa Malaysia' || subject === 'Bahasa Melayu' ||
      !!(topic && (topic.includes('Bahasa Malaysia') || topic.includes('Bahasa Melayu')));

    // Language-matched quick-reply suggestions — BM subject always gets BM replies
    const suggestions = isBmSubject
      ? ['Faham! Teruskan.', 'Boleh beri contoh lain?', 'Saya kurang faham bahagian ini.']
      : isBm
      ? ['Faham! Teruskan.', 'Boleh tunjukkan contoh?', 'Saya kurang faham bahagian ini.']
      : ['I understand, please continue.', 'Can you show an example?', "I'm not sure about this part."];

    // ── Q&A mode: free question, no active topic ──────────────────
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
        parsed = { answer: claudeRes.content[0].text, example: null, related_questions: [] };
      }
      return res.json({ ...parsed, source: 'claude' });
    }

    // ── Pregen: serve FAQ or explanation before calling Claude ───
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

    // ── Tutor mode: guided lesson with topic ──────────────────────
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

    // ── Per-phase token limits (prevent content dumps) ─────────────
    const phaseTokens = { intro: 500, teach: 480, check: 380, quiz_setup: 380, quiz_answer: 380, done: 380 };
    const maxTokens = phaseTokens[currentPhase] || 420;

    // ── Personality styles ─────────────────────────────────────────
    const personalityStyles = {
      friendly:  'Warm, fun, lots of encouragement, uses relatable analogies. Celebrate every correct answer. Use casual Malaysian phrases occasionally.',
      balanced:  'Professional yet approachable. Clear pacing. Steady encouragement. Neither too strict nor too casual.',
      strict:    'High expectations, minimal small talk, demands precise answers. Still respectful but very focused.',
      military:  'Very direct, drills concepts with repetition, expects exact answers. No wasted words. Discipline-first.'
    };
    const personalityDesc = personalityStyles[personalityMode] || personalityStyles.balanced;

    // ── Phase-specific teaching instructions (HARDCODED PEDAGOGY) ──
    const phaseInstructions = {
      intro: `=== LESSON 1: INTRODUCTION PHASE ===
YOUR TASK (do ALL of these, nothing more):
1. Write ONE curiosity hook — a surprising fact, relatable scenario, or real-life connection to "${topic}" in ${subject || 'Mathematics'} (1-2 sentences only)
2. Ask ONE activation question to find out what the student already knows (e.g. "Before we start, what do you already know about this?")
3. STOP. Do NOT explain the concept yet.
→ Set "phase": "teach"
→ Keep reply under 80 words`,

      teach: `=== LESSON 2: TEACHING PHASE (Segment ${currentSegment}) ===
YOUR TASK (ONE concept per response — no more):
1. Introduce ONE sub-concept or ONE step of "${topic}" — not the whole topic
2. Show ONE worked example, step-by-step with working shown clearly
3. Explain WHY this step works and WHEN to use it
4. Name ONE common mistake SPM students make here
5. End with a direct comprehension question to the student (e.g. "Now, can you tell me WHY we do step 2?" or "What do you think comes next?")
→ Set "isCheckIn": true
→ Set "phase": "check"
→ Keep reply under 160 words
CRITICAL: Do NOT explain the next concept. Do NOT summarise the whole topic. ONE concept, then STOP.`,

      check: `=== CHECK PHASE: ASSESSING UNDERSTANDING ===
The student has just responded. Assess their understanding:

IF STUDENT ANSWERED CORRECTLY:
- Praise in ONE sentence (genuine, not hollow)
- If segment < 3: introduce the NEXT concept → set "phase": "teach"
- If segment >= 3: move to exam practice → set "phase": "quiz_setup"

IF STUDENT ANSWERED WRONGLY OR IS CONFUSED:
- DO NOT give the answer yet
- Give ONE specific hint that points them in the right direction
- Ask a simpler guiding question ("What if I told you that...?")
- Stay in "phase": "check"

IF STUDENT SAYS "I DON'T KNOW":
- Ask an even simpler scaffolding question first
- Break it into the smallest possible step
- Stay in "phase": "check"

→ Keep reply under 130 words`,

      quiz_setup: `=== LESSON 3: EXAM PRACTICE PHASE ===
YOUR TASK:
1. Tell student: "Let's try an SPM-style question. Take your time and think before answering."
2. Create ONE SPM-style question on "${topic}" in ${subject || 'Mathematics'}
3. For MCQ: set activeQuestion with 4 options (A/B/C/D), correct answer, and a short explanation
4. The question should match the difficulty and format of actual SPM past-year papers
5. Add exam tip: mention which SPM paper this type appears in (Paper 1/Paper 2)
→ Set "isCheckIn": true
→ Set "phase": "quiz_answer"
→ Keep reply (excluding activeQuestion) under 80 words`,

      quiz_answer: `=== QUIZ ANSWER PHASE ===
The student has answered the MCQ. Assess their answer:

IF CORRECT:
- Confirm it enthusiastically
- Explain WHY it is correct step-by-step (SPM marking-scheme style — show how marks are awarded)
- Set "phase": "done"

IF WRONG:
- DO NOT reveal the answer immediately
- Ask: "Interesting choice — what was your thinking for that option?"
- After they explain: guide them to see the error
- Only reveal correct answer + full working after student attempts to reason
- Set "phase": "done" once fully resolved

→ Keep reply under 130 words`,

      done: `=== WRAP-UP PHASE ===
YOUR TASK:
1. Summarise "${topic}" in EXACTLY 3 bullet points using exam-ready language
2. Give ONE specific SPM exam tip for this topic (e.g. "In Paper 2 Section B, always show full working for...")
3. Ask: "Would you like to try more practice questions, revisit any part, or move to a new topic?"
→ Set "phase": "done"
→ Keep reply under 120 words`
    };

    const currentPhaseInstructions = isConfused
      ? `=== CONFUSION DETECTED — OVERRIDE NORMAL FLOW ===
The student is confused. Drop everything else and do this:
1. Acknowledge confusion warmly (1 sentence)
2. Re-explain the LAST concept using a COMPLETELY DIFFERENT method:
   - If you used formula: now use a real-life analogy
   - If you used steps: now use a visual/diagram description
   - If abstract: now use numbers first, then generalise
3. Ask a simpler, more guided question than before
→ Stay in current phase: "${currentPhase}"
→ Keep reply under 130 words`
      : (phaseInstructions[currentPhase] || phaseInstructions.teach);

    let systemPrompt = `ABSOLUTE RULE — YOU ARE TEACHING: ${subject || 'Mathematics'} — ${topic}
You must ONLY teach content related to "${topic}" in ${subject || 'Mathematics'}.
NEVER introduce a new topic. NEVER ask "What do you want to learn?". NEVER restart the session.
You are mid-session. The student has already chosen their topic.

You are Nova, a Learnova AI tutor for Malaysian SPM students.

==================================================
WHO YOU ARE — NON-NEGOTIABLE
==================================================
You are NOT a chatbot. You are NOT ChatGPT. You are NOT an answer generator.
You behave like an experienced Malaysian tuition teacher teaching a real student.
You teach the way tuition teachers in Malaysia teach — patient, structured, step-by-step.

Teaching personality: ${personalityDesc}
Subject: ${subject || 'Mathematics'}
Topic: ${topic}
Respond in: ${lang}

==================================================
CORE LEARNOVA TEACHING PRINCIPLES — ALWAYS ENFORCED
==================================================
1. NEVER dump the full topic explanation in one response. ONE concept per response, then STOP.
2. Always explain WHY a step is used, WHEN to use it, and WHAT mistakes students make.
3. After every teaching segment, ask the student a question. Do not continue until they respond.
4. If student is WRONG: give a hint, not the answer. Make them think first.
5. If student is CONFUSED: switch method entirely. Use analogy, diagram description, or simpler numbers.
6. If student goes off-topic: gently redirect — "Let's master this first before moving on 😊"
7. Match SPM exam format, marking scheme, and Paper 1/Paper 2 expectations.
8. Use Malaysian student-friendly language. BM/Manglish phrases are welcome occasionally.
9. Every response MUST end with either a question to the student OR a clear next action.
10. UNDERSTANDING > MEMORISATION. THINKING > COPYING. GUIDANCE > ANSWERS.

==================================================
LESSON FLOW (ENFORCED SEQUENCE)
==================================================
Lesson 1 (intro): Hook → activate prior knowledge → STOP
Lesson 2 (teach × 3): ONE concept → worked example → common mistake → comprehension question → STOP → assess answer → repeat
Lesson 3 (quiz): SPM-style question → student answers → mark it with scheme → summarise

==================================================
CURRENT PHASE INSTRUCTIONS
==================================================
${currentPhaseInstructions}

==================================================
ANTI-CONTENT-DUMP RULES — HARD LIMITS
==================================================
- NEVER list all sub-topics in one message
- NEVER give a full lesson summary before teaching
- NEVER pre-answer questions the student hasn't asked yet
- NEVER write more than the word limit specified above
- If you catch yourself about to explain more than ONE concept: STOP, cut it, save it for next turn
- NEVER output JSON, code, curly braces {}, brackets [], or any programming syntax in your reply text
- NEVER show teaching instructions, phase descriptions, or response format examples to the student
- ONLY write natural conversational sentences exactly as a teacher would speak out loud

==================================================
RESPONSE FORMAT — JSON ONLY, NO MARKDOWN OUTSIDE "reply"
==================================================
{"reply":"...use **bold** for key terms, use newlines for steps...","phase":"next_phase_name","segment":${currentSegment + 1},"suggestedResponses":["from student perspective 1","from student perspective 2","from student perspective 3"],"isCheckIn":false,"activeQuestion":null}

activeQuestion format (MCQ only):
{"question":"full question text","options":{"A":"...","B":"...","C":"...","D":"..."},"correct":"A","explanation":"why A is correct, step by step"}

suggestedResponses must be from the STUDENT's perspective and written in ${lang}.
${isBm ? 'Examples (Bahasa Malaysia):\n- "Faham! Teruskan."\n- "Saya kurang faham bahagian ini."\n- "Jawapan saya [X], betul ke?"\n- "Boleh tunjukkan contoh lain?"' : 'Examples (English):\n- "I understand! Please continue."\n- "I\'m not sure about [specific part]"\n- "My answer is [X], is that right?"\n- "Can you show another example?"'}`;

    // Append strict Bahasa Malaysia rules when subject is BM
    if (isBmSubject) {
      systemPrompt += `

==================================================
PERATURAN MUTLAK — BAHASA MALAYSIA
==================================================
Subjek ini adalah Bahasa Malaysia.

1. WAJIB menggunakan Bahasa Malaysia SEPENUHNYA dalam SEMUA respons tanpa pengecualian.

2. DILARANG SAMA SEKALI mencampurkan bahasa Inggeris dalam ayat — tiada code-switching, tiada 'Bahasa Malaysia words' diikuti English words.

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
        // Parse teaching_sequence — may be stored as a JSON string (array of phase objects)
        let teachingOrder = 'konsep -> contoh -> latihan';
        if (pedagogy.teaching_sequence) {
          if (typeof pedagogy.teaching_sequence === 'string') {
            try {
              const seq = JSON.parse(pedagogy.teaching_sequence);
              if (Array.isArray(seq)) {
                teachingOrder = seq.map((s, i) => `${i + 1}. ${s.concept || s.name || s.title || JSON.stringify(s)}`).join(' → ');
              } else {
                teachingOrder = String(pedagogy.teaching_sequence);
              }
            } catch { teachingOrder = String(pedagogy.teaching_sequence); }
          } else if (Array.isArray(pedagogy.teaching_sequence)) {
            teachingOrder = pedagogy.teaching_sequence.map((s, i) => `${i + 1}. ${s.concept || s.name || s.title || s}`).join(' → ');
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
    const userMsg = message === 'start'
      ? `Start teaching me about "${topic}" in ${subject}. Begin with the intro phase.`
      : (message || 'continue');
    msgs.push({ role: 'user', content: userMsg });

    const claudeRes = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: maxTokens,
      system: systemPrompt,
      messages: msgs,
    });

    let parsed;
    try {
      const text = claudeRes.content[0].text.trim();
      const match = text.match(/\{[\s\S]*\}/);
      parsed = JSON.parse(match ? match[0] : text);
    } catch {
      parsed = {
        reply: safeReply(claudeRes.content[0].text),
        phase: currentPhase === 'intro' ? 'teach' : currentPhase,
        segment: currentSegment + 1,
        suggestedResponses: suggestions,
        isCheckIn: false, activeQuestion: null,
      };
    }
    if (parsed.reply) parsed.reply = safeReply(parsed.reply);
    triggerBackup();
    return res.json({ ...parsed, source: 'claude' });
  } catch (e) {
    console.error('Tutor session error:', e);
    res.status(500).json({ error: e.message });
  }
});

// ── KM CURRICULUM HELPERS ────────────────────────────────────────
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

// ── CONTENT CHUNKS (topic intro screen) ──────────────────────────
app.get('/api/tutor/content-chunks', async (req, res) => {
  try {
    const { subject, topic } = req.query;
    if (!subject) return res.json({ chunks: [] });

    const cols = 'concept_title,concept_explanation,worked_example,common_mistakes,keywords,difficulty_level';

    // 1. ILIKE subject + ILIKE topic
    if (topic) {
      const { data: exact } = await supabase
        .from('concept_chunks').select(cols)
        .ilike('subject', '%' + subject + '%').ilike('topic', '%' + topic + '%')
        .order('difficulty_level', { ascending: true }).limit(6);
      if (exact && exact.length > 0) return res.json({ chunks: exact });

      // 2. Keyword fallback — longest word in topic name (>3 chars)
      const keyword = topic.split(/\s+/).filter(w => w.length > 3).sort((a, b) => b.length - a.length)[0];
      if (keyword) {
        const { data: kw } = await supabase
          .from('concept_chunks').select(cols)
          .ilike('subject', '%' + subject + '%').ilike('topic', '%' + keyword + '%')
          .order('difficulty_level', { ascending: true }).limit(6);
        if (kw && kw.length > 0) return res.json({ chunks: kw });
      }
    }

    // 3. No topic match — return empty so UI shows "coming soon" gracefully
    return res.json({ chunks: [] });
  } catch (err) {
    return res.json({ chunks: [] });
  }
});

// ── TOPIC ILLUSTRATIONS ───────────────────────────────────────────
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

    // 2. ILIKE fallback — handles subject variations (e.g. "Add Maths" vs "Mathematics")
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

// ── ADMIN BACKUP ENDPOINT ─────────────────────────────────────────
app.get('/api/admin/backup', (req, res) => {
  const secret = req.headers['admin_secret_key'] || req.headers['admin-secret-key'];
  if (!secret || secret !== process.env.ADMIN_SECRET_KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  triggerBackup();
  res.json({ status: 'backup started' });
});

app.listen(PORT, () => {
  console.log(`\nLearnova v2.2 running on port ${PORT}`);
  console.log(`FAQ loaded: ${Object.keys(FAQ_DATA).length} Maths questions`);
  console.log(`Multi-subject FAQ: faq_cache table (8 subjects)`);
  console.log(`PregenLookup: question_bank + faq_bank + concept_explanations (ID + MY)`);
  console.log(`Claude API: ${claudeApiKey ? 'ready' : 'FAQ-only mode'}\n`);
});
// ── MARKING ENGINE ────────────────────────────────────────────────
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















