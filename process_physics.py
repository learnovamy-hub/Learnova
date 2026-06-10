"""
Learnova Physics Textbook Processor
Extracts text from PDF pages using PyMuPDF, structures with DeepSeek,
inserts into Supabase concept_chunks table.
"""

import fitz
import json
import requests
import os
import sys
import time
import re

# ── Config ──────────────────────────────────────────────────────────
DEEPSEEK_API_KEY = os.environ.get('DEEPSEEK_API_KEY', 'sk-116af79bcdc740dc914cf072fd735cb5')
SUPABASE_URL     = 'https://nxvbpanozswheackgwni.supabase.co'
SUPABASE_KEY     = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54dmJwYW5venN3aGVhY2tnd25pIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQxNTA3NCwiZXhwIjoyMDkwOTkxMDc0fQ.0MvWb7_gBfDQQOlcpmX4brBRk6YbOOVOInyvpJL1a7A'

DEEPSEEK_MODEL   = 'deepseek-v4-flash'   # use deepseek-v4-pro for higher quality
MIN_WORDS        = 40                    # skip pages with fewer words
MAX_TOKENS       = 6000                  # reasoning model needs ~4-5k for thinking + JSON output

SYSTEM_PROMPT = """You are a Malaysian SPM Physics curriculum specialist.
You receive raw text extracted from an SPM Physics textbook page.
Structure it into a teaching unit for students.

Return ONLY valid JSON with these exact keys:
{
  "skip": false,
  "bab": "Bab N: <chapter title in BM>",
  "subtopic": "<specific section heading on this page, or empty string>",
  "concept_title": "<short title for this teaching unit, max 8 words>",
  "concept_explanation": "<clear SPM-level explanation of the content, 2-5 sentences. Use the textbook content directly.>",
  "worked_example": "<any worked example, calculation, or solved problem on this page. Empty string if none.>",
  "common_mistakes": "<common student error related to this content. Empty string if not obvious.>",
  "keywords": ["term1", "term2", "term3"],
  "difficulty_level": 2
}

If the page is a cover, table of contents, blank, acknowledgements, or has no teachable physics content, return:
{"skip": true, "reason": "brief reason"}

Rules:
- bab must always be identified (look for 'Bab', 'BAB', chapter heading)
- concept_explanation must be accurate physics content, not just a description
- keywords should be physics terms, 3-8 items
- difficulty_level: 1=basic, 2=intermediate, 3=advanced SPM
- Return JSON only, no markdown, no extra text"""


def extract_page_text(doc, page_num):
    page = doc[page_num]
    return page.get_text(sort=True).strip()


def structure_with_deepseek(raw_text, current_bab, page_num):
    user_msg = f"[Page {page_num+1}] Current chapter context: {current_bab}\n\nExtracted text:\n{raw_text[:3000]}"

    r = requests.post(
        'https://api.deepseek.com/chat/completions',
        headers={'Authorization': f'Bearer {DEEPSEEK_API_KEY}', 'Content-Type': 'application/json'},
        json={
            'model': DEEPSEEK_MODEL,
            'messages': [
                {'role': 'system', 'content': SYSTEM_PROMPT},
                {'role': 'user',   'content': user_msg}
            ],
            'temperature': 0.1,
            'max_tokens': MAX_TOKENS,
        },
        timeout=120
    )

    if r.status_code != 200:
        raise Exception(f'DeepSeek API error {r.status_code}: {r.text[:200]}')

    resp_json = r.json()
    content = resp_json['choices'][0]['message']['content'].strip()
    if not content:
        # Reasoning model used all tokens on thinking — raise so caller retries or logs error
        finish = resp_json['choices'][0].get('finish_reason', 'unknown')
        raise Exception(f'Empty content from DeepSeek (finish_reason={finish}). Increase MAX_TOKENS.')

    # Strip markdown fences if present
    content = re.sub(r'^```(?:json)?\s*', '', content, flags=re.MULTILINE)
    content = re.sub(r'\s*```$', '', content, flags=re.MULTILINE).strip()
    return json.loads(content)


def detect_bab(text, current_bab):
    """Update current Bab if a new chapter heading is found.
    Handles PDF layout artifacts like 'BabBab 1' or 'BAB BAB 2'.
    """
    # Normalise repeated 'Bab' artifacts from 2-column PDF layout
    clean = re.sub(r'(Bab|BAB)\s*(Bab|BAB)\s*', 'Bab ', text)
    match = re.search(r'[Bb][Aa][Bb]\s+(\d+)\s*[:\s–\-]+\s*([^\n]{3,60})', clean)
    if match:
        num = match.group(1)
        title = match.group(2).strip().rstrip('.')
        return f'Bab {num}: {title}'
    # Simpler fallback: just "Bab N" with no title
    match2 = re.search(r'[Bb][Aa][Bb]\s+(\d+)', clean)
    if match2:
        num = match2.group(1)
        if num != current_bab.split()[-1]:  # only update if different chapter
            return f'Bab {num}'
    return current_bab


def save_to_supabase(chunk):
    r = requests.post(
        f'{SUPABASE_URL}/rest/v1/concept_chunks',
        headers={
            'apikey': SUPABASE_KEY,
            'Authorization': f'Bearer {SUPABASE_KEY}',
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal'
        },
        json=chunk,
        timeout=15
    )
    if r.status_code not in (200, 201):
        print(f'        Supabase error {r.status_code}: {r.text[:200]}')
    return r.status_code in (200, 201)


def process_textbook(pdf_path, subject, form, start_page=0, end_page=None):
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    end_page = end_page if end_page is not None else total_pages

    print(f'Processing: {pdf_path}')
    print(f'Subject: {subject}  Form: {form}  Pages: {start_page+1}-{end_page} of {total_pages}')
    print('-' * 60)

    current_bab = 'Bab 1'
    saved = skipped = errors = 0
    results = []

    for page_num in range(start_page, end_page):
        raw_text = extract_page_text(doc, page_num)
        word_count = len(raw_text.split())

        # Update chapter tracking
        current_bab = detect_bab(raw_text, current_bab)

        prefix = f'  p{page_num+1:>3}/{end_page}'

        if word_count < MIN_WORDS:
            print(f'{prefix}  SKIP  (only {word_count} words)')
            skipped += 1
            time.sleep(0.1)
            continue

        try:
            data = structure_with_deepseek(raw_text, current_bab, page_num)

            if data.get('skip'):
                print(f'{prefix}  SKIP  {data.get("reason","")}')
                skipped += 1
            else:
                # Map to concept_chunks schema
                chunk = {
                    'subject':              subject,
                    'form':                 str(form),
                    'topic':                data.get('bab', current_bab),
                    'subtopic':             data.get('subtopic', ''),
                    'concept_title':        data.get('concept_title', data.get('bab', '')),
                    'concept_explanation':  data.get('concept_explanation', ''),
                    'worked_example':       data.get('worked_example', ''),
                    'common_mistakes':      data.get('common_mistakes', ''),
                    'keywords':             data.get('keywords', []),
                    'difficulty_level':     data.get('difficulty_level', 2),
                    'level':                'SPM',
                    'country':              'MY',
                    'source_name':          f'F{form} Physics KSSM Textbook',
                }

                ok = save_to_supabase(chunk)
                status = 'SAVED' if ok else 'DB-ERR'
                if ok:
                    saved += 1
                else:
                    errors += 1

                label = data.get('bab', current_bab)
                sub = data.get('subtopic', '')
                print(f'{prefix}  {status}  {label} | {sub}'
                      .encode('ascii', 'replace').decode())

            results.append({'page': page_num+1, 'bab': current_bab, **data})

        except json.JSONDecodeError as e:
            # Try to extract JSON substring
            try:
                match = re.search(r'\{[\s\S]+\}', str(e.__context__ or ''))
                if not match:
                    raise
                data = json.loads(match.group())
                print(f'{prefix}  RETRY-OK  (extracted JSON from response)')
            except Exception:
                print(f'{prefix}  JSON-ERR  {str(e)[:80]}')
                errors += 1
        except Exception as e:
            print(f'{prefix}  ERROR  {str(e)[:80]}')
            errors += 1
            time.sleep(2)

        time.sleep(0.8)  # ~75 pages/minute, well within rate limits

    print('-' * 60)
    print(f'DONE: {saved} saved, {skipped} skipped, {errors} errors')

    # Save backup JSON locally
    backup_path = rf'C:\Learnova\{subject}_F{form}_results.json'
    with open(backup_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f'Backup: {backup_path}')
    return saved, skipped, errors


# ── Entry point ──────────────────────────────────────────────────────
if __name__ == '__main__':
    # Resume F4 from Bab 5 (page 176, 0-indexed 175). Bab 1-4 already in Supabase.
    print('=== FORM 4 (Bab 5-7, pages 171-295) ===')
    s4, sk4, e4 = process_textbook(
        pdf_path=r'C:\learnova_app\textbooks\F4 Physics.pdf',
        subject='MY-Physics',
        form=4,
        start_page=170,  # page 171 (0-indexed), 5 pages before Bab 5 for safety
        end_page=None    # process through end
    )

    # Full run — F5 Physics (skip first 8 front-matter pages)
    print()
    print('=== FORM 5 ===')
    s5, sk5, e5 = process_textbook(
        pdf_path=r'C:\learnova_app\textbooks\F5 Physics.pdf',
        subject='MY-Physics',
        form=5,
        start_page=8,
        end_page=None   # process all 268 pages
    )

    print()
    print(f'GRAND TOTAL: {s4+s5} saved, {sk4+sk5} skipped, {e4+e5} errors')
