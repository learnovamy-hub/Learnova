"""
Processes missing F4 textbooks from Downloads folder.
"""

import multiprocessing
import os
import sys

os.environ.setdefault('DEEPSEEK_API_KEY', 'sk-116af79bcdc740dc914cf072fd735cb5')
os.environ.setdefault('PYTHONIOENCODING', 'utf-8')

from process_subject import process_textbook

BASE = r'C:\Users\Yong\Downloads\Learnova Malaysia\Form 4'

JOBS = [
    (
        'MY-AddMaths', 'AddMaths', 4,
        os.path.join(BASE, 'DLP Additional Mathematics Form 4.pdf'), 11,
        'F4 Additional Mathematics KSSM Textbook (DLP)',
    ),
    (
        'MY-BahasaMalaysia', 'BahasaMalaysia', 4,
        os.path.join(BASE, 'MY- F4 BAHASA MELAYU.pdf'), 8,
        'F4 Bahasa Malaysia KSSM Textbook',
    ),
    (
        'MY-English', 'English', 4,
        os.path.join(BASE, 'MY- F4 English.pdf'), 4,
        'F4 English KSSM Textbook',
    ),
    (
        'MY-Sejarah', 'Sejarah', 4,
        os.path.join(BASE, 'MY-F4 SEJARAH.pdf'), 11,
        'F4 Sejarah KSSM Textbook',
    ),
]


def run_job(args):
    subject_tag, subject_name, form, pdf_path, start_page_1idx, source_label = args

    safe_name = subject_tag.replace('MY-', '') + f'_F{form}_' + os.path.basename(pdf_path).replace(' ', '_').replace('.pdf', '')
    log_path = rf'C:\Learnova\logs\{safe_name}.log'

    sys.stdout = open(log_path, 'w', encoding='utf-8', buffering=1)
    sys.stderr = sys.stdout

    try:
        saved, skipped, errors = process_textbook(
            pdf_path=pdf_path,
            subject_tag=subject_tag,
            subject_name=subject_name,
            form=form,
            source_label=source_label,
            start_page=start_page_1idx - 1,
            end_page=None,
        )
        result = f'DONE: {saved} saved, {skipped} skipped, {errors} errors'
        print(result)
        sys.stdout.flush()
        return (subject_tag, form, os.path.basename(pdf_path), saved, skipped, errors, None)
    except Exception as e:
        msg = f'FATAL: {e}'
        print(msg)
        sys.stdout.flush()
        return (subject_tag, form, os.path.basename(pdf_path), 0, 0, 0, str(e))
    finally:
        sys.stdout.close()


if __name__ == '__main__':
    print(f'Launching {len(JOBS)} F4 jobs in parallel...')
    for j in JOBS:
        print(f'  {j[0]} F{j[2]}: {os.path.basename(j[3])} ({j[3]})')
    print()

    with multiprocessing.Pool(processes=len(JOBS)) as pool:
        results = pool.map(run_job, JOBS)

    print('\n=== ALL F4 JOBS COMPLETE ===')
    total_saved = total_skipped = total_errors = 0
    for tag, form, pdf, saved, skipped, errors, err in results:
        status = f'{saved} saved, {skipped} skipped, {errors} errors'
        fatal = f' [FATAL: {err}]' if err else ''
        print(f'  {tag} F{form} ({pdf}): {status}{fatal}')
        total_saved   += saved
        total_skipped += skipped
        total_errors  += errors

    print(f'\nGRAND TOTAL: {total_saved} saved, {total_skipped} skipped, {total_errors} errors')
