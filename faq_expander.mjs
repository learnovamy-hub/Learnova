import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = 'https://nxvbpanozswheackgwni.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54dmJwYW5venN3aGVhY2tnd25pIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQxNTA3NCwiZXhwIjoyMDkwOTkxMDc0fQ.0MvWb7_gBfDQQOlcpmX4brBRk6YbOOVOInyvpJL1a7A';
const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

const delay = ms => new Promise(r => setTimeout(r, ms));

// ── EXPANDED Q&A BANK ────────────────────────────────────────────
const QA_BANK = [

  // ═══ ADD MATHS ═══════════════════════════════════════════════
  { subject: 'Add Maths', topic: 'Functions', q: 'what is a one to one function', a: 'A one-to-one (injective) function means every output has exactly one input — no two inputs give the same output. Use the horizontal line test: if any horizontal line crosses the graph more than once, it is NOT one-to-one.' },
  { subject: 'Add Maths', topic: 'Functions', q: 'what is an onto function', a: 'An onto (surjective) function means every element in the range (codomain) is mapped to by at least one element in the domain. All possible outputs are covered.' },
  { subject: 'Add Maths', topic: 'Functions', q: 'how to determine if inverse function exists', a: 'An inverse function exists only if the original function is one-to-one (bijective). Check using the horizontal line test — every horizontal line must cut the graph at most once.' },
  { subject: 'Add Maths', topic: 'Quadratic Functions', q: 'how to find range of quadratic function', a: 'For f(x) = a(x-h)² + k: if a > 0, range is y ≥ k (minimum k). If a < 0, range is y ≤ k (maximum k). The vertex (h, k) is the turning point.' },
  { subject: 'Add Maths', topic: 'Quadratic Functions', q: 'what is the nature of roots', a: 'Discriminant b²-4ac determines roots: b²-4ac > 0 = two distinct real roots; b²-4ac = 0 = two equal (repeated) real roots; b²-4ac < 0 = no real roots (complex roots).' },
  { subject: 'Add Maths', topic: 'Quadratic Functions', q: 'how to form quadratic equation from roots', a: 'If roots are α and β: x² - (α+β)x + αβ = 0. Sum of roots = -b/a, product of roots = c/a. Substitute known sum and product to form the equation.' },
  { subject: 'Add Maths', topic: 'Simultaneous Equations', q: 'how to solve simultaneous equations one linear one quadratic', a: 'Step 1: Express one variable from the linear equation. Step 2: Substitute into the quadratic equation. Step 3: Solve the resulting quadratic. Step 4: Find the other variable for each solution.' },
  { subject: 'Add Maths', topic: 'Indices Surds Logarithms', q: 'what is change of base formula', a: 'log_a(b) = log(b)/log(a) = ln(b)/ln(a). Change base to 10 or e when calculator needed. Example: log_2(8) = log(8)/log(2) = 3.' },
  { subject: 'Add Maths', topic: 'Indices Surds Logarithms', q: 'how to solve log equations', a: 'Step 1: Use log laws to simplify. Step 2: If log_a(x) = k, then x = a^k. Step 3: Check solutions — log of negative number or zero is undefined.' },
  { subject: 'Add Maths', topic: 'Indices Surds Logarithms', q: 'what is natural logarithm', a: 'Natural log ln(x) = log_e(x) where e ≈ 2.718. Key rules: ln(e) = 1, ln(1) = 0, ln(e^x) = x, e^(ln x) = x. Used in calculus and growth models.' },
  { subject: 'Add Maths', topic: 'Coordinate Geometry', q: 'what is equation of locus', a: 'A locus is the path traced by a moving point satisfying a condition. To find: let point be P(x,y), write the condition as an equation, simplify to get the locus equation.' },
  { subject: 'Add Maths', topic: 'Coordinate Geometry', q: 'how to find area of triangle with coordinates', a: 'Area = ½|x₁(y₂-y₃) + x₂(y₃-y₁) + x₃(y₁-y₂)|. Use the shoelace formula. Always take absolute value — area is never negative.' },
  { subject: 'Add Maths', topic: 'Coordinate Geometry', q: 'what is point of division', a: 'Point dividing line AB in ratio m:n internally: P = ((mx₂+nx₁)/(m+n), (my₂+ny₁)/(m+n)). For midpoint, m=n=1 gives ((x₁+x₂)/2, (y₁+y₂)/2).' },
  { subject: 'Add Maths', topic: 'Differentiation', q: 'what is product rule', a: 'If y = uv, then dy/dx = u(dv/dx) + v(du/dx). Remember: "first times derivative of second, plus second times derivative of first." Example: y = x²sin(x) → dy/dx = x²cos(x) + 2x·sin(x).' },
  { subject: 'Add Maths', topic: 'Differentiation', q: 'what is quotient rule', a: 'If y = u/v, then dy/dx = (v·du/dx - u·dv/dx)/v². Remember: "bottom times derivative of top minus top times derivative of bottom, all over bottom squared."' },
  { subject: 'Add Maths', topic: 'Differentiation', q: 'what is the second derivative test', a: 'At turning point where f\'(x) = 0: if f\'\'(x) > 0 → minimum point; if f\'\'(x) < 0 → maximum point; if f\'\'(x) = 0 → test inconclusive, use first derivative test.' },
  { subject: 'Add Maths', topic: 'Differentiation', q: 'how to find rate of change', a: 'Rate of change = dy/dx. For related rates: use chain rule. dy/dt = (dy/dx) × (dx/dt). Example: if area A = πr², dA/dt = 2πr × (dr/dt).' },
  { subject: 'Add Maths', topic: 'Integration', q: 'what is definite integral', a: 'Definite integral ∫[a to b] f(x)dx = F(b) - F(a) where F is the antiderivative. It represents the signed area between the curve and x-axis from x=a to x=b.' },
  { subject: 'Add Maths', topic: 'Integration', q: 'how to find area between two curves', a: 'Area = ∫[a to b] |f(x) - g(x)| dx. Find intersection points first (set f(x) = g(x)). If f(x) ≥ g(x) throughout, area = ∫[a to b] [f(x) - g(x)] dx.' },
  { subject: 'Add Maths', topic: 'Integration', q: 'how to find volume of revolution', a: 'Rotating about x-axis: V = π∫[a to b] y² dx. Rotating about y-axis: V = π∫[c to d] x² dy. Always multiply by π and square the function.' },
  { subject: 'Add Maths', topic: 'Trigonometric Functions', q: 'what are double angle formulas', a: 'sin(2A) = 2sin(A)cos(A). cos(2A) = cos²A - sin²A = 1 - 2sin²A = 2cos²A - 1. tan(2A) = 2tan(A)/(1-tan²A). Memorise all three forms of cos(2A).' },
  { subject: 'Add Maths', topic: 'Trigonometric Functions', q: 'what are compound angle formulas', a: 'sin(A±B) = sinA·cosB ± cosA·sinB. cos(A±B) = cosA·cosB ∓ sinA·sinB. tan(A±B) = (tanA ± tanB)/(1 ∓ tanA·tanB).' },
  { subject: 'Add Maths', topic: 'Vectors', q: 'what is scalar product dot product', a: 'a·b = |a||b|cos θ = a₁b₁ + a₂b₂. If a·b = 0, vectors are perpendicular. The dot product gives a scalar (number), not a vector.' },
  { subject: 'Add Maths', topic: 'Vectors', q: 'how to find unit vector', a: 'Unit vector â = a/|a|. Magnitude |a| = √(x² + y²). A unit vector has magnitude 1 and points in the same direction as the original vector.' },
  { subject: 'Add Maths', topic: 'Linear Programming', q: 'how to identify feasible region', a: 'Plot all constraint inequalities. The feasible region is where ALL constraints are satisfied simultaneously. Test a point (usually origin) to determine which side of each line to shade.' },
  { subject: 'Add Maths', topic: 'Probability Distributions', q: 'what is binomial distribution', a: 'X ~ B(n,p): n = number of trials, p = probability of success. P(X=r) = nCr × p^r × (1-p)^(n-r). Mean = np, Variance = np(1-p). Each trial independent, only 2 outcomes.' },
  { subject: 'Add Maths', topic: 'Probability Distributions', q: 'what is normal distribution', a: 'X ~ N(μ, σ²): bell-shaped, symmetric about mean μ. To find probabilities, standardise: Z = (X-μ)/σ, then use Z-tables. 68% within 1σ, 95% within 2σ, 99.7% within 3σ.' },
  { subject: 'Add Maths', topic: 'Kinematics Linear Motion', q: 'what is displacement velocity acceleration relationship', a: 'v = ds/dt (velocity = rate of change of displacement). a = dv/dt = d²s/dt² (acceleration = rate of change of velocity). To find displacement from velocity: s = ∫v dt.' },
  { subject: 'Add Maths', topic: 'Linear Law', q: 'what is linear law', a: 'Linear law converts non-linear equations to Y = mX + c form. Identify Y, X, m, c. Example: y = ax^n → log y = log a + n log x, so Y = log y, X = log x, m = n, c = log a.' },

  // ═══ PHYSICS ═════════════════════════════════════════════════
  { subject: 'Physics', topic: 'Forces Motion', q: 'what is the difference between scalar and vector', a: 'Scalar: magnitude only (speed, mass, temperature, energy). Vector: magnitude AND direction (velocity, force, displacement, acceleration). Vectors are represented with arrows.' },
  { subject: 'Physics', topic: 'Forces Motion', q: 'what is uniform acceleration', a: 'Constant acceleration. Use SUVAT equations: v = u + at, s = ut + ½at², v² = u² + 2as, s = ½(u+v)t. Where s=displacement, u=initial velocity, v=final velocity, a=acceleration, t=time.' },
  { subject: 'Physics', topic: 'Forces Motion', q: 'what is free fall', a: 'Motion under gravity only, no air resistance. Acceleration = g = 9.8 m/s² downward. All objects fall at same rate regardless of mass (Galileo). Use SUVAT with a = g.' },
  { subject: 'Physics', topic: 'Forces Motion', q: 'what is friction', a: 'Force opposing motion between surfaces. Static friction (before motion) > kinetic friction (during motion). f = μN where μ = coefficient of friction, N = normal force.' },
  { subject: 'Physics', topic: 'Forces Motion', q: 'what is work done', a: 'W = Fs cos θ. Work = force × displacement × cos(angle between them). Unit: Joule (J). Work done is zero if force perpendicular to displacement (e.g. gravity on horizontal motion).' },
  { subject: 'Physics', topic: 'Forces Motion', q: 'what is power', a: 'P = W/t = Fv. Power = work done per unit time = force × velocity. Unit: Watt (W) = J/s. Efficiency = useful output power/input power × 100%.' },
  { subject: 'Physics', topic: 'Forces Motion', q: 'what is kinetic energy and potential energy', a: 'KE = ½mv² (energy of motion). GPE = mgh (energy due to height). Conservation of energy: KE + PE = constant (no friction). Loss in PE = gain in KE when falling.' },
  { subject: 'Physics', topic: 'Waves', q: 'what is superposition of waves', a: 'When two waves meet, resultant displacement = sum of individual displacements. Constructive interference: waves in phase, amplitude increases. Destructive interference: waves out of phase, amplitude decreases.' },
  { subject: 'Physics', topic: 'Waves', q: 'what is diffraction', a: 'Bending of waves around obstacles or through gaps. Most noticeable when gap size ≈ wavelength. Longer wavelengths diffract more. Sound diffracts around corners; light needs very narrow slits.' },
  { subject: 'Physics', topic: 'Waves', q: 'what is the electromagnetic spectrum', a: 'In order of increasing frequency/decreasing wavelength: Radio → Microwave → Infrared → Visible → UV → X-ray → Gamma. All travel at speed of light (3×10⁸ m/s) in vacuum.' },
  { subject: 'Physics', topic: 'Electricity', q: 'what is electric potential difference', a: 'Voltage (V) = work done per unit charge = W/Q. It is the "push" that drives current. Unit: Volt. EMF is the voltage of the source; terminal voltage is less due to internal resistance.' },
  { subject: 'Physics', topic: 'Electricity', q: 'what is electric power', a: 'P = IV = I²R = V²/R. Power = current × voltage. Unit: Watt. Energy = Pt. Electricity bill calculated from kWh = (power in kW) × (time in hours).' },
  { subject: 'Physics', topic: 'Electricity', q: 'what is internal resistance', a: 'Resistance inside a battery/source. EMF (ε) = V + Ir, where V = terminal voltage, I = current, r = internal resistance. Terminal voltage drops under load.' },
  { subject: 'Physics', topic: 'Electromagnetism', q: 'what is electromagnetic induction', a: 'When magnetic flux through a conductor changes, an EMF is induced. Faraday\'s law: EMF = -dΦ/dt. Lenz\'s law: induced current opposes the change causing it.' },
  { subject: 'Physics', topic: 'Electromagnetism', q: 'what is a transformer', a: 'Transforms AC voltage: Vs/Vp = Ns/Np = Ip/Is. Step-up: more secondary turns → higher voltage. Step-down: fewer secondary turns → lower voltage. Ideal transformer: VpIp = VsIs (100% efficient).' },
  { subject: 'Physics', topic: 'Heat', q: 'what is latent heat', a: 'Energy absorbed or released during change of state at constant temperature. L = Q/m. Latent heat of fusion (solid↔liquid). Latent heat of vaporisation (liquid↔gas). No temperature change during phase transition.' },
  { subject: 'Physics', topic: 'Heat', q: 'what is the gas laws', a: 'Boyle\'s law: PV = constant (constant T). Charles\'s law: V/T = constant (constant P). Pressure law: P/T = constant (constant V). Combined: PV/T = constant. Ideal gas: PV = nRT.' },
  { subject: 'Physics', topic: 'Light', q: 'what is the lens formula', a: '1/f = 1/u + 1/v. f = focal length, u = object distance, v = image distance. Magnification m = v/u = image height/object height. Converging lens: f positive. Diverging lens: f negative.' },
  { subject: 'Physics', topic: 'Nuclear Physics', q: 'what is nuclear fission and fusion', a: 'Fission: heavy nucleus splits into smaller nuclei, releasing energy (nuclear power plants, atom bomb). Fusion: light nuclei combine to form heavier nucleus, releasing more energy (sun, hydrogen bomb). Both convert mass to energy: E = mc².' },
  { subject: 'Physics', topic: 'Electronics', q: 'what is a transistor', a: 'A semiconductor device that amplifies or switches signals. Base-Emitter junction: small base current controls large collector-emitter current. Used in amplifiers (active region) and switches (saturation/cutoff).' },

  // ═══ BIOLOGY ═════════════════════════════════════════════════
  { subject: 'Biology', topic: 'Cell Biology', q: 'what is active transport', a: 'Movement of molecules against concentration gradient (low to high) using energy (ATP) and carrier proteins. Examples: sodium-potassium pump, glucose absorption in intestine. Unlike diffusion — requires energy.' },
  { subject: 'Biology', topic: 'Cell Biology', q: 'what is the difference between plant and animal cells', a: 'Plant cells only: cell wall (cellulose), chloroplasts, large central vacuole. Animal cells only: centrioles, smaller vacuoles. Both have: nucleus, mitochondria, ribosomes, cell membrane, cytoplasm, ER, Golgi.' },
  { subject: 'Biology', topic: 'Cell Biology', q: 'what is the role of mitochondria', a: 'Mitochondria are the "powerhouse of the cell" — site of aerobic respiration. Inner membrane (cristae) is where ATP is produced. Cells with high energy needs (muscle, liver) have more mitochondria.' },
  { subject: 'Biology', topic: 'Cell Division', q: 'what are the stages of mitosis', a: 'PMAT: Prophase (chromosomes condense, spindle forms), Metaphase (chromosomes align at equator), Anaphase (chromatids pulled to poles), Telophase (nuclear envelope reforms). Then cytokinesis splits cytoplasm.' },
  { subject: 'Biology', topic: 'Cell Division', q: 'why is meiosis important', a: 'Meiosis produces gametes (sperm/eggs) with half the chromosome number (haploid). Ensures correct chromosome number after fertilisation. Also creates genetic variation through crossing over and random assortment.' },
  { subject: 'Biology', topic: 'Nutrition', q: 'what are the functions of nutrients', a: 'Carbohydrates: energy. Proteins: growth and repair. Fats: energy storage, insulation, hormones. Vitamins: metabolic reactions (Vit C = immune system, Vit D = calcium absorption). Minerals: Ca (bones), Fe (haemoglobin). Water: transport medium.' },
  { subject: 'Biology', topic: 'Nutrition', q: 'how does digestion work', a: 'Mechanical digestion: physical breakdown (chewing, churning). Chemical digestion: enzyme breakdown. Mouth: amylase (starch→maltose). Stomach: pepsin (protein→peptides). Small intestine: lipase, protease, amylase. Absorption in small intestine (villi).' },
  { subject: 'Biology', topic: 'Respiration', q: 'what are the stages of aerobic respiration', a: 'Glycolysis (cytoplasm): glucose → 2 pyruvate + 2 ATP. Krebs cycle (mitochondrial matrix): pyruvate → CO₂ + NADH. Oxidative phosphorylation (cristae): NADH → 34 ATP. Total: 38 ATP from one glucose.' },
  { subject: 'Biology', topic: 'Dynamic Ecosystem', q: 'what is a food chain and food web', a: 'Food chain: linear sequence showing energy flow (producer → consumer → decomposer). Food web: interconnected food chains. Energy lost at each trophic level (~90%). Only ~10% transferred to next level.' },
  { subject: 'Biology', topic: 'Dynamic Ecosystem', q: 'what is the nitrogen cycle', a: 'Nitrogen fixation (bacteria convert N₂ to NH₃). Nitrification (NH₃ → NO₂ → NO₃). Assimilation (plants absorb NO₃). Ammonification (decomposers return N to soil). Denitrification (NO₃ → N₂ back to atmosphere).' },
  { subject: 'Biology', topic: 'Coordination Control', q: 'what is a reflex arc', a: 'Stimulus → Receptor → Sensory neuron → Relay neuron (spinal cord) → Motor neuron → Effector → Response. Bypasses brain for speed. Examples: knee jerk, withdrawing hand from pain.' },
  { subject: 'Biology', topic: 'Coordination Control', q: 'what is the role of hormones', a: 'Chemical messengers secreted by endocrine glands into blood. Slower but longer lasting than nerves. Insulin (pancreas): lowers blood glucose. Adrenaline (adrenal): fight-or-flight. Oestrogen (ovary): female development.' },
  { subject: 'Biology', topic: 'Heredity', q: 'what is incomplete dominance', a: 'Neither allele is fully dominant — heterozygote shows intermediate phenotype. Example: red (RR) × white (WW) → pink (RW). Different from codominance where BOTH traits show fully.' },
  { subject: 'Biology', topic: 'Heredity', q: 'what is sex-linked inheritance', a: 'Genes on sex chromosomes (usually X). X-linked recessive: more common in males (XY) as they only need one copy. Example: colour blindness, haemophilia. Carrier females (XX^c) pass to sons.' },
  { subject: 'Biology', topic: 'Variation', q: 'what is the difference between continuous and discontinuous variation', a: 'Continuous: range of values, influenced by environment and many genes (height, mass). Discontinuous: distinct categories, mainly genetic (blood group, tongue rolling). Continuous shows normal distribution curve.' },
  { subject: 'Biology', topic: 'Biotechnology', q: 'what is genetic engineering', a: 'Manipulating DNA to change an organism\'s characteristics. Steps: identify gene → cut with restriction enzymes → insert into vector (plasmid) → insert into host organism. Example: insulin gene in bacteria.' },

  // ═══ GEOGRAPHY ═══════════════════════════════════════════════
  { subject: 'Geography', topic: 'Geomorphology', q: 'what causes weathering', a: 'Physical weathering: freeze-thaw, thermal expansion (no chemical change). Chemical weathering: carbonation (acid rain + limestone), oxidation (iron rusting), hydrolysis (water reacts with minerals). Biological: roots breaking rock.' },
  { subject: 'Geography', topic: 'Geomorphology', q: 'what are river features', a: 'Upper course: V-shaped valley, waterfalls, rapids (high energy, vertical erosion). Middle course: meanders, floodplains (lateral erosion). Lower course: ox-bow lakes, deltas, estuaries (deposition dominant).' },
  { subject: 'Geography', topic: 'Hydrology', q: 'what factors affect river discharge', a: 'Precipitation intensity and duration. Rock permeability (impermeable rock = more runoff). Soil saturation. Vegetation (intercepts rain, roots absorb water). Slope steepness. Land use (urban = faster runoff).' },
  { subject: 'Geography', topic: 'Climate', q: 'what causes monsoon', a: 'Seasonal reversal of winds due to differential heating of land and sea. Southwest monsoon (June-Sept): sea warmer than land in winter, now land heats faster in summer → low pressure over land draws in moist sea air → heavy rain.' },
  { subject: 'Geography', topic: 'Climate', q: 'what is global warming and its effects', a: 'Rise in Earth\'s temperature due to enhanced greenhouse effect (CO₂, CH₄ from human activities). Effects: melting ice caps, sea level rise, extreme weather, coral bleaching, drought in some areas, flooding in others.' },
  { subject: 'Geography', topic: 'Population', q: 'what is demographic transition model', a: 'Stage 1: High birth rate, high death rate (pre-industrial). Stage 2: Death rate falls (medicine improves), birth rate stays high → population explosion. Stage 3: Birth rate falls. Stage 4: Both low, stable population.' },
  { subject: 'Geography', topic: 'Agriculture', q: 'what are the types of agriculture in malaysia', a: 'Plantation agriculture: large-scale, single crop (rubber, palm oil, for export). Subsistence farming: small-scale, padi (rice), vegetables for family use. Commercial farming: market gardens, poultry, modern technology.' },
  { subject: 'Geography', topic: 'Industry', q: 'what are the factors of industrial location', a: 'Raw materials (near source = lower transport cost). Labour supply and skills. Transport infrastructure. Market proximity. Government policy (industrial zones, incentives). Energy supply. Land cost and availability.' },
  { subject: 'Geography', topic: 'Development', q: 'what is the human development index', a: 'HDI measures development using three dimensions: health (life expectancy), education (years of schooling), and living standard (GNI per capita). Scale 0-1. Very high (>0.8), High, Medium, Low development.' },

  // ═══ SEJARAH ═════════════════════════════════════════════════
  { subject: 'Sejarah', topic: 'Tamadun Islam', q: 'apakah ciri-ciri tamadun Islam', a: 'Tamadun Islam bercirikan: akidah (kepercayaan kepada Allah), syariat (undang-undang Islam), akhlak (moral), ilmu pengetahuan, keadilan sosial, dan kesejahteraan ummah. Bersifat universal dan syumul (menyeluruh).' },
  { subject: 'Sejarah', topic: 'Nasionalisme Malaysia', q: 'apakah itu perjuangan kemerdekaan', a: 'Perjuangan mendapatkan kemerdekaan daripada penjajah British. Tokoh penting: Dato Onn Jaafar (UMNO), Tunku Abdul Rahman (Bapa Malaysia). Kemerdekaan dicapai 31 Ogos 1957 melalui diplomasi, bukan perang.' },
  { subject: 'Sejarah', topic: 'Pembinaan Negara Bangsa', q: 'apakah Dasar Ekonomi Baru DEB', a: 'DEB (1971-1990) bertujuan: (1) membasmi kemiskinan tanpa mengira kaum, (2) menyusun semula masyarakat untuk menghapus pengenalan kaum mengikut fungsi ekonomi. Sasaran bumiputera 30% ekuiti korporat.' },
  { subject: 'Sejarah', topic: 'Pembinaan Negara Bangsa', q: 'apakah peranan Perlembagaan Malaysia', a: 'Perlembagaan Malaysia adalah undang-undang tertinggi negara. Mengandungi: hak asasi warganegara, pembahagian kuasa (Parlimen, Eksekutif, Kehakiman), kedudukan Islam sebagai agama rasmi, hak istimewa bumiputera, bahasa Melayu sebagai bahasa kebangsaan.' },
  { subject: 'Sejarah', topic: 'Malaysia dalam Kerjasama Antarabangsa', q: 'apakah ASEAN dan kepentingannya', a: 'ASEAN (1967) ditubuhkan di Bangkok oleh 5 negara pengasas (Malaysia, Thailand, Filipina, Indonesia, Singapura). Tujuan: kerjasama ekonomi, sosial, budaya, keamanan serantau. Kini 10 ahli termasuk Brunei, Vietnam, Laos, Myanmar, Kemboja.' },

  // ═══ BAHASA MALAYSIA ══════════════════════════════════════════
  { subject: 'Bahasa Malaysia', topic: 'Tatabahasa', q: 'apakah imbuhan akhiran kata nama', a: 'Akhiran kata nama: -an (makanan, minuman), -wan (hartawan, seniman), -man (budiman), -wati (seniwati), -isme (nasionalisme). Akhiran -an paling produktif — boleh ditambah pada banyak kata.' },
  { subject: 'Bahasa Malaysia', topic: 'Tatabahasa', q: 'apakah ayat aktif dan ayat pasif', a: 'Ayat aktif: subjek melakukan perbuatan (Ali menulis surat). Ayat pasif: objek menjadi subjek (Surat ditulis oleh Ali). Penanda pasif: me- → di- (menulis → ditulis). Kata ganti nama diri: ditulis olehnya → ditulisnya.' },
  { subject: 'Bahasa Malaysia', topic: 'Frasa dan Klausa', q: 'apakah perbezaan frasa dan klausa', a: 'Frasa: kumpulan kata tanpa subjek dan predikat lengkap (buku merah, berlari pantas). Klausa: kumpulan kata ada subjek dan predikat (dia berlari, buku itu merah). Ayat mengandungi sekurang-kurangnya satu klausa.' },
  { subject: 'Bahasa Malaysia', topic: 'Karangan', q: 'bagaimana menulis karangan yang baik', a: 'Pendahuluan: ayat topik yang menarik, perkenalkan tema. Isi: 3-4 perenggan, setiap perenggan satu isi utama + huraian + contoh. Penutup: rumusan, pandangan peribadi, cadangan. Gunakan kata hubung dan bahasa yang tepat.' },
  { subject: 'Bahasa Malaysia', topic: 'Rumusan', q: 'bagaimana cara menulis rumusan', a: 'Baca petikan, kenal pasti isi penting (bukan contoh). Tulis 3-4 isi utama dalam ayat sendiri (parafrase). Panjang: 80 patah perkataan untuk SPM. Jangan salin terus dari petikan. Mulakan dengan "Petikan ini membincangkan..."' },
  { subject: 'Bahasa Malaysia', topic: 'Komsas', q: 'apakah unsur-unsur dalam karya sastera', a: 'Tema (persoalan utama), Persoalan (isu-isu yang dibincangkan), Watak dan Perwatakan, Plot (jalan cerita), Latar (tempat/masa/masyarakat), Sudut pandangan (orang pertama/ketiga), Nilai murni, Pengajaran.' },

  // ═══ ENGLISH ═════════════════════════════════════════════════
  { subject: 'English', topic: 'Grammar', q: 'what are the types of nouns', a: 'Common nouns (dog, city), Proper nouns (Ali, Kuala Lumpur — capitalised), Abstract nouns (love, freedom), Collective nouns (team, flock), Countable nouns (book/books), Uncountable nouns (water, information — no plural).' },
  { subject: 'English', topic: 'Grammar', q: 'what is subject verb agreement', a: 'Singular subject → singular verb. Plural subject → plural verb. Tricks: "The team IS..." (collective noun = singular). "Each/every + singular noun" → singular verb. "Neither/either" → singular verb.' },
  { subject: 'English', topic: 'Grammar', q: 'what are relative clauses', a: 'Defining: "The book that I read was great" (essential info, no commas). Non-defining: "My brother, who lives in KL, is a doctor" (extra info, use commas). Who = people, which = things, that = people or things (defining only).' },
  { subject: 'English', topic: 'Tenses', q: 'when to use past perfect tense', a: 'Past perfect (had + past participle) for actions completed BEFORE another past action. "She had already eaten when I arrived." The earlier action uses past perfect; the later uses simple past.' },
  { subject: 'English', topic: 'Essay Writing', q: 'how to write a formal letter', a: 'Sender address (top right) → Date → Recipient address (left) → Salutation (Dear Sir/Madam) → Subject heading → Body (3 paragraphs: purpose, details, closing request) → Yours faithfully → Signature.' },
  { subject: 'English', topic: 'Essay Writing', q: 'what are discourse markers', a: 'Words/phrases linking ideas: Addition (furthermore, moreover, in addition). Contrast (however, nevertheless, on the other hand). Cause/effect (therefore, consequently, as a result). Sequence (firstly, subsequently, finally).' },
  { subject: 'English', topic: 'Literature', q: 'how to analyse a poem', a: 'SLAB: Subject (what is it about), Language (imagery, metaphor, simile, personification), Attitude/tone (how does the poet feel), Bigger picture (theme, message). Always quote from the poem to support your analysis.' },
  { subject: 'English', topic: 'Vocabulary', q: 'what are collocations', a: 'Words that naturally go together. Examples: make a decision (NOT do a decision), heavy rain (NOT strong rain), commit a crime, take a photo. Learn collocations together as chunks to sound natural in English.' },
  { subject: 'English', topic: 'Reading Comprehension', q: 'how to answer comprehension questions', a: 'Skim text first for overview. For each question: find the relevant section, answer in complete sentences (unless told otherwise), use own words unless asked to quote. Inference questions: use evidence from text, not personal opinion.' },

  // ═══ MATHEMATICS ══════════════════════════════════════════════
  { subject: 'Mathematics', topic: 'Number Bases', q: 'how to convert binary to decimal', a: 'Multiply each digit by its place value (powers of 2) and add. Example: 1011₂ = 1×8 + 0×4 + 1×2 + 1×1 = 8+0+2+1 = 11₁₀. Place values: ...8,4,2,1 from right.' },
  { subject: 'Mathematics', topic: 'Number Bases', q: 'how to convert decimal to binary', a: 'Repeatedly divide by 2, record remainders, read remainders from BOTTOM to TOP. Example: 13 ÷ 2 = 6 r1, 6÷2=3 r0, 3÷2=1 r1, 1÷2=0 r1. Answer: 1101₂.' },
  { subject: 'Mathematics', topic: 'Solid Geometry', q: 'what are the formulas for volume and surface area', a: 'Cylinder: V=πr²h, SA=2πr²+2πrh. Cone: V=⅓πr²h, SA=πr²+πrl (l=slant height). Sphere: V=4/3πr³, SA=4πr². Pyramid: V=⅓×base area×height.' },
  { subject: 'Mathematics', topic: 'Plans Elevations', q: 'what are plans and elevations', a: 'Plan: view from ABOVE (top view). Front elevation: view from FRONT. Side elevation: view from SIDE. These are 2D drawings showing a 3D object from different directions. Dotted lines show hidden edges.' },
  { subject: 'Mathematics', topic: 'Earth as a Sphere', q: 'what is latitude and longitude', a: 'Latitude: angular distance north or south of equator (0°-90°N or S). Longitude: angular distance east or west of prime meridian (0°-180°E or W). A location is written as (latitude, longitude). Equator = 0° latitude. Greenwich = 0° longitude.' },
  { subject: 'Mathematics', topic: 'Graphs of Functions', q: 'what are the shapes of common graphs', a: 'y=x: straight line through origin. y=x²: U-shaped parabola. y=x³: S-shaped cubic. y=1/x: hyperbola (two curves in opposite quadrants). y=√x: half parabola. Know the shape, intercepts, and key features of each.' },
];

async function upsertFAQ(item) {
  try {
    const { error } = await supabase
      .from('faq_cache')
      .upsert({
        subject: item.subject,
        topic: item.topic,
        question: item.q.toLowerCase().trim(),
        answer: item.a,
        form_level: '4,5',
        source: 'curated_v2',
      }, { onConflict: 'subject,question' });
    return !error;
  } catch {
    return false;
  }
}

async function main() {
  console.log('╔══════════════════════════════════════════════╗');
  console.log('║   LEARNOVA FAQ EXPANDER v2 — 500+ Questions  ║');
  console.log('╚══════════════════════════════════════════════╝\n');

  // Count existing
  const { count: before } = await supabase.from('faq_cache').select('*', { count: 'exact', head: true });
  console.log(`📊 Current FAQ count: ${before}\n`);

  let saved = 0, failed = 0;
  const subjects = {};

  for (const item of QA_BANK) {
    const ok = await upsertFAQ(item);
    if (ok) {
      saved++;
      subjects[item.subject] = (subjects[item.subject] || 0) + 1;
    } else {
      failed++;
    }
    await delay(40);
  }

  const { count: after } = await supabase.from('faq_cache').select('*', { count: 'exact', head: true });

  console.log('╔══════════════════════════════════════════════╗');
  console.log('║              EXPANSION COMPLETE              ║');
  console.log('╠══════════════════════════════════════════════╣');
  console.log(`║  Before: ${String(before).padEnd(35)}║`);
  console.log(`║  Added:  ${String(saved).padEnd(35)}║`);
  console.log(`║  Total:  ${String(after).padEnd(35)}║`);
  console.log('╠══════════════════════════════════════════════╣');
  console.log('║  By subject:                                 ║');
  for (const [subj, count] of Object.entries(subjects)) {
    console.log(`║  ✅ ${(subj + ': ' + count).padEnd(40)}║`);
  }
  console.log('╚══════════════════════════════════════════════╝');
}

main().catch(console.error);
