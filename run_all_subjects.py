"""
Launches all SPM subject textbook processing jobs in parallel using multiprocessing.
Each job runs process_textbook() in its own OS process.
"""

import multiprocessing
import sys
import os

os.environ.setdefault('DEEPSEEK_API_KEY', 'sk-116af79bcdc740dc914cf072fd735cb5')
os.environ.setdefault('PYTHONIOENCODING', 'utf-8')

from process_subject import process_textbook

JOBS = [
    # (subject_tag, subject_name, form, pdf_path, start_page_1indexed, source_label)
    (
        'MY-Mathematics', 'Mathematics', 4,
        r'C:\learnova_app\textbooks\F4 Maths.pdf', 11,
        'F4 Mathematics KSSM Textbook',
    ),
    (
        'MY-Mathematics', 'Mathematics', 5,
        r'C:\learnova_app\textbooks\F5 Maths.pdf', 11,
        'F5 Mathematics KSSM Textbook',
    ),
    (
        'MY-AddMaths', 'AddMaths', 5,
        r'C:\learnova_app\textbooks\F5 Add Maths.pdf', 11,
        'F5 Additional Mathematics KSSM Textbook',
    ),
    (
        'MY-Biology', 'Biology', 4,
        r'C:\learnova_app\textbooks\F4 Biology.pdf', 11,
        'F4 Biology KSSM Textbook',
    ),
    (
        'MY-Chemistry', 'Chemistry', 4,
        r'C:\learnova_app\textbooks\F4 Chemistry.pdf', 11,
        'F4 Chemistry KSSM Textbook',
    ),
    (
        'MY-Chemistry', 'Chemistry', 5,
        r'C:\learnova_app\textbooks\F5 Chemistry.pdf', 11,
        'F5 Chemistry KSSM Textbook',
    ),
    (
        'MY-BahasaMalaysia', 'BahasaMalaysia', 5,
        r'C:\learnova_app\textbooks\F5 Bahasa Melayu.pdf', 11,
        'F5 Bahasa Malaysia KSSM Textbook',
    ),
    (
        'MY-English', 'English', 5,
        r'C:\learnova_app\textbooks\F5 English.pdf', 6,
        'F5 English KSSM Textbook',
    ),
    (
        'MY-Sejarah', 'Sejarah', 5,
        r'C:\learnova_app\textbooks\F5 Sejarah 1.pdf', 6,
        'F5 Sejarah KSSM Textbook Vol 1',
    ),
    (
        'MY-Sejarah', 'Sejarah', 5,
        r'C:\learnova_app\textbooks\F5 Sejarah 2.pdf', 3,
        'F5 Sejarah KSSM Textbook Vol 2',
    ),
]


def run_job(args):
    subject_tag, subject_name, form, pdf_path, start_page_1idx, source_label = args

    # Redirect this process's stdout/stderr to a log file
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
            start_page=start_page_1idx - 1,  # convert to 0-indexed
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
    print(f'Launching {len(JOBS)} jobs in parallel...')
    for j in JOBS:
        print(f'  {j[0]} F{j[2]}: {os.path.basename(j[3])}')
    print()

    with multiprocessing.Pool(processes=len(JOBS)) as pool:
        results = pool.map(run_job, JOBS)

    print('\n=== ALL JOBS COMPLETE ===')
    total_saved = total_skipped = total_errors = 0
    for tag, form, pdf, saved, skipped, errors, err in results:
        status = f'{saved} saved, {skipped} skipped, {errors} errors'
        fatal = f' [FATAL: {err}]' if err else ''
        print(f'  {tag} F{form} ({pdf}): {status}{fatal}')
        total_saved   += saved
        total_skipped += skipped
        total_errors  += errors

    print(f'\nGRAND TOTAL: {total_saved} saved, {total_skipped} skipped, {total_errors} errors')
