"""
Learnova Audio Pre-generation Pipeline
Generates MP3 audio for all lessons and stores on cPanel.
Flutter Dengar mode checks audio_url first (free), falls back to OpenAI TTS.

Usage:
  python generate_audio.py              # Process 50 lessons
  python generate_audio.py --limit 5   # Test with 5 lessons
  python generate_audio.py --limit 0   # Process all

Requires env vars:
  SUPABASE_URL          (e.g. https://nxvbpanozswheackgwni.supabase.co)
  SUPABASE_SERVICE_KEY  (service role key for write access)
  OPENAI_API_KEY        (for BM lessons — OpenAI nova voice)
  LEARNOVA_FTP_USER     (cPanel FTP username)
  LEARNOVA_FTP_PASS     (cPanel FTP password)
"""

import os
import re
import time
import json
import ftplib
import argparse
import tempfile
import subprocess
from pathlib import Path

import requests
import numpy as np

# ── Config ────────────────────────────────────────────────────────────────────

SUPABASE_URL = os.environ.get('SUPABASE_URL', 'https://nxvbpanozswheackgwni.supabase.co')
SUPABASE_KEY = os.environ.get('SUPABASE_SERVICE_KEY') or os.environ.get('SUPABASE_SERVICE_ROLE_KEY')
OPENAI_KEY   = os.environ.get('OPENAI_API_KEY')
FTP_HOST     = 'learnova.optimus.com.my'
FTP_USER     = os.environ.get('LEARNOVA_FTP_USER', 'optimus')
FTP_PASS     = os.environ.get('LEARNOVA_FTP_PASS')
FTP_DIR      = '/public_html/Learnova/audio'
PUBLIC_BASE  = 'https://learnova.optimus.com.my/audio'
OUTPUT_DIR   = Path('C:/learnova_audio')
MODEL_DIR    = Path('C:/learnova_audio/models')
OUTPUT_DIR.mkdir(exist_ok=True)

SUPABASE_HEADERS = {
    'apikey': SUPABASE_KEY or '',
    'Authorization': f'Bearer {SUPABASE_KEY or ""}',
    'Content-Type': 'application/json',
}

# Voice routing: AL- (English) → Kokoro free; MY- (BM) → OpenAI TTS
# ZH- (Mandarin) → future; ID- (Indonesian) → OpenAI TTS
KOKORO_SUBJECTS = ('AL-',)   # Use Kokoro for these
OPENAI_SUBJECTS = ('MY-', 'ID-')   # Use OpenAI TTS for these


# ── Kokoro setup (lazy init) ──────────────────────────────────────────────────

_kokoro = None

def get_kokoro():
    global _kokoro
    if _kokoro is None:
        model = MODEL_DIR / 'kokoro-v1.0.onnx'
        voices = MODEL_DIR / 'voices-v1.0.bin'
        if not model.exists() or not voices.exists():
            raise RuntimeError(
                f'Kokoro model files missing in {MODEL_DIR}\n'
                'Download:\n'
                '  curl -L https://github.com/thewh1teagle/kokoro-onnx/releases/'
                'download/model-files-v1.0/kokoro-v1.0.onnx -o C:/learnova_audio/models/kokoro-v1.0.onnx\n'
                '  curl -L https://github.com/thewh1teagle/kokoro-onnx/releases/'
                'download/model-files-v1.0/voices-v1.0.bin -o C:/learnova_audio/models/voices-v1.0.bin'
            )
        from kokoro_onnx import Kokoro
        _kokoro = Kokoro(str(model), str(voices))
    return _kokoro


# ── Supabase queries ──────────────────────────────────────────────────────────

def get_lessons_needing_audio(limit=50, subject_filter=None):
    params = {
        'select': 'id,subject,topic,lesson_title,hook_sentence,concept_explanation,'
                  'worked_example,try_it_question,exam_technique',
        'audio_url': 'is.null',
        'is_published': 'eq.true',
        'order': 'subject,topic,lesson_number',
        'limit': str(limit) if limit > 0 else '9999',
    }
    if subject_filter:
        params['subject'] = f'ilike.{subject_filter}%'
    r = requests.get(f'{SUPABASE_URL}/rest/v1/structured_lessons',
                     headers=SUPABASE_HEADERS, params=params)
    r.raise_for_status()
    return r.json()


def update_audio_url(lesson_id, audio_url):
    r = requests.patch(
        f'{SUPABASE_URL}/rest/v1/structured_lessons?id=eq.{lesson_id}',
        headers=SUPABASE_HEADERS,
        json={
            'audio_url': audio_url,
            'audio_generated_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        }
    )
    return r.status_code == 204


# ── Text cleaning ─────────────────────────────────────────────────────────────

def build_lesson_text(lesson, is_bm=True):
    parts = []
    def add(v):
        if v and str(v).strip():
            parts.append(str(v).strip())

    add(lesson.get('hook_sentence'))
    add(lesson.get('concept_explanation'))
    if lesson.get('worked_example'):
        prefix = 'Contoh: ' if is_bm else 'Example: '
        add(prefix + lesson['worked_example'])
    if lesson.get('exam_technique'):
        prefix = 'Teknik peperiksaan: ' if is_bm else 'Exam technique: '
        add(prefix + lesson['exam_technique'])

    text = ' '.join(parts)
    # Strip markdown
    text = re.sub(r'\*\*(.*?)\*\*', r'\1', text)
    text = re.sub(r'\*(.*?)\*', r'\1', text)
    text = re.sub(r'#{1,6}\s', '', text)
    text = re.sub(r'`(.*?)`', r'\1', text)

    if is_bm:
        text = (text.replace('÷', ' bahagi ')
                    .replace('×', ' darab ')
                    .replace('²', ' kuasa dua ')
                    .replace('°', ' darjah ')
                    .replace('√', ' punca kuasa dua '))
    else:
        text = (text.replace('÷', ' divided by ')
                    .replace('×', ' times ')
                    .replace('²', ' squared ')
                    .replace('°', ' degrees ')
                    .replace('√', ' square root of '))

    text = re.sub(r'\s+', ' ', text).strip()
    return text[:4000]


# ── Audio generation ──────────────────────────────────────────────────────────

def generate_kokoro_mp3(text, output_path, voice='af_sarah', speed=1.0):
    """Generate MP3 via Kokoro (free, local). For AL- English lessons."""
    import soundfile as sf
    kokoro = get_kokoro()
    try:
        samples, rate = kokoro.create(text, voice=voice, speed=speed, lang='en-us')
        # Write WAV then convert to MP3 via ffmpeg
        wav_path = str(output_path).replace('.mp3', '.wav')
        sf.write(wav_path, samples, rate)
        result = subprocess.run(
            ['ffmpeg', '-y', '-i', wav_path, '-codec:a', 'libmp3lame',
             '-q:a', '4', '-ar', '22050', str(output_path)],
            capture_output=True, text=True
        )
        Path(wav_path).unlink(missing_ok=True)
        return result.returncode == 0 and output_path.exists()
    except Exception as e:
        print(f'  Kokoro error: {e}')
        return False


def generate_openai_mp3(text, output_path):
    """Generate MP3 via OpenAI TTS (best BM voice). For MY-/ID- lessons."""
    if not OPENAI_KEY:
        print('  OPENAI_API_KEY not set — skipping BM lesson')
        return False
    try:
        r = requests.post(
            'https://api.openai.com/v1/audio/speech',
            headers={'Authorization': f'Bearer {OPENAI_KEY}',
                     'Content-Type': 'application/json'},
            json={'model': 'tts-1', 'voice': 'nova', 'input': text,
                  'response_format': 'mp3', 'speed': 1.0},
            timeout=60
        )
        if r.status_code == 200:
            output_path.write_bytes(r.content)
            return output_path.exists() and output_path.stat().st_size > 1000
        else:
            print(f'  OpenAI error {r.status_code}: {r.text[:100]}')
            return False
    except Exception as e:
        print(f'  OpenAI error: {e}')
        return False


# ── FTP upload ────────────────────────────────────────────────────────────────

_ftp_conn = None

def get_ftp():
    global _ftp_conn
    try:
        if _ftp_conn:
            _ftp_conn.voidcmd('NOOP')
            return _ftp_conn
    except Exception:
        _ftp_conn = None

    ftp = ftplib.FTP(FTP_HOST)
    ftp.login(FTP_USER, FTP_PASS or '')
    try:
        ftp.mkd(FTP_DIR)
    except ftplib.error_perm:
        pass
    ftp.cwd(FTP_DIR)
    _ftp_conn = ftp
    return ftp


def upload_mp3(local_path, remote_filename):
    try:
        ftp = get_ftp()
        with open(local_path, 'rb') as f:
            ftp.storbinary(f'STOR {remote_filename}', f)
        return True
    except Exception as e:
        global _ftp_conn
        _ftp_conn = None
        print(f'  FTP error: {e}')
        return False


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--limit', type=int, default=50,
                        help='Max lessons to process (0 = all)')
    parser.add_argument('--subject', default=None,
                        help='Filter by subject prefix e.g. AL-')
    args = parser.parse_args()

    if not SUPABASE_KEY:
        print('ERROR: Set SUPABASE_SERVICE_KEY env var')
        return 1
    if not FTP_PASS:
        print('ERROR: Set LEARNOVA_FTP_PASS env var')
        return 1

    print('Learnova Audio Generator')
    print('=' * 50)
    print(f'Models: {MODEL_DIR}')
    print(f'Output: {OUTPUT_DIR}')
    print(f'FTP: {FTP_HOST}{FTP_DIR}')

    lessons = get_lessons_needing_audio(limit=args.limit, subject_filter=args.subject)
    total = len(lessons)
    print(f'\nFound {total} lessons needing audio\n')

    if total == 0:
        print('All lessons already have audio!')
        return 0

    generated = failed = skipped = 0

    for i, lesson in enumerate(lessons, 1):
        lid     = lesson['id']
        subject = lesson.get('subject', '')
        title   = lesson.get('lesson_title', 'lesson')[:50]
        print(f'[{i}/{total}] {subject} — {title}')

        # Determine engine
        is_kokoro = subject.startswith(KOKORO_SUBJECTS)
        is_openai = subject.startswith(OPENAI_SUBJECTS)
        if not is_kokoro and not is_openai:
            print(f'  Skipped ({subject} not in routing table)')
            skipped += 1
            continue

        is_bm = subject.startswith('MY-') or subject.startswith('ID-')
        text = build_lesson_text(lesson, is_bm=is_bm)
        if not text:
            print('  No text content, skipping')
            skipped += 1
            continue
        print(f'  Text: {len(text)} chars')

        safe = re.sub(r'[^a-z0-9]', '_', title.lower())[:40]
        filename = f'{lid[:8]}_{safe}.mp3'
        local_path = OUTPUT_DIR / filename

        # Generate
        print(f'  Generating via {"Kokoro" if is_kokoro else "OpenAI"}...')
        if is_kokoro:
            ok = generate_kokoro_mp3(text, local_path)
        else:
            ok = generate_openai_mp3(text, local_path)

        if not ok:
            print('  FAILED generation')
            failed += 1
            continue

        size_kb = local_path.stat().st_size // 1024
        print(f'  Generated: {size_kb} KB')

        # Upload
        print('  Uploading to cPanel...')
        if not upload_mp3(local_path, filename):
            print('  FAILED upload')
            failed += 1
            continue

        # Save URL to Supabase
        audio_url = f'{PUBLIC_BASE}/{filename}'
        if update_audio_url(lid, audio_url):
            print(f'  Done: {audio_url}')
            generated += 1
        else:
            print('  Generated+uploaded but Supabase update failed')
            generated += 1

        # Small delay between API calls
        if is_openai:
            time.sleep(0.3)

    # Close FTP
    if _ftp_conn:
        try:
            _ftp_conn.quit()
        except Exception:
            pass

    print(f'\n{"=" * 50}')
    print(f'Complete: {generated} generated, {failed} failed, {skipped} skipped')
    return 0 if failed == 0 else 1


if __name__ == '__main__':
    exit(main())
