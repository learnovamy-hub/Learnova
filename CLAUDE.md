# LEARNOVA — Claude Code Master Reference
Last updated: 2026-06-06

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

## Navigation Structure (current)
4 tabs in main_shell.dart:
- 0: Home (HomeTab)
- 1: Learn (SubjectScreen)
- 2: Nova (AITutorTab)
- 3: Profil (ProfileTab)
Quizzes tab removed from nav — QuizzesTab file still exists but not in nav.

## Deployment Process
Flutter: Run .\deploy.ps1 from C:\learnova_app
  - Builds with flutter build web --release
  - Pushes to gh-pages branch → GitHub Pages auto-serves at learnova.optimus.com.my
  - CNAME file must always be present in gh-pages root
Backend: cd C:\Learnova && railway up --detach
NEVER manually edit files on the server.
NEVER deploy without building first.

## Two Separate Backends — CRITICAL
Production Railway: C:\Learnova\server_updated.mjs
  - Deploy: cd C:\Learnova && railway up --detach
  - GitHub auto-deploy NOT reliable — always use railway CLI
Old/wrong backend: C:\Users\Yong\OneDrive\learnova\learnova-backend\
  - NOT on Railway. Changes here do NOT go live.

## Current Known Bugs (update as fixed)
- [ ] Subjects showing 0 lessons
- [ ] Topic passed as undefined to Nova
- [ ] Raw JSON leaking sometimes

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
