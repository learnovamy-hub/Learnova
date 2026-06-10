"""
Learnova Generic SPM Textbook Processor
Usage: python process_subject.py <subject_tag> <subject_name> <form> <pdf_path> <start_page> [end_page]
  subject_tag  : e.g. MY-Mathematics
  subject_name : e.g. Mathematics (human-readable, used in prompts)
  form         : 4 or 5
  pdf_path     : full path to PDF
  start_page   : 1-indexed first page to process
  end_page     : optional 1-indexed last page (default: all)
"""

import fitz
import json
import requests
import os
import sys
import time
import re

DEEPSEEK_API_KEY = os.environ.get('DEEPSEEK_API_KEY', 'sk-116af79bcdc740dc914cf072fd735cb5')
SUPABASE_URL     = 'https://nxvbpanozswheackgwni.supabase.co'
SUPABASE_KEY     = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54dmJwYW5venN3aGVhY2tnd25pIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQxNTA3NCwiZXhwIjoyMDkwOTkxMDc0fQ.0MvWb7_gBfDQQOlcpmX4brBRk6YbOOVOInyvpJL1a7A'

DEEPSEEK_MODEL   = 'deepseek-v4-flash'
MIN_WORDS        = 40
MAX_TOKENS       = 6000

SUBJECT_PROMPTS = {
    'AL-Mathematics': """You are a Cambridge International AS & A Level Mathematics specialist.
You receive raw text extracted from a Cambridge A Level Mathematics coursebook page.
Structure it into a precise teaching unit for AS/A Level students.

Return ONLY valid JSON:
{{
  "skip": false,
  "bab": "Chapter N: <chapter title>",
  "subtopic": "<section heading or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<rigorous A-Level explanation, 2-5 sentences. Include definitions, theorems, proofs or key steps. Be mathematically precise.>",
  "worked_example": "<any worked example or solved exercise on this page. Include full working. Empty string if none.>",
  "common_mistakes": "<common A-Level student error. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 3
}}

If page has no teachable content (answers only, blank, index, TOC, copyright), return:
{{"skip": true, "reason": "brief reason"}}

Rules: chapter must always be identified; keywords are mathematical terms 3-8 items; difficulty 1-3 (3=A2 level); JSON only.""",

    'AL-FurtherMaths': """You are a Cambridge International AS & A Level Further Mathematics specialist.
You receive raw text from a Cambridge A Level Further Mathematics coursebook page.
Structure it into a precise teaching unit for Further Maths students.

Return ONLY valid JSON:
{{
  "skip": false,
  "bab": "Chapter N: <chapter title>",
  "subtopic": "<section heading or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<rigorous Further Maths explanation, 2-5 sentences. Include definitions, proofs, or key results. Be mathematically precise.>",
  "worked_example": "<worked example or solved problem with full working. Empty string if none.>",
  "common_mistakes": "<common student error. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 3
}}

If page has no teachable content, return: {{"skip": true, "reason": "brief reason"}}
Rules: chapter must always be identified; keywords 3-8 items; JSON only.""",

    'AL-Physics': """You are a Cambridge International AS & A Level Physics specialist.
You receive raw text from a Cambridge A Level Physics coursebook page.
Structure it into a precise teaching unit.

Return ONLY valid JSON:
{{
  "skip": false,
  "bab": "Chapter N: <chapter title>",
  "subtopic": "<section heading or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<rigorous A-Level explanation, 2-5 sentences. Include laws, equations, and physical reasoning.>",
  "worked_example": "<any calculation or solved problem with full working. Empty string if none.>",
  "common_mistakes": "<common A-Level student error. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 3
}}

If page has no teachable content, return: {{"skip": true, "reason": "brief reason"}}
Rules: chapter must always be identified; keywords are physics terms 3-8 items; JSON only.""",

    'AL-Chemistry': """You are a Cambridge International AS & A Level Chemistry specialist.
You receive raw text from a Cambridge A Level Chemistry coursebook page.
Structure it into a precise teaching unit.

Return ONLY valid JSON:
{{
  "skip": false,
  "bab": "Chapter N: <chapter title>",
  "subtopic": "<section heading or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<rigorous A-Level explanation, 2-5 sentences. Include equations, mechanisms, or key chemical principles.>",
  "worked_example": "<any calculation, mechanism, or solved problem. Empty string if none.>",
  "common_mistakes": "<common A-Level student error. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 3
}}

If page has no teachable content, return: {{"skip": true, "reason": "brief reason"}}
Rules: chapter must always be identified; keywords are chemistry terms 3-8 items; JSON only.""",

    'AL-Biology': """You are a Cambridge International AS & A Level Biology specialist.
You receive raw text from a Cambridge A Level Biology coursebook page.
Structure it into a precise teaching unit.

Return ONLY valid JSON:
{{
  "skip": false,
  "bab": "Chapter N: <chapter title>",
  "subtopic": "<section heading or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<rigorous A-Level explanation, 2-5 sentences. Include biological processes, structures, and mechanisms.>",
  "worked_example": "<any data analysis, experiment design, or solved question. Empty string if none.>",
  "common_mistakes": "<common A-Level student error. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 3
}}

If page has no teachable content, return: {{"skip": true, "reason": "brief reason"}}
Rules: chapter must always be identified; keywords are biology terms 3-8 items; JSON only.""",

    'Mathematics': """You are a Malaysian SPM Mathematics curriculum specialist.
You receive raw text extracted from an SPM Mathematics textbook page (KSSM).
Structure it into a teaching unit for Form {form} students.

Return ONLY valid JSON with these exact keys:
{{
  "skip": false,
  "bab": "Bab N: <chapter title>",
  "subtopic": "<specific section heading, or empty string>",
  "concept_title": "<short title for this teaching unit, max 8 words>",
  "concept_explanation": "<clear SPM-level explanation, 2-5 sentences. Include definitions, theorems, or rules.>",
  "worked_example": "<any worked example, calculation, or solved problem on this page. Empty string if none.>",
  "common_mistakes": "<common student error related to this content. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 2
}}

If the page is a cover, table of contents, blank, or has no teachable mathematics content, return:
{{"skip": true, "reason": "brief reason"}}

Rules:
- bab must always be identified (Bab, Chapter, or Unit heading)
- keywords should be mathematical terms, 3-8 items
- difficulty_level: 1=basic, 2=intermediate, 3=advanced SPM
- Return JSON only, no markdown, no extra text""",

    'AddMaths': """You are a Malaysian SPM Additional Mathematics curriculum specialist.
You receive raw text from an SPM Add Maths textbook page (KSSM Form {form}).
Structure it into a teaching unit.

Return ONLY valid JSON:
{{
  "skip": false,
  "bab": "Bab N: <chapter title>",
  "subtopic": "<section heading or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<SPM-level explanation, 2-5 sentences. Include definitions, formulae, theorems.>",
  "worked_example": "<worked example or solved problem. Empty string if none.>",
  "common_mistakes": "<common error. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 2
}}

If page has no teachable Add Maths content (cover, TOC, blank, etc.), return:
{{"skip": true, "reason": "brief reason"}}

Rules: bab must always be identified; keywords 3-8 math terms; difficulty 1-3; JSON only.""",

    'Biology': """You are a Malaysian SPM Biology curriculum specialist.
You receive raw text from an SPM Biology textbook page (KSSM Form {form}).
Structure it into a teaching unit.

Return ONLY valid JSON:
{{
  "skip": false,
  "bab": "Bab N: <chapter title>",
  "subtopic": "<section heading or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<clear SPM-level explanation, 2-5 sentences. Use accurate biology content.>",
  "worked_example": "<any experiment, worked example, or data interpretation on this page. Empty string if none.>",
  "common_mistakes": "<common student misconception. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 2
}}

If page has no teachable Biology content, return:
{{"skip": true, "reason": "brief reason"}}

Rules: bab must always be identified; keywords are biology terms 3-8 items; difficulty 1-3; JSON only.""",

    'Chemistry': """You are a Malaysian SPM Chemistry curriculum specialist.
You receive raw text from an SPM Chemistry textbook page (KSSM Form {form}).
Structure it into a teaching unit.

Return ONLY valid JSON:
{{
  "skip": false,
  "bab": "Bab N: <chapter title>",
  "subtopic": "<section heading or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<clear SPM-level explanation, 2-5 sentences. Include chemical equations where relevant.>",
  "worked_example": "<any calculation, experiment, or solved problem. Empty string if none.>",
  "common_mistakes": "<common student error. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 2
}}

If page has no teachable Chemistry content, return:
{{"skip": true, "reason": "brief reason"}}

Rules: bab must always be identified; keywords are chemistry terms 3-8 items; difficulty 1-3; JSON only.""",

    'BahasaMalaysia': """Anda ialah pakar kurikulum Bahasa Malaysia SPM (KSSM).
Anda menerima teks yang diekstrak daripada halaman buku teks Bahasa Malaysia Tingkatan {form}.
Susun kandungan ini sebagai unit pengajaran.

Kembalikan HANYA JSON yang sah dengan kunci-kunci ini:
{{
  "skip": false,
  "bab": "Bab N: <tajuk bab>",
  "subtopic": "<tajuk subtopik atau rentetan kosong>",
  "concept_title": "<tajuk pendek, maksimum 8 patah perkataan>",
  "concept_explanation": "<penerangan jelas peringkat SPM, 2-5 ayat. Sertakan huraian tentang tatabahasa, sastera, atau kemahiran bahasa.>",
  "worked_example": "<contoh karangan, latihan, atau soalan yang diselesaikan. Rentetan kosong jika tiada.>",
  "common_mistakes": "<kesilapan biasa pelajar. Rentetan kosong jika tidak jelas.>",
  "keywords": ["istilah1", "istilah2"],
  "difficulty_level": 2
}}

Jika halaman tidak mengandungi kandungan BM yang boleh diajar, kembalikan:
{{"skip": true, "reason": "sebab ringkas"}}

Peraturan: bab mesti dikenal pasti; keywords adalah istilah bahasa 3-8 item; difficulty 1-3; JSON sahaja.""",

    'English': """You are a Malaysian SPM English Language curriculum specialist.
You receive raw text from an SPM English textbook page (KSSM Form {form}).
Structure it into a teaching unit.

Return ONLY valid JSON:
{{
  "skip": false,
  "bab": "Unit N: <unit title>",
  "subtopic": "<section heading or empty string>",
  "concept_title": "<short title, max 8 words>",
  "concept_explanation": "<clear SPM-level explanation, 2-5 sentences. Cover grammar rules, vocabulary, reading skills, or writing techniques.>",
  "worked_example": "<any model answer, example text, or solved exercise. Empty string if none.>",
  "common_mistakes": "<common student error in this area. Empty string if not obvious.>",
  "keywords": ["term1", "term2"],
  "difficulty_level": 2
}}

If page has no teachable English content, return:
{{"skip": true, "reason": "brief reason"}}

Rules: bab/unit must always be identified; keywords are English language terms 3-8 items; difficulty 1-3; JSON only.""",

    'Sejarah': """Anda ialah pakar kurikulum Sejarah SPM (KSSM).
Anda menerima teks yang diekstrak daripada halaman buku teks Sejarah Tingkatan {form}.
Susun kandungan ini sebagai unit pengajaran.

Kembalikan HANYA JSON yang sah:
{{
  "skip": false,
  "bab": "Bab N: <tajuk bab>",
  "subtopic": "<tajuk subtopik atau rentetan kosong>",
  "concept_title": "<tajuk pendek, maksimum 8 patah perkataan>",
  "concept_explanation": "<penerangan jelas peringkat SPM, 2-5 ayat. Sertakan fakta, tokoh, tarikh, atau peristiwa penting.>",
  "worked_example": "<contoh soalan esei atau isi jawapan yang diselesaikan. Rentetan kosong jika tiada.>",
  "common_mistakes": "<kesilapan biasa pelajar. Rentetan kosong jika tidak jelas.>",
  "keywords": ["istilah1", "istilah2"],
  "difficulty_level": 2
}}

Jika halaman tidak mengandungi kandungan Sejarah yang boleh diajar, kembalikan:
{{"skip": true, "reason": "sebab ringkas"}}

Peraturan: bab mesti dikenal pasti; keywords adalah istilah sejarah 3-8 item; difficulty 1-3; JSON sahaja.""",
}


def get_system_prompt(subject_name, form):
    template = SUBJECT_PROMPTS.get(subject_name, SUBJECT_PROMPTS['Mathematics'])
    return template.format(form=form)


def extract_page_text(doc, page_num):
    return doc[page_num].get_text(sort=True).strip()


def detect_chapter(text, current_chapter, subject_name):
    """Detect chapter/unit/bab heading from page text."""
    clean = re.sub(r'(Bab|BAB|Unit|UNIT)\s*(Bab|BAB|Unit|UNIT)\s*', r'\1 ', text)

    patterns = [
        r'[Bb][Aa][Bb]\s+(\d+)\s*[:\s–\-]+\s*([^\n]{3,60})',
        r'[Uu][Nn][Ii][Tt]\s+(\d+)\s*[:\s–\-]+\s*([^\n]{3,60})',
        r'[Cc]hapter\s+(\d+)\s*[:\s–\-]+\s*([^\n]{3,60})',
    ]
    prefix_map = {'b': 'Bab', 'u': 'Unit', 'c': 'Chapter'}

    for pattern in patterns:
        m = re.search(pattern, clean)
        if m:
            num = m.group(1)
            title = m.group(2).strip().rstrip('.')
            first_char = pattern[1].lower()
            prefix = prefix_map.get(first_char, 'Bab')
            return f'{prefix} {num}: {title}'

    # Fallback: just number, no title
    for pattern, prefix in [
        (r'[Bb][Aa][Bb]\s+(\d+)', 'Bab'),
        (r'[Uu][Nn][Ii][Tt]\s+(\d+)', 'Unit'),
    ]:
        m2 = re.search(pattern, clean)
        if m2:
            num = m2.group(1)
            curr_num = re.search(r'\d+', current_chapter)
            if not curr_num or num != curr_num.group():
                return f'{prefix} {num}'

    return current_chapter


def structure_with_deepseek(raw_text, current_chapter, page_num, system_prompt):
    user_msg = f"[Page {page_num+1}] Current chapter context: {current_chapter}\n\nExtracted text:\n{raw_text[:3000]}"

    for attempt in range(3):
        try:
            r = requests.post(
                'https://api.deepseek.com/chat/completions',
                headers={'Authorization': f'Bearer {DEEPSEEK_API_KEY}', 'Content-Type': 'application/json'},
                json={
                    'model': DEEPSEEK_MODEL,
                    'messages': [
                        {'role': 'system', 'content': system_prompt},
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
                finish = resp_json['choices'][0].get('finish_reason', 'unknown')
                raise Exception(f'Empty content from DeepSeek (finish_reason={finish})')

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
    if r.status_code not in (200, 201):
        print(f'        Supabase error {r.status_code}: {r.text[:200]}')
    return r.status_code in (200, 201)


def process_textbook(pdf_path, subject_tag, subject_name, form, source_label,
                     start_page=0, end_page=None, level='SPM', country='MY'):
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    end_page = end_page if end_page is not None else total_pages

    system_prompt = get_system_prompt(subject_name, form)

    print(f'Processing: {pdf_path}')
    print(f'Subject: {subject_tag}  Form: {form}  Pages: {start_page+1}-{end_page} of {total_pages}')
    print('-' * 60)

    current_chapter = 'Bab 1'
    saved = skipped = errors = 0
    results = []

    for page_num in range(start_page, end_page):
        raw_text = extract_page_text(doc, page_num)
        word_count = len(raw_text.split())
        current_chapter = detect_chapter(raw_text, current_chapter, subject_name)

        prefix = f'  p{page_num+1:>3}/{end_page}'

        if word_count < MIN_WORDS:
            print(f'{prefix}  SKIP  (only {word_count} words)')
            skipped += 1
            time.sleep(0.1)
            continue

        try:
            data = structure_with_deepseek(raw_text, current_chapter, page_num, system_prompt)

            if data.get('skip'):
                print(f'{prefix}  SKIP  {data.get("reason", "")}')
                skipped += 1
            else:
                chunk = {
                    'subject':             subject_tag,
                    'form':                str(form),
                    'topic':               data.get('bab', current_chapter),
                    'subtopic':            data.get('subtopic', ''),
                    'concept_title':       data.get('concept_title', ''),
                    'concept_explanation': data.get('concept_explanation', ''),
                    'worked_example':      data.get('worked_example', ''),
                    'common_mistakes':     data.get('common_mistakes', ''),
                    'keywords':            data.get('keywords', []),
                    'difficulty_level':    data.get('difficulty_level', 2),
                    'level':               level,
                    'country':             country,
                    'source_name':         source_label,
                }
                ok = save_to_supabase(chunk)
                if ok:
                    saved += 1
                    label = data.get('bab', current_chapter)
                    sub = data.get('subtopic', '')
                    print(f'{prefix}  SAVED  {label} | {sub}'.encode('ascii', 'replace').decode())
                else:
                    errors += 1
                    label = data.get('bab', current_chapter)
                    sub = data.get('subtopic', '')
                    print(f'{prefix}  DB-ERR  {label} | {sub}'.encode('ascii', 'replace').decode())

            results.append({'page': page_num + 1, 'bab': current_chapter, **data})

        except json.JSONDecodeError as e:
            print(f'{prefix}  JSON-ERR  {str(e)[:80]}')
            errors += 1
        except Exception as e:
            print(f'{prefix}  ERROR  {str(e)[:80]}')
            errors += 1
            time.sleep(2)

        time.sleep(0.8)

    print('-' * 60)
    print(f'DONE: {saved} saved, {skipped} skipped, {errors} errors')

    safe_tag = subject_tag.replace('/', '-').replace('\\', '-')
    backup_path = rf'C:\Learnova\{safe_tag}_F{form}_results.json'
    with open(backup_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f'Backup: {backup_path}')

    doc.close()
    return saved, skipped, errors


if __name__ == '__main__':
    if len(sys.argv) < 6:
        print('Usage: python process_subject.py <subject_tag> <subject_name> <form> <pdf_path> <start_page> [end_page]')
        sys.exit(1)

    subject_tag  = sys.argv[1]
    subject_name = sys.argv[2]
    form         = int(sys.argv[3])
    pdf_path     = sys.argv[4]
    start_page   = int(sys.argv[5]) - 1  # convert 1-indexed to 0-indexed
    end_page     = int(sys.argv[6]) - 1 if len(sys.argv) > 6 else None

    source_label = f'F{form} {subject_name} KSSM Textbook'

    saved, skipped, errors = process_textbook(
        pdf_path=pdf_path,
        subject_tag=subject_tag,
        subject_name=subject_name,
        form=form,
        source_label=source_label,
        start_page=start_page,
        end_page=end_page,
    )

    print(f'\nFINAL: {saved} saved, {skipped} skipped, {errors} errors')
