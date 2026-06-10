import requests

SUPABASE_URL = 'https://nxvbpanozswheackgwni.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54dmJwYW5venN3aGVhY2tnd25pIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQxNTA3NCwiZXhwIjoyMDkwOTkxMDc0fQ.0MvWb7_gBfDQQOlcpmX4brBRk6YbOOVOInyvpJL1a7A'

TEST_CASES = [
    ('MY-Physics',          'Fizik Nuklear',        'bahasa_malaysia'),
    ('MY-Chemistry',        'Keseimbangan Redoks',  'bahasa_malaysia'),
    ('MY-Biology',          'Respirasi Sel',        'bahasa_malaysia'),
    ('MY-Mathematics',      'Quadratic Functions',  'bahasa_malaysia'),
    ('MY-AddMaths',         'Integration',          'bahasa_malaysia'),
    ('MY-BahasaMalaysia',   'Tema 1',               'bahasa_malaysia'),
    ('MY-English',          'Writing',              'english'),
    ('MY-Sejarah',          'Bab 1',                'bahasa_malaysia'),
    ('AL-Physics',          'Mechanics',            'english'),
    ('AL-Chemistry',        'Organic Chemistry',    'english'),
    ('AL-Biology',          'Cell Biology',         'english'),
    ('AL-Mathematics',      'Calculus',             'english'),
    ('AL-FurtherMaths',     'Matrices',             'english'),
    ('ID-Fisika',           'Mekanika',             'bahasa_indonesia'),
    ('ID-Matematika',       'Aljabar',              'bahasa_indonesia'),
]

headers = {
    'apikey': SUPABASE_KEY,
    'Authorization': 'Bearer ' + SUPABASE_KEY,
}

print('%-22s %-25s %-15s %s' % ('Subject', 'Topic', 'Language', 'Chunks | First 80 chars'))
print('-' * 100)

for subject, topic, lang in TEST_CASES:
    keyword = ' '.join(topic.split()[:4])
    r = requests.get(
        SUPABASE_URL + '/rest/v1/concept_chunks',
        headers=headers,
        params={
            'select': 'concept_title,concept_explanation',
            'subject': 'eq.' + subject,
            'topic': 'ilike.*' + keyword + '*',
            'limit': '5',
        }
    )
    rows = r.json() if r.ok else []
    n = len(rows)
    first = ''
    if n > 0 and rows[0].get('concept_explanation'):
        first = rows[0]['concept_explanation'][:80].replace('\n', ' ')
    elif n > 0 and rows[0].get('concept_title'):
        first = rows[0]['concept_title'][:80]

    # Fallback: count all chunks for this subject if topic match fails
    if n == 0:
        r2 = requests.get(
            SUPABASE_URL + '/rest/v1/concept_chunks',
            headers=headers,
            params={'select': 'id', 'subject': 'eq.' + subject, 'limit': '1'},
        )
        total = len(r2.json()) if r2.ok else 0
        note = '(topic mismatch, subject has %d total)' % total if total > 0 else '(NO CHUNKS)'
        print('%-22s %-25s %-15s 0 | %s' % (subject, topic[:25], lang, note))
    else:
        print('%-22s %-25s %-15s %d | %s' % (subject, topic[:25], lang, n, first[:60]))
