# LEARNOVA — Claude Code Master Reference
Last updated: 2026-06-09

## Project Overview
Learnova is an AI-powered tutoring platform for Malaysian SPM, A-Level, and Indonesian SNBT students.
Live URL: https://learnova.optimus.com.my
Backend: https://learnova-backend-production-bd3a.up.railway.app

## Tech Stack
- Frontend: Flutter Web (C:\learnova_app)
- Backend: Node.js server_updated.mjs (Railway)
- Database: Supabase (nxvbpanozswheackgwni)
- AI: Claude API (tutoring) + DeepSeek (processing)
- TTS: OpenAI TTS (nova voice)
- Hosting: GitHub Pages (learnova.optimus.com.my via CNAME)

## Critical Files
- C:\learnova_app\lib\screens\ai_tutor_tab.dart
- C:\learnova_app\lib\screens\home_tab.dart
- C:\learnova_app\lib\screens\subject_screen.dart
- C:\learnova_app\lib\screens\main_shell.dart
- C:\learnova_app\lib\screens\welcome_home.dart
- C:\learnova_app\lib\config\constants.dart (kSubjects)
- C:\Learnova\server_updated.mjs (Railway backend)

## Database Structure
- concept_chunks: all textbook content
  Prefixes: MY- (SPM), AL- (A-Level), ID- (Indonesian)
- lessons: structured lesson records
- topics: topic list per subject

## Subject Naming Convention (CRITICAL)
Always use prefixed names in Supabase:
SPM: MY-Physics, MY-Chemistry, MY-Biology,
     MY-Mathematics, MY-AddMaths,
     MY-BahasaMalaysia, MY-English, MY-Sejarah
A-Level: AL-Physics, AL-Chemistry, AL-Biology,
         AL-Mathematics, AL-FurtherMaths
Indonesian: ID-Fisika, ID-Kimia, ID-Biologi,
            ID-Matematika, ID-BahasaIndonesia

Flutter sends unprefixed names.
Server normalizeSubject() converts them.
NEVER remove normalizeSubject().

## TTS Configuration (NEVER CHANGE)
Model: tts-1-hd
Voice: nova
Speed: 1.0
Format: mp3
Always strip markdown before sending to TTS.

## Nova Pedagogy Rules (NEVER CHANGE)
1. Never give direct answers immediately
2. Always end response with open question
3. Question must require typing — never yes/no
4. No suggested answer chips mid-session
5. BM for MY- subjects, English for AL-,
   Bahasa Indonesia for ID-
6. MY- tone: casual BM like senior student
7. AL- tone: professional Cambridge tutor
8. ID- tone: friendly Indonesian kakak/mas

## BM Language Rules (NEVER CHANGE)
Technical terms OK: formula, graf, atom, pH
Forbidden (use BM instead):
exposed→terdedah, involve→melibatkan,
experience→pengalaman, calculation→pengiraan,
understand→faham, because→kerana,
example→contoh, student→pelajar
"kau" is FORBIDDEN in ALL BM content — always use "kamu".
Softer and more respectful. Applies to Nova responses, lessons,
onboarding UI, and all server system prompts. Word boundary rule:
regex \bkau\b to avoid breaking "akaun" (account).

## Navigation Structure (current)
4 tabs in main_shell.dart:
- 0: Home (HomeTab)
- 1: Learn (SubjectScreen)
- 2: Nova (AITutorTab)
- 3: Profil (ProfileTab)
Quizzes tab removed from nav — QuizzesTab file still exists but not in nav.

## Deployment Process
Flutter: Run .\deploy.ps1 from C:\learnova_app
  1. flutter build web --release
  2. Zip build\web contents → deploy_fresh.zip
  3. Upload zip to cPanel via FTP (curl.exe — NOT curl, which is aliased to Invoke-WebRequest)
  4. Extract via cPanel UAPI (https://learnova.optimus.com.my:2083/execute/Fileman/extract_file)
  5. Delete zip from server
  FTP host: learnova.optimus.com.my | user: optimus | remote: /home/optimus/public_html/Learnova/
  Manual backup: zip build\web, upload via cPanel File Manager at :2083
Backend: cd C:\Learnova && railway up --detach
NEVER manually edit files on the server.
NEVER deploy without building first.

## Cache Busting (IMPLEMENTED 2026-06-08)
- flutter_bootstrap.js and main.dart.js get a timestamp query param on each build
  so browsers always fetch fresh JS — no manual version bumping needed
- PWA strategy set to none: service worker does NOT cache files aggressively
- web/index.html already has Cache-Control: no-cache, no-store, must-revalidate meta tags
- Result: every deploy is immediately live for all users with no stale-cache issues

## Two Separate Backends — CRITICAL
Production Railway: C:\Learnova\server_updated.mjs
  - Deploy: cd C:\Learnova && railway up --detach
  - GitHub auto-deploy NOT reliable — always use railway CLI
Old/wrong backend: C:\Users\Yong\OneDrive\learnova\learnova-backend\
  - NOT on Railway. Changes here do NOT go live.

## Lessons Engine (IMPLEMENTED 2026-06-07)
- structured_lessons table: ACTIVE (24 lessons across 8 topics)
- student_lesson_progress table: ACTIVE
- topic_quizzes table: ACTIVE
- Nova context-aware: YES (lessonContext injected when opened from LessonScreen)
- Nova opening from lesson: auto-sends "Saya nak faham [title] dengan lebih baik" → Nova responds
- Nova opening from tab: shows "Hei! Kau nak belajar apa hari ni?..."
- Nova mandatory rules: short responses (3-4 sentences), redirect after 3-4 exchanges, lesson-stay enforced
- Nova 7 mandatory response rules: HARDCODED in server system prompt (ALL sessions)
- Lesson→Nova flow: Navigator.push(AITutorTab) — back button returns to LessonScreen
- Nova lesson banner: shown at top of chat (📚 [title] + ← Pelajaran button)
- Nova hint text: "Tanya pasal [lesson_title]..." when in lesson mode
- nova_source logging: 'nova_from_lesson' vs 'nova_direct' sent to API on every message
- Home screen: Continue Learning card shows next incomplete lesson + Nova banner below it
- Learn screen: Redesigned as lesson path (subject chips → topic list → lesson rows)
- New LessonScreen: Objective bar, Concept, Worked Example, Try It, Answer, Mistakes, Technique
- API endpoints: /api/lessons/path, /api/lessons/lesson, /api/lessons/complete, /api/lessons/progress, /api/lessons/next

## Deployment Note (IMPORTANT — 2026-06-09)
LiteSpeed static file memory cache on cPanel does NOT detect FTP STOR overwrites
after the first post-extraction overwrite. To force cache clear on every deploy:
1. FTP upload root_only.zip (created by deploy.ps1 zip step, root files only)
2. In cPanel File Manager → /public_html/Learnova/ → upload zip → Extract
3. This creates new inodes → LiteSpeed serves fresh content immediately
Assets folder (/assets/) is locked (owned by extraction user, not FTP user).
Assets haven't changed — only root JS files change per build.

## LiteSpeed Cache Bypass Attempts (NONE work via API/FTP — 2026-06-10)
- `CacheLookup off` and `StaticCache off` in .htaccess: does NOT clear memory cache
- FTP DELE then STOR: does NOT bust LiteSpeed cache (new inode not detected)
- cPanel JSON API rename then FTP STOR: does NOT bust cache
- `CacheMgr` UAPI module: not installed on this host
- `Fileman/extract_file` UAPI: function does not exist on this host
- PURGE HTTP method: 405 Method Not Allowed
- TTL unknown — possibly 24h. Only cPanel File Manager GUI extract reliably busts it.
  If cache blocking rollout: login to :2083, upload any zip to /public_html/Learnova/, Extract.

## Railway Crash Root Cause (2026-06-10)
Emoji corruption: emojis in server_updated.mjs strings (💪 = F0 9F 92 AA in UTF-8)
were double-encoded as cp1252 bytes. Byte 0x92 in cp1252 = U+2019 RIGHT SINGLE
QUOTATION MARK ('). This ' inside single-quoted JS strings terminates them early
→ SyntaxError. Affects: 💪 in .join() calls and similar single-quoted contexts.
FIX: Never use emoji in server_updated.mjs or any .mjs file. Use ASCII/text only.
→ is safe in template literals and double-quoted strings but NOT in single-quoted strings
  (→ = U+2192 = E2 86 92 in UTF-8; byte 92 → U+2019 in cp1252 = same problem)

## CORS (ADDED 2026-06-10)
cors package was in package.json but never imported or configured.
Login was broken for all users. Fixed: import cors added, app.use(cors({...})) added
immediately after const app = express(). Allowed origins: learnova.optimus.com.my
+ all localhost ports. app.options('*', cors()) for preflight.

## Emoji / Encoding Rules (PERMANENT)
- lesson_screen.dart file had UTF-8 multi-byte chars corrupted as individual Latin-1 chars
  (e.g. → stored as â†' = U+00E2 + U+2020 + U+2019). Fixed 2026-06-09.
- NEVER use emoji in Dart source files — always use Material Icons (Icons.*) instead.
- NEVER use curly/smart quotes (U+2018, U+2019) in Dart source — Dart only accepts U+0027.
- lesson_screen.dart tab icons now use Material Icons (menu_book, volume_up, auto_awesome).
- Hook sentence 💡 replaced with Icon(Icons.lightbulb_outline_rounded).
- Server stripEmojis() added in server_updated.mjs — applied to all lesson fields in
  /api/lessons/lesson endpoint so no emoji reaches Flutter Web.

## Current Known Bugs (update as fixed)
- [x] Subjects showing 0 lessons — fixed: switched to /api/tutor/topics
- [x] Topic passed as undefined to Nova — fixed: mobile topic selector now shows actual topics from API; tapping starts a guided session with a valid topic
- [x] Onboarding crash — form_level is INTEGER in Supabase but server wrote "Form 5" string.
      Fixed: added levelMap in completeOnboarding() in student_profile_engine.mjs
      ("Form 4"→4, "Form 5"→5, "A-Level"→6). Every new student was failing onboarding silently.
- [x] Route shadowing — GET /api/lessons/:id (line 550) intercepted ALL /api/lessons/path,
      /api/lessons/lesson, /api/lessons/progress, /api/lessons/next before they could fire.
      Fixed: renamed old route to /api/lessons/detail/:id.
- [x] student_lesson_progress FK — student_id FK pointed at auth.users(id) but students
      are in the custom students table (not Supabase Auth). Every insert failed silently.
      Fixed: DROP old FK, ADD FK referencing students(id) ON DELETE CASCADE.
- [x] parent/connect .catch() crash — Supabase v2 query builder does not support .catch()
      chaining. Fixed: wrapped upsert in try/catch block.
- [x] parent/dashboard .catch() crash — same .catch() issue on parent_child_links query.
      Fixed: destructure result then use || [] fallback.
- [x] subjects empty in parent dashboard — server used child.active_subjects (not in raw DB
      row) instead of child.selected_subjects (actual JSONB column). Fixed.
- [x] projected_coverage_pct wrong — denominator was progress.length (rows seen) so 1
      completed lesson = 100%. Fixed: use fixed denominator of 24 (total structured_lessons).
- [x] Raw JSON leaking — PERMANENT FIX: (1) learnova_core.mjs created with formatNovaResponse()
      — handles double-encoded JSON, extracts reply field, converts literal \n to newlines.
      (2) server_updated.mjs imports + uses formatNovaResponse() in both catch blocks.
      (3) Flutter _buildMessage() uses _parseNovaText() static helper (same logic client-side).
- [x] Mid-session illustration chips ("Angles of Elevation – Graph" etc) — REMOVED:
      _loadTopicIllustrations() call removed from _startTutorSession(); chips never auto-populate.
      Overlay still works if user explicitly triggers it via _showIllustrationItem().
- [x] "Listen" button renamed to "Baca Kuat" in tts_player.dart (label + semantics).
- [x] BM language rules expanded in server system prompt: added advantage, survive, scarce,
      distinction, angle (non-math), solid, reproduce, inherit, environment, adapt.
- [x] Lesson tab icons fixed: emoji (📖📊🎯) replaced with Material Icons (menu_book, volume_up, auto_awesome).
- [x] Hook sentence 💡 emoji replaced with Icon(Icons.lightbulb_outline_rounded) in lesson_screen.dart.
- [x] stripEmojis() added to server /api/lessons/lesson endpoint — all text fields stripped before send.
- [x] Null safety: hook_sentence cast changed from `as String` to `as String? ?? ''`.
- [x] Duplicate topic names in Biology (x2) and Sejarah (x1) fixed in Supabase.

## Parent Progress Engine (ENHANCED 2026-06-09)
- lesson_sessions table: ACTIVE (tracks open/close/complete with duration + topic)
- student_logins table: ACTIVE (tracks every login for streak calculation)
- nova_sessions table: NEW (tracks Nova chat sessions per student)
- quiz_attempts table: ACTIVE (subject + topic columns added)
- /api/lesson/start → returns sessionId, called when lesson opens
- /api/lesson/end → saves duration + completed + topic, called on dispose/complete
- /api/nova/session-end → records Nova session (messagesCount, durationMinutes, subject, topic)
- /api/activity/login → fired after every student login (fire-and-forget)
- /api/parent/link → no-auth: validate LRN-XXXXXX, return student UUID
- /api/parent/child-progress → no-auth: full dashboard data:
    child (name, level, joinedDays), today (mins, lessons, nova questions, streak),
    thisWeek (totalMinutes, dailyActivity[7], vsLastWeek trend),
    subjects (percentComplete, strongTopics, weakTopics, minutesThisWeek),
    spmReadiness (daysRemaining, overallPercent, predictedGrade, subjectReadiness),
    recentActivity (last 5 across lesson/nova/quiz),
    summary.bm (Claude-generated BM paragraph), summary.en
- SPM date hardcoded: 2026-11-14
- Claude Haiku used for BM summary generation in parent endpoint
- Parent screen: STATE A (link via LRN-ID), STATE B (full dashboard)
- Parent screen accessible at /parent URL (no auth required)
- Parent link button in ProfileTab: "Ibu Bapa? Pantau di sini →"
- Nova session tracking: _recordNovaSession() called in ai_tutor_tab dispose()
- Lesson session topic tracking: topic sent in /api/lesson/end call

## Session Continuity (IMPLEMENTED 2026-06-09)
- student_progress: tracks exactly where student stopped per lesson
    (last_section, scroll_position, total_minutes, is_completed)
    Sections: concept | try_it | completed
- subject_progress: per-subject summary (lessons_completed, total_minutes, last_topic)
- /api/progress/lesson-open → creates lesson_sessions row, upserts subject_progress,
    upserts student_logins daily row, returns sessionId
- /api/progress/lesson-update → upserts student_progress + updates lesson_sessions
    Called every 30 seconds by Timer.periodic in lesson_screen.dart
- /api/progress/lesson-complete → marks student_progress completed, closes session,
    increments subject_progress.lessons_completed
- /api/progress/resume → returns last incomplete lesson + streak + todayMinutes
    (for home screen "Continue Learning" card)
- calculateStreak() helper handles date deduplication for streak count
- lesson_screen.dart: _progressTimer (30s), _currentSection, _sessionStart, _saveProgress()
    Section changes tracked: concept (start) → try_it (on submit) → completed (on Selesai)
- Both /api/progress/lesson-complete AND /api/lessons/complete called on Selesai
    (progress continuity + student_lesson_progress for Learn screen)
- home_tab.dart: _loadResumeData() called after dashboard load + on refresh
    _resumeData, _streak, _todayMinutes state vars populated from /api/progress/resume
    _buildContinueCard() priority: resume card → next lesson card → start card
    Resume card: shows subject chip, topic, lesson title, "Berhenti di X" bookmark
    Stats line: uses real _todayMinutes + _streak (not stale weekly_stats from dashboard cache)
    Missions: mission1=always done, mission2=lastSection=='completed', mission3=locked until active

## Supabase Tables Added (2026-06-07, enhanced 2026-06-09)
- lesson_sessions: id UUID, student_id TEXT, lesson_id TEXT, subject TEXT, topic TEXT,
    started_at TIMESTAMPTZ, ended_at TIMESTAMPTZ, duration_seconds INT, completed BOOLEAN
- student_logins: id UUID, student_id TEXT, logged_at TIMESTAMPTZ
- nova_sessions: id UUID, student_id TEXT, subject TEXT, topic TEXT,
    messages_count INT, duration_minutes INT, started_at TIMESTAMPTZ
- quiz_attempts: id UUID, student_id UUID, lesson_id UUID, score INT, total INT,
    subject TEXT, topic TEXT, started_at TIMESTAMPTZ
- parent_child_links: upserted by /api/parent/connect (parent_id, student_id)

## Icon Library
CupertinoIcons: REMOVED permanently (2026-06-09).
All icons use Material Icons only (Icons.*).
cupertino_icons package removed from pubspec.yaml.
Never re-add CupertinoIcons.

## Completed This Project
- [x] 25,070 concept_chunks in Supabase
- [x] All subjects categorised with MY/AL/ID prefix
- [x] TTS working (tts-1-hd, nova, speed 1.0)
- [x] 4-tab nav: Home / Learn / Nova / Profil
- [x] Suggested answer chips removed mid-session
- [x] normalizeSubject() in server
- [x] Flat subject list (no big cards)
- [x] No floating ? button
- [x] Landing page redesign (voice orb flow)
- [x] Nova pedagogy question ending
- [x] Input placeholder updated (BM/EN aware)
- [x] All 8 SPM subjects showing
- [x] Lessons Engine: structured_lessons + student_lesson_progress + topic_quizzes
- [x] Learn screen redesigned as lesson path (topic expand → lesson rows with progress)
- [x] LessonScreen: full lesson flow (concept → try it → answer → mistakes → technique)
- [x] Nova context-aware when opened from LessonScreen
- [x] Home Continue Learning card shows next incomplete lesson
- [x] Nova lesson banner (📚 title + ← Pelajaran back button)
- [x] Nova auto-sends first message ("Saya nak faham [title]...") via real API call
- [x] Lesson→Nova→Lesson flow: Navigator.push so ← back returns to lesson
- [x] Home screen Nova banner ("Sambung belajar? Tanya Nova →")
- [x] Onboarding redesign: minimalist dark (#07080C), one question per screen, fade transitions,
      auto-advance on level tap, flat subject rows, no progress dots/icons (2026-06-09)
- [x] Smart greeting: Muslim/Malay/Arab names → "Assalamualaikum", others → time-based (2026-06-09)
      muslimNameIndicators in learnova_core.mjs + home_tab.dart + onboarding_screen.dart Screen 3
- [x] Lesson screen 3-mode tabs: Baca / Dengar (TTS audio player) / Nova (2026-06-09)
      Dengar: auto-loads TTS on tab tap, pulsing Nova avatar, progress slider, restart/+30s
      Baca: "Tak faham? Tanya Nova" button at bottom of content
      Nova tab: navigates directly to AITutorTab with lesson context
- [x] nova_source logging (nova_from_lesson vs nova_direct)
- [x] Nova hint text context-aware ("Tanya pasal [lesson]...")
- [x] Lesson session tracking: _startLesson() on open, _endLesson() on dispose/complete
- [x] Login activity tracking: POST /api/activity/login on every student login
- [x] Student ID inline in ProfileTab: LRN-XXXXXX large monospace + copy + link to StudentIdScreen
- [x] Parent Progress Engine: fully connected, 9-section dashboard, lesson + login data
- [x] Parent linking: /api/parent/connect wired to ParentConnectScreen
- [x] New Supabase tables: lesson_sessions, student_logins

## Smart Greeting Rules (NEVER CHANGE)
Greeting logic: check if first name part matches MUSLIM_NAME_INDICATORS list.
If match → "Assalamualaikum". Otherwise → time-based "Selamat pagi/petang/malam".
Implemented in:
- home_tab.dart: _HomeTabState.getSmartGreeting(name) → _greeting getter
- onboarding_screen.dart: _getSmartGreeting(name) → Screen 3 heading
- learnova_core.mjs: getSmartGreeting(name) export + MUSLIM_NAME_INDICATORS array
- student_profile_engine.mjs: generateGreeting() uses getSmartGreeting()
All 4 places MUST stay in sync. Never revert to plain time-based greeting.

## Free Subjects (HARDCODED — NEVER CHANGE)
- MY-BahasaMalaysia: FREE FOREVER for all students
- MY-English: FREE FOREVER for all students
All other subjects require selection during onboarding or later purchase.
Source: C:\Learnova\subject_access_engine.mjs FREE_SUBJECTS array.

## Core Engines (server-side)
- C:\Learnova\subject_access_engine.mjs — subject access + display name mappings
- C:\Learnova\student_profile_engine.mjs — profile CRUD, LRN-ID generation, greeting
Both imported and initialised in server_updated.mjs at startup.

## Student ID Format
Display ID: LRN-XXXXXX (6 alphanumeric chars)
Stored in: students.learnova_id column (Supabase)
Returned from: /api/student/onboard and /api/student/profile

## Onboarding Rules (NEVER CHANGE)
- Show ONLY on first login (when onboarding_completed = false)
- NEVER ask again after completion
- BM + English always pre-selected and locked in step 2
- Student sees ONLY their selected subjects in Learn tab
- After onboarding: cache active_subjects in SharedPreferences

## Onboarding Flow
1. Screen 1 — Level: Form 4, Form 5, A-Level
2. Screen 2 — Subjects: BM+English locked, others checkboxes
3. Screen 3 — Welcome with LRN-XXXXXX Student ID
POST /api/student/onboard → saves level + subjects + assigns LRN-ID
File: C:\learnova_app\lib\screens\onboarding_screen.dart

## Learn Screen Architecture (IMPLEMENTED 2026-06-08)
Navigation flow: Learn tab → Subject cards → Topic list → Lesson list → Lesson screen
- subject_screen.dart: redesigned as subject card grid (icon, name, description)
  Tap card → TopicListScreen(subjectKey, subjectName, subjectColor)
- topic_list_screen.dart: NEW — shows all topics for selected subject
  Each topic card: topic name, lesson count badge, progress bar, completed/in-progress dot
  Tap → LessonListScreen(topic, lessons, subject, progress)
- lesson_list_screen.dart: NEW — shows all lessons for selected topic
  Lesson rows: number, title, duration, difficulty chip, status icon
  Mastery Quiz row: locked until all lessons completed
  Tap lesson → LessonScreen(lessonId, subject)
- lesson_screen.dart: updated — shows hook_sentence at top before Konsep section
  hook_sentence: teacher-talking style relatable opening (💡 card with italic text)
- hook_sentence column added to structured_lessons table (Supabase)
  Populated for all 8 topics: Elektrik, Elektrokimia, Indices and Logarithms,
  Integration, Nuklear Fizik, Quadratic Functions, Respirasi Sel, Sel
- Nova is NOT the destination for Learn tab — accessible only from:
  1. "Tanya Nova" button inside LessonScreen
  2. Nova tab in bottom nav (free chat mode)
  3. Home screen "Sambung belajar?" banner

## Lesson Content Style Rules
- hook_sentence: start with relatable real-life scenario, use "kau" not "pelajar/anda"
- Never start lesson with formula/definition — always WHY it matters first
- Server returns hook_sentence via select('*') on structured_lessons
- FIX 4 (generate more lessons from concept_chunks) — COMPLETE (2026-06-09)
  bulk_convert_lessons.py ran twice; 5,412 lessons across 356 topics, 8 subjects
  All MY- subjects populated. Counts: Chemistry 1209, Sejarah 1110, Biology 972,
  English 726, Mathematics 429, Physics 414, AddMaths 384, BahasaMalaysia 168

## Health Monitoring (ACTIVE — 2026-06-10)
- /health endpoint: comprehensive — checks Supabase, env vars, lesson count, CORS
  Returns {"status":"OK","checks":{"supabase":"OK","lesson_count":5412,...}}
  Returns 500 + "DEGRADED" if any check fails
- Pre-deploy checklist: C:\learnova_app\check_before_deploy.ps1
  Runs automatically at start of every deploy.ps1 (Step 0)
  9 checks: CupertinoIcons, BM kau, JSON leak, CORS, .htaccess, build age,
            Railway health, live site, emoji in server_updated.mjs
  FAILS deploy if CupertinoIcons / CORS / .htaccess / build / Railway are missing
  WARNS (non-blocking) for kau / JSON in Text() / build age
- Emoji check: scans server_updated.mjs only (subject_access_engine.mjs has
  intentional emoji for subject icons — those bytes are safe, no 0x92 byte)

## Rules For This Project
1. Always read CLAUDE.md before starting work
2. Never change TTS config
3. Never remove normalizeSubject()
4. Never add suggested answer chips mid-session
5. Always use prefixed subject names in Supabase
6. Always build and deploy after changes
7. Update CLAUDE.md when bugs are fixed or features completed
8. Keep changes small — one fix at a time
9. Always test after each change
10. Never leave background jobs running
11. CNAME file must always be in gh-pages root (learnova.optimus.com.my)
