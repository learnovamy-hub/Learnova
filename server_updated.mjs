import express from 'express';
import { createClient } from '@supabase/supabase-js';
import jwt from 'jsonwebtoken';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const app = express();
const PORT = process.env.PORT || 3000;

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_KEY;
const claudeApiKey = process.env.CLAUDE_API_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error('FATAL: Missing SUPABASE_URL or SUPABASE_KEY');
  process.exit(1);
}

console.log('Supabase connected:', supabaseUrl);
const supabase = createClient(supabaseUrl, supabaseKey);
const JWT_SECRET = process.env.JWT_SECRET || 'learnova-dev-secret-2025';

process.on('uncaughtException', (err) => { console.error('UNCAUGHT:', err); process.exit(1); });
process.on('unhandledRejection', (err) => { console.error('REJECTION:', err); process.exit(1); });

const __dirname = dirname(fileURLToPath(import.meta.url));
app.use(express.json());
app.use('/portals', express.static(join(__dirname, 'portals')));
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
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

app.get('/', (req, res) => res.send('Learnova API v2.1'));
app.get('/health', (req, res) => res.json({ status: 'ok', version: '2.1', timestamp: new Date() }));

// â”€â”€ FAQ DATA (Maths hardcoded, zero cost AI) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const FAQ_DATA = {
  "what is a function": { answer: "A function is a relation where every input (x-value) has exactly ONE output (y-value). If one input gives two different outputs, it's NOT a function.", topic: "Functions", example: "f(x) = 2x + 1. When x = 3, f(3) = 7. Only one answer!" },
  "what is domain and range": { answer: "Domain = all possible INPUT values (x-values). Range = all possible OUTPUT values (y-values). For f(x) = sqrt(x), domain is x >= 0, range is y >= 0.", topic: "Functions", example: "f(x) = 1/x â€” Domain: all x except 0. Range: all y except 0." },
  "how to find inverse function": { answer: "Step 1: Replace f(x) with y. Step 2: Swap x and y. Step 3: Solve for y. Step 4: Replace y with f-inverse(x). The inverse undoes what the function does.", topic: "Functions", example: "f(x) = 2x + 3 â†’ swap â†’ x = 2y + 3 â†’ f-inv(x) = (x-3)/2" },
  "what is composite function": { answer: "fg(x) means apply g first, then f. Written as f(g(x)). Work from RIGHT to LEFT.", topic: "Functions", example: "f(x)=xÂ², g(x)=x+1. fg(x) = f(x+1) = (x+1)Â²" },
  "how to find fg x": { answer: "fg(x) = f(g(x)). Apply g first, substitute result into f.", topic: "Functions", example: "f(x)=3x, g(x)=x-2. fg(x) = f(x-2) = 3(x-2) = 3x-6" },
  "what is absolute value": { answer: "|x| always gives a positive value or zero. |x| = x if x >= 0, |x| = -x if x < 0. Distance from zero on number line.", topic: "Functions", example: "|5|=5, |-3|=3, |0|=0" },
  "how to graph a function": { answer: "1) Make a table of x and y values. 2) Plot points. 3) Connect smoothly. Find x-intercepts (y=0), y-intercept (x=0).", topic: "Functions", example: "f(x)=xÂ²: x=-2â†’4, x=-1â†’1, x=0â†’0, x=1â†’1, x=2â†’4. U-shape parabola!" },
  "what is quadratic equation": { answer: "axÂ² + bx + c = 0 where a â‰  0. Highest power is 2. Has at most 2 solutions.", topic: "Quadratic Equations", example: "xÂ² - 5x + 6 = 0 has solutions x=2 and x=3" },
  "how to use quadratic formula": { answer: "x = (-b Â± sqrt(bÂ²-4ac)) / 2a. Identify a, b, c from axÂ² + bx + c = 0 and substitute.", topic: "Quadratic Equations", example: "xÂ²-5x+6=0: a=1,b=-5,c=6. x=(5Â±1)/2. So x=3 or x=2" },
  "what is discriminant": { answer: "bÂ²-4ac tells you about roots: >0 means two real roots, =0 means one repeated root, <0 means no real roots.", topic: "Quadratic Equations", example: "xÂ²-4x+4=0: disc=16-16=0. One root: x=2" },
  "how to factorise quadratic": { answer: "Find two numbers that MULTIPLY to c and ADD to b in xÂ²+bx+c. Write as (x+p)(x+q).", topic: "Quadratic Equations", example: "xÂ²+5x+6: need Ã—=6, +=5. That's 2 and 3. Answer: (x+2)(x+3)" },
  "how to complete the square": { answer: "xÂ²+bx+c: add (b/2)Â² to both sides to get (x+b/2)Â²=something. Then solve.", topic: "Quadratic Equations", example: "xÂ²+6x+5=0 â†’ (x+3)Â²=4 â†’ x=-1 or x=-5" },
  "what is vertex of parabola": { answer: "Turning point of parabola. For axÂ²+bx+c, x-coord of vertex = -b/2a. If a>0, it's minimum. If a<0, it's maximum.", topic: "Quadratic Equations", example: "f(x)=xÂ²-4x+3: vertex x=2, y=-1. Vertex: (2,-1)" },
  "sum and product of roots": { answer: "For axÂ²+bx+c=0 with roots Î± and Î²: Î±+Î² = -b/a, Î±Î² = c/a.", topic: "Quadratic Equations", example: "xÂ²-5x+6=0: sum=5, product=6. Roots 2,3 check: 2+3=5âœ“, 2Ã—3=6âœ“" },
  "what are laws of indices": { answer: "aáµÃ—aâ¿=aáµâºâ¿, aáµÃ·aâ¿=aáµâ»â¿, (aáµ)â¿=aáµâ¿, aâ°=1, aâ»â¿=1/aâ¿, a^(1/n)=nth root of a, a^(m/n)=nth root of aáµ", topic: "Indices and Surds", example: "2Â³Ã—2â´=2â·=128. 5â°=1. 2â»Â³=1/8" },
  "what is a surd": { answer: "An irrational square root that cannot simplify to a whole number. sqrt(2), sqrt(3), sqrt(5) are surds. sqrt(4)=2 is NOT a surd.", topic: "Indices and Surds", example: "sqrt(12)=2sqrt(3) (surd). sqrt(9)=3 (not a surd)" },
  "how to simplify surds": { answer: "Find the largest perfect square factor: sqrt(n) = sqrt(aÂ²Ã—m) = aÃ—sqrt(m). Look for 4, 9, 16, 25, 36...", topic: "Indices and Surds", example: "sqrt(48)=4sqrt(3), sqrt(75)=5sqrt(3), sqrt(200)=10sqrt(2)" },
  "how to rationalise denominator": { answer: "Remove surds from denominator. For 1/sqrt(a): multiply by sqrt(a)/sqrt(a). For 1/(a+sqrt(b)): multiply by conjugate (a-sqrt(b))/(a-sqrt(b)).", topic: "Indices and Surds", example: "3/sqrt(2) = 3sqrt(2)/2. 1/(1+sqrt(3)) = (sqrt(3)-1)/2" },
  "how to add surds": { answer: "Only add LIKE surds (same number under root). Simplify first, then combine.", topic: "Indices and Surds", example: "2sqrt(3)+5sqrt(3)=7sqrt(3). sqrt(12)+sqrt(3)=2sqrt(3)+sqrt(3)=3sqrt(3)" },
  "what is negative index": { answer: "aâ»â¿ = 1/aâ¿. Flip it! Never makes the number negative. 2â»Â³ = 1/8 (still positive).", topic: "Indices and Surds", example: "3â»Â²=1/9. (1/2)â»Â³=8. xâ»Â¹=1/x" },
  "what is fractional index": { answer: "a^(m/n) = nth_root(aáµ). Denominator=ROOT, numerator=POWER.", topic: "Indices and Surds", example: "8^(2/3)=(cube_root 8)Â²=2Â²=4. 27^(1/3)=3. 16^(3/4)=2Â³=8" },
  "what is linear inequality": { answer: "Like a linear equation but with <, >, â‰¤, â‰¥ instead of =. Solution is a RANGE of values.", topic: "Linear Inequalities", example: "2x+3>7 â†’ 2x>4 â†’ x>2" },
  "how to solve linear inequality": { answer: "Solve like equation EXCEPT: multiplying or dividing by NEGATIVE number FLIPS the inequality sign!", topic: "Linear Inequalities", example: "-2x>6 â†’ x<-3 (flipped!). But 2x>6 â†’ x>3 (no flip)" },
  "how to show inequality on number line": { answer: "Open circle = strict inequality (< or >) endpoint NOT included. Closed circle = â‰¤ or â‰¥ endpoint IS included.", topic: "Linear Inequalities", example: "x>3: open circle at 3, arrow right. xâ‰¤-1: closed circle at -1, arrow left." },
  "what is combined inequality": { answer: "Has TWO conditions like a<x<b. Solve each part separately, find where BOTH satisfied.", topic: "Linear Inequalities", example: "-2<2x+4â‰¤10 â†’ -3<xâ‰¤3" },
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
  "how to solve exponential equation": { answer: "If bases can be matched: equal bases means equal powers. If not, take log of both sides.", topic: "Logarithms", example: "2^x=8 â†’ 2^x=2Â³ â†’ x=3. 3^x=10 â†’ xlog3=log10 â†’ x=1/log3â‰ˆ2.096" },
  "what is a polynomial": { answer: "Expression with non-negative integer powers: anxâ¿+...+a1x+a0. Degree=highest power. Polynomial division uses long division or synthetic.", topic: "Polynomials", example: "3xÂ³-2xÂ²+5x-1 is degree 3 polynomial" },
  "remainder theorem": { answer: "When polynomial f(x) divided by (x-a), remainder = f(a). No need to do full division!", topic: "Polynomials", example: "f(x)=xÂ³-2x+1 divided by (x-2): remainder=f(2)=8-4+1=5" },
  "factor theorem": { answer: "If f(a)=0, then (x-a) is a factor of f(x). Use to find factors without full division.", topic: "Polynomials", example: "f(x)=xÂ³-6xÂ²+11x-6. f(1)=0, so (x-1) is a factor" },
  "what is partial fractions": { answer: "Breaking a complex fraction into simpler parts. For (px+q)/((ax+b)(cx+d)) = A/(ax+b) + B/(cx+d). Find A,B by substituting.", topic: "Partial Fractions", example: "5/(xÂ²-1) = A/(x-1) + B/(x+1). Solve: A=5/2, B=-5/2" },
  "what is binomial expansion": { answer: "(a+b)â¿ = sum of nCr Ã— aâ¿â»Ê³ Ã— bÊ³ for r=0 to n. Coefficients from Pascal's Triangle or nCr.", topic: "Binomial Expansion", example: "(1+x)Â³ = 1+3x+3xÂ²+xÂ³. Coefficients: 1,3,3,1 from Pascal's row 3" },
  "what is differentiation": { answer: "Finding the rate of change (gradient) of a function. d/dx(xâ¿)=nxâ¿â»Â¹. Differentiation = finding f'(x) = slope at any point.", topic: "Differentiation", example: "f(x)=xÂ³: f'(x)=3xÂ². At x=2: gradient=12" },
  "what is integration": { answer: "Reverse of differentiation. âˆ«xâ¿ dx = xâ¿âºÂ¹/(n+1) + C. Definite integral gives area under curve between two x values.", topic: "Integration", example: "âˆ«xÂ² dx = xÂ³/3 + C. âˆ«â‚€Â² xÂ² dx = [xÂ³/3]â‚€Â² = 8/3" },
  "how to find stationary points": { answer: "Set f'(x)=0 and solve for x. Then find y-value. Use f''(x) to determine: f''(x)>0 means minimum, f''(x)<0 means maximum.", topic: "Differentiation", example: "f(x)=xÂ²-4x: f'(x)=2x-4=0 â†’ x=2. f''(2)=2>0 so minimum at (2,-4)" }
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

// â”€â”€ AI ASK ENDPOINT (updated: FAQ â†’ faq_cache â†’ Claude) â”€â”€â”€â”€â”€â”€â”€â”€â”€
app.post('/api/ai/ask', async (req, res) => {
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
    res.json({ student: { id: student.id, name: student.name, email: student.email }, stats: { totalQuizzes, avgScore, totalStudyTime } });
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
    const { subject, form_level } = req.query;
    let query = supabase.from('lessons').select('id,title,topic,subject,form_level,teacher_id,created_at').eq('is_published', true);
    if (subject) query = query.eq('subject', subject);
    if (form_level) query = query.eq('form_level', form_level);
    const { data, error } = await query.order('created_at', { ascending: false });
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

// â”€â”€ QUIZ ROUTES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

app.get('/api/ai/analytics', async (req, res) => { try { const { data, error } = await supabase.from('ai_conversations').select('question,subject,topic,source,cost,created_at').order('created_at', { ascending: false }).limit(1000); if (error) throw error; const qC = {}; const sC = {}; let cost = 0; (data||[]).forEach(r => { qC[r.question]=(qC[r.question]||0)+1; sC[r.subject]=(sC[r.subject]||0)+1; cost+=parseFloat(r.cost||0); }); res.json({ total: data?.length||0, total_cost: cost.toFixed(4), top_questions: Object.entries(qC).sort((a,b)=>b[1]-a[1]).slice(0,10).map(([q,c])=>({question:q,count:c})), top_subjects: Object.entries(sC).sort((a,b)=>b[1]-a[1]).map(([s,c])=>({subject:s,count:c})) }); } catch (err) { res.status(500).json({ error: err.message }); } });


app.listen(PORT, () => {
  console.log(`\nLearnova v2.1 running on port ${PORT}`);
  console.log(`FAQ loaded: ${Object.keys(FAQ_DATA).length} Maths questions`);
  console.log(`Multi-subject FAQ: faq_cache table (8 subjects)`);
  console.log(`Claude API: ${claudeApiKey ? 'ready' : 'FAQ-only mode'}\n`);
});
