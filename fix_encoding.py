"""
Fix UTF-8-as-Latin-1 double-encoding in concept_chunks for MY-Physics.
Encodes each string field as latin-1 to recover original UTF-8 bytes, then decodes as UTF-8.
Only PATCHes rows where at least one field changed.
"""

import requests
import json
import sys

SUPABASE_URL = 'https://nxvbpanozswheackgwni.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54dmJwYW5venN3aGVhY2tnd25pIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQxNTA3NCwiZXhwIjoyMDkwOTkxMDc0fQ.0MvWb7_gBfDQQOlcpmX4brBRk6YbOOVOInyvpJL1a7A'

HEADERS = {
    'apikey': SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}',
    'Content-Type': 'application/json',
    'Prefer': 'return=minimal',
}

TEXT_FIELDS = [
    'topic', 'subtopic', 'concept_title',
    'concept_explanation', 'worked_example', 'common_mistakes',
]


def fix(text):
    """Try to fix double-encoded UTF-8. Returns original string if fix fails or wasn't needed."""
    if not text:
        return text
    try:
        fixed = text.encode('latin-1').decode('utf-8')
        return fixed if fixed != text else text
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text


def fix_keywords(kws):
    if not kws:
        return kws
    return [fix(k) for k in kws]


def fetch_all(subject):
    rows = []
    offset = 0
    limit = 500
    while True:
        r = requests.get(
            f'{SUPABASE_URL}/rest/v1/concept_chunks',
            headers=HEADERS,
            params={
                'subject': f'eq.{subject}',
                'select': 'id,topic,subtopic,concept_title,concept_explanation,worked_example,common_mistakes,keywords',
                'limit': limit,
                'offset': offset,
            },
            timeout=30,
        )
        batch = r.json()
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < limit:
            break
        offset += limit
    return rows


def patch_row(row_id, payload):
    r = requests.patch(
        f'{SUPABASE_URL}/rest/v1/concept_chunks?id=eq.{row_id}',
        headers=HEADERS,
        json=payload,
        timeout=15,
    )
    return r.status_code in (200, 204)


def main():
    subject = 'MY-Physics'
    print(f'Fetching all {subject} rows...')
    rows = fetch_all(subject)
    print(f'Fetched {len(rows)} rows')

    fixed_count = 0
    error_count = 0

    for row in rows:
        payload = {}

        for field in TEXT_FIELDS:
            original = row.get(field) or ''
            corrected = fix(original)
            if corrected != original:
                payload[field] = corrected

        kws_original = row.get('keywords') or []
        kws_fixed = fix_keywords(kws_original)
        if kws_fixed != kws_original:
            payload['keywords'] = kws_fixed

        if not payload:
            continue  # nothing to fix

        ok = patch_row(row['id'], payload)
        if ok:
            fixed_count += 1
            title = fix(row.get('concept_title', ''))
            print(f'  FIXED  id={row["id"]}  {title[:50]}')
        else:
            error_count += 1
            print(f'  ERROR  id={row["id"]}')

    print(f'\nDone: {fixed_count} rows fixed, {error_count} errors, {len(rows) - fixed_count - error_count} already clean')


if __name__ == '__main__':
    main()
