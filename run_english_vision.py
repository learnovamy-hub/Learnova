import os
"""
Vision-based processor for scanned English PDF (MY-English form 4-2.pdf).
Uses Claude vision API to OCR + structure each page in one pass.
Saves backup to MY-English_reprocess_results.json as requested.
"""
import fitz
import json
import requests
import base64
import time
import re

CLAUDE_API_KEY = os.environ["ANTHROPIC_API_KEY"]
SUPABASE_URL   = 'https://nxvbpanozswheackgwni.supabase.co'
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
CLAUDE_MODEL   = 'claude-haiku-4-5-20251001'

SYSTEM_PROMPT = """You are a Malaysian SPM English Language curriculum specialist and OCR expert.
You receive a scanned image of an SPM English textbook page (KSSM Form 4).
Your job is to READ the text from the image and structure it into a teaching unit.

Return ONLY valid JSON:
{
  "skip": false,
  "bab": "Unit N: <unit title from page>",
  "subtopic": "<section heading visible on page, or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<clear SPM-level explanation, 2-5 sentences based on content. Cover grammar rules, vocabulary, reading skills, writing techniques, speaking skills, or literature analysis.>",
  "worked_example": "<any model answer, example text, sample essay paragraph, dialogue, or exercise visible on page. Empty string if none.>",
  "common_mistakes": "<common SPM student error related to this content. Empty string if not obvious.>",
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

If the page is blank, just an image/diagram with no text, or a decorative page, return:
{"skip": true, "reason": "brief reason"}

If the page is a table of contents, index, copyright, or cover, return:
{"skip": true, "reason": "brief reason"}

Rules:
- Always identify the unit/chapter from any heading visible on the page
- keywords are English language terms, 3-8 items
- difficulty_level: 1=basic, 2=intermediate, 3=advanced SPM
- JSON only, no markdown wrapper"""


def page_to_base64(doc, page_num, dpi=150):
    page = doc[page_num]
    mat = fitz.Matrix(dpi/72, dpi/72)
    pix = page.get_pixmap(matrix=mat)
    png_bytes = pix.tobytes("png")
    return base64.standard_b64encode(png_bytes).decode('utf-8')


def structure_with_claude(img_b64, page_num, current_chapter):
    for attempt in range(3):
        try:
            resp = requests.post(
                'https://api.anthropic.com/v1/messages',
                headers={
                    'x-api-key': CLAUDE_API_KEY,
                    'anthropic-version': '2023-06-01',
                    'content-type': 'application/json',
                },
                json={
                    'model': CLAUDE_MODEL,
                    'max_tokens': 1024,
                    'system': SYSTEM_PROMPT,
                    'messages': [{
                        'role': 'user',
                        'content': [
                            {
                                'type': 'image',
                                'source': {
                                    'type': 'base64',
                                    'media_type': 'image/png',
                                    'data': img_b64,
                                },
                            },
                            {
                                'type': 'text',
                                'text': f'Page {page_num+1}. Current unit context: {current_chapter}. Extract and structure this page content.',
                            },
                        ],
                    }],
                },
                timeout=60,
            )

            if resp.status_code == 529 or resp.status_code == 429:
                wait = 30 * (attempt + 1)
                print(f'        Overloaded/rate-limited, waiting {wait}s...')
                time.sleep(wait)
                continue

            if resp.status_code != 200:
                raise Exception(f'Claude API error {resp.status_code}: {resp.text[:200]}')

            content = resp.json()['content'][0]['text'].strip()
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


def detect_chapter_from_data(data, current_chapter):
    bab = data.get('bab', '')
    if bab and bab != current_chapter and len(bab) > 4:
        return bab
    return current_chapter


def main():
    pdf_path   = r'C:\Users\Yong\Downloads\Learnova Malaysia\Form 4\MY-English form 4-2.pdf'
    backup_path = r'C:\Learnova\MY-English_reprocess_results.json'

    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    print(f'Processing (vision): {pdf_path}')
    print(f'Subject: MY-English  Form: 4  Pages: 1-{total_pages}')
    print(f'Model: {CLAUDE_MODEL}')
    print('-' * 60)

    current_chapter = 'Unit 1'
    saved = skipped = errors = 0
    results = []

    for page_num in range(total_pages):
        prefix = f'  p{page_num+1:>3}/{total_pages}'
        try:
            img_b64 = page_to_base64(doc, page_num, dpi=150)
            data = structure_with_claude(img_b64, page_num, current_chapter)
            current_chapter = detect_chapter_from_data(data, current_chapter)

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
            time.sleep(3)

        time.sleep(0.5)

        if (page_num + 1) % 25 == 0:
            with open(backup_path, 'w', encoding='utf-8') as f:
                json.dump(results, f, ensure_ascii=False, indent=2)
            pct = round((page_num + 1) / total_pages * 100)
            print(f'  [CHECKPOINT {pct}%] saved={saved} skipped={skipped} errors={errors}')

    print('-' * 60)
    print(f'DONE: {saved} saved, {skipped} skipped, {errors} errors')

    with open(backup_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f'Backup: {backup_path}')
    doc.close()


if __name__ == '__main__':
    main()
