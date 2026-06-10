"""
Reprocess MY-English Form 4 Part 2 textbook (284 pages).
Saves backup to MY-English_reprocess_results.json as requested.
"""
import sys
sys.path.insert(0, r'C:\Learnova')

import fitz
import json
import requests
import os
import time
import re

DEEPSEEK_API_KEY = os.environ.get('DEEPSEEK_API_KEY', 'sk-116af79bcdc740dc914cf072fd735cb5')
SUPABASE_URL     = 'https://nxvbpanozswheackgwni.supabase.co'
SUPABASE_KEY     = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54dmJwYW5venN3aGVhY2tnd25pIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQxNTA3NCwiZXhwIjoyMDkwOTkxMDc0fQ.0MvWb7_gBfDQQOlcpmX4brBRk6YbOOVOInyvpJL1a7A'
DEEPSEEK_MODEL   = 'deepseek-v4-flash'
MIN_WORDS        = 40
MAX_TOKENS       = 6000

SYSTEM_PROMPT = """You are a Malaysian SPM English Language curriculum specialist.
You receive raw text from an SPM English textbook page (KSSM Form 4).
Structure it into a teaching unit for Form 4 SPM students.

Return ONLY valid JSON:
{
  "skip": false,
  "bab": "Unit N: <unit title>",
  "subtopic": "<section heading or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<clear SPM-level explanation, 2-5 sentences. Cover grammar rules, vocabulary, reading skills, writing techniques, speaking skills, or literature analysis.>",
  "worked_example": "<any model answer, example text, sample essay paragraph, or solved exercise. Empty string if none.>",
  "common_mistakes": "<common SPM student error in this area. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 2
}

Focus on extracting:
- Writing samples and model essays (directed writing, continuous writing)
- Grammar rules and examples
- Comprehension strategies and reading skills
- Speaking test phrases and structures
- Literature analysis frameworks (short stories, poems, novels)
- Vocabulary building and word usage

If page has no teachable English content (blank, images only, index, TOC, copyright page), return:
{"skip": true, "reason": "brief reason"}

Rules: bab/unit must always be identified from context; keywords are English language terms 3-8 items; difficulty 1-3; JSON only."""


def extract_page_text(doc, page_num):
    return doc[page_num].get_text(sort=True).strip()


def detect_chapter(text, current_chapter):
    clean = re.sub(r'(Unit|UNIT)\s*(Unit|UNIT)\s*', r'\1 ', text)
    patterns = [
        r'[Uu][Nn][Ii][Tt]\s+(\d+)\s*[:\s–\-]+\s*([^\n]{3,60})',
        r'[Cc]hapter\s+(\d+)\s*[:\s–\-]+\s*([^\n]{3,60})',
        r'[Uu][Nn][Ii][Tt]\s+(\d+)',
    ]
    for i, pattern in enumerate(patterns):
        m = re.search(pattern, clean)
        if m:
            num = m.group(1)
            title = m.group(2).strip().rstrip('.') if len(m.groups()) > 1 else ''
            if title:
                return f'Unit {num}: {title}'
            else:
                curr_num = re.search(r'\d+', current_chapter)
                if not curr_num or num != curr_num.group():
                    return f'Unit {num}'
    return current_chapter


def structure_with_deepseek(raw_text, current_chapter, page_num):
    user_msg = f"[Page {page_num+1}] Current unit context: {current_chapter}\n\nExtracted text:\n{raw_text[:3000]}"
    for attempt in range(3):
        try:
            r = requests.post(
                'https://api.deepseek.com/chat/completions',
                headers={'Authorization': f'Bearer {DEEPSEEK_API_KEY}', 'Content-Type': 'application/json'},
                json={
                    'model': DEEPSEEK_MODEL,
                    'messages': [
                        {'role': 'system', 'content': SYSTEM_PROMPT},
                        {'role': 'user',   'content': user_msg},
                    ],
                    'temperature': 0.1,
                    'max_tokens': MAX_TOKENS,
                },
                timeout=120,
            )
            if r.status_code == 429:
                wait = 60 * (attempt + 1)
                print(f'        Rate limited, waiting {wait}s...')
                time.sleep(wait)
                continue
            if r.status_code != 200:
                raise Exception(f'DeepSeek API error {r.status_code}: {r.text[:200]}')
            resp_json = r.json()
            content = resp_json['choices'][0]['message']['content'].strip()
            if not content:
                raise Exception(f'Empty content (finish_reason={resp_json["choices"][0].get("finish_reason","?")})')
            content = re.sub(r'^```(?:json)?\s*', '', content, flags=re.MULTILINE)
            content = re.sub(r'\s*```$', '', content, flags=re.MULTILINE).strip()
            return json.loads(content)
        except json.JSONDecodeError:
            if attempt < 2:
                time.sleep(5)
                continue
            raise
    raise Exception('Failed after 3 attempts')


def save_to_supabase(chunk):
    r = requests.post(
        f'{SUPABASE_URL}/rest/v1/concept_chunks',
        headers={
            'apikey': SUPABASE_KEY,
            'Authorization': f'Bearer {SUPABASE_KEY}',
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal',
        },
        json=chunk,
        timeout=15,
    )
    return r.status_code in (200, 201)


def main():
    pdf_path = r'C:\Users\Yong\Downloads\Learnova Malaysia\Form 4\MY-English form 4-2.pdf'
    backup_path = r'C:\Learnova\MY-English_reprocess_results.json'

    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    print(f'Processing: {pdf_path}')
    print(f'Subject: MY-English  Form: 4  Pages: 1-{total_pages}')
    print('-' * 60)

    current_chapter = 'Unit 1'
    saved = skipped = errors = 0
    results = []

    for page_num in range(total_pages):
        raw_text = extract_page_text(doc, page_num)
        word_count = len(raw_text.split())
        current_chapter = detect_chapter(raw_text, current_chapter)
        prefix = f'  p{page_num+1:>3}/{total_pages}'

        if word_count < MIN_WORDS:
            print(f'{prefix}  SKIP  (only {word_count} words)')
            skipped += 1
            time.sleep(0.1)
            continue

        try:
            data = structure_with_deepseek(raw_text, current_chapter, page_num)
            if data.get('skip'):
                print(f'{prefix}  SKIP  {data.get("reason", "")}')
                skipped += 1
            else:
                chunk = {
                    'subject':             'MY-English',
                    'form':                '4',
                    'topic':               data.get('bab', current_chapter),
                    'subtopic':            data.get('subtopic', ''),
                    'concept_title':       data.get('concept_title', ''),
                    'concept_explanation': data.get('concept_explanation', ''),
                    'worked_example':      data.get('worked_example', ''),
                    'common_mistakes':     data.get('common_mistakes', ''),
                    'keywords':            data.get('keywords', []),
                    'difficulty_level':    data.get('difficulty_level', 2),
                    'level':               'SPM',
                    'country':             'MY',
                    'source_name':         'F4 English KSSM Textbook (Part 2)',
                }
                ok = save_to_supabase(chunk)
                if ok:
                    saved += 1
                    label = data.get('bab', current_chapter)
                    sub = data.get('subtopic', '')
                    print(f'{prefix}  SAVED  {label} | {sub}'.encode('ascii', 'replace').decode())
                else:
                    errors += 1
                    print(f'{prefix}  DB-ERR  {data.get("bab", current_chapter)}')
            results.append({'page': page_num + 1, 'bab': current_chapter, **data})
        except json.JSONDecodeError as e:
            print(f'{prefix}  JSON-ERR  {str(e)[:80]}')
            errors += 1
        except Exception as e:
            print(f'{prefix}  ERROR  {str(e)[:80]}')
            errors += 1
            time.sleep(2)

        time.sleep(0.8)

        # Save checkpoint every 50 pages
        if (page_num + 1) % 50 == 0:
            with open(backup_path, 'w', encoding='utf-8') as f:
                json.dump(results, f, ensure_ascii=False, indent=2)
            print(f'  [CHECKPOINT] Saved {len(results)} results so far')

    print('-' * 60)
    print(f'DONE: {saved} saved, {skipped} skipped, {errors} errors')

    with open(backup_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f'Backup: {backup_path}')

    doc.close()


if __name__ == '__main__':
    main()
