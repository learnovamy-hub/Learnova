"""
A-Level textbook processing — Cambridge AS & A Level coursebooks.
Runs all subjects in parallel via multiprocessing.
"""

import multiprocessing, os, sys
os.environ.setdefault('DEEPSEEK_API_KEY', 'sk-116af79bcdc740dc914cf072fd735cb5')
os.environ.setdefault('PYTHONIOENCODING', 'utf-8')
from process_subject import process_textbook

BASE = r'C:\Users\Yong\Downloads\Learnova A Levels\text books'

JOBS = [
    # AL-Mathematics: 3 core Cambridge coursebooks
    (
        'AL-Mathematics', 'AL-Mathematics', 'AS-A2',
        os.path.join(BASE, r'A Levels Maths\Math\Cambridge International AS and A Level Mathematics Pure Mathematics 1 Coursebook - Cambridge University Press (2018).pdf'),
        8, 'Cambridge A Level Mathematics Pure Mathematics 1', 'A-Level',
    ),
    (
        'AL-Mathematics', 'AL-Mathematics', 'AS-A2',
        os.path.join(BASE, r'A Levels Maths\Math\Cambridge International AS and A Level Mathematics Pure Mathematics 2 _ 3 Coursebook - Cambridge University Press (2018).pdf'),
        8, 'Cambridge A Level Mathematics Pure Mathematics 2 & 3', 'A-Level',
    ),
    (
        'AL-Mathematics', 'AL-Mathematics', 'AS-A2',
        os.path.join(BASE, r'A Levels Maths\Math\Cambridge International AS and A Level Mathematics Probability _ Statistics 1 Coursebook - Cambridge University Press (2018).pdf'),
        8, 'Cambridge A Level Mathematics Probability & Statistics 1', 'A-Level',
    ),
    # AL-FurtherMaths
    (
        'AL-FurtherMaths', 'AL-FurtherMaths', 'AS-A2',
        os.path.join(BASE, r'A Levels Further Mathematics 1\Cambridge AS & A Level Further Mathematics Full.pdf'),
        10, 'Cambridge A Level Further Mathematics Full', 'A-Level',
    ),
    # AL-Physics
    (
        'AL-Physics', 'AL-Physics', 'AS-A2',
        os.path.join(BASE, r'A Levels Physics\Physics\Cambridge International AS _ A Level Physics Coursebook with Digital Access (2 Years) - Cambridge University Press (2021).pdf'),
        10, 'Cambridge A Level Physics Coursebook', 'A-Level',
    ),
    # AL-Chemistry
    (
        'AL-Chemistry', 'AL-Chemistry', 'AS-A2',
        os.path.join(BASE, r'A Levels Chemistry\Chemistry\Cambridge International AS _ A Level Chemistry Coursebook with Digital Access (2 Years) - Cambridge University Press (2020).pdf'),
        10, 'Cambridge A Level Chemistry Coursebook', 'A-Level',
    ),
]


def run_job(args):
    subject_tag, subject_name, form, pdf_path, start_1idx, source_label, level = args
    safe = f"{subject_tag.replace('AL-','AL_')}_{os.path.basename(pdf_path)[:30].replace(' ','_')}"
    log_path = rf'C:\Learnova\logs\{safe}.log'
    sys.stdout = open(log_path, 'w', encoding='utf-8', buffering=1)
    sys.stderr = sys.stdout
    try:
        saved, skipped, errors = process_textbook(
            pdf_path=pdf_path,
            subject_tag=subject_tag,
            subject_name=subject_name,
            form=form,
            source_label=source_label,
            start_page=start_1idx - 1,
            end_page=None,
            level=level,
            country='MY',
        )
        print(f'DONE: {saved} saved, {skipped} skipped, {errors} errors')
        sys.stdout.flush()
        return (subject_tag, os.path.basename(pdf_path), saved, skipped, errors, None)
    except Exception as e:
        print(f'FATAL: {e}'); sys.stdout.flush()
        return (subject_tag, os.path.basename(pdf_path), 0, 0, 0, str(e))
    finally:
        sys.stdout.close()


if __name__ == '__main__':
    print(f'Launching {len(JOBS)} A-Level jobs in parallel...')
    for j in JOBS:
        print(f'  {j[0]}: {os.path.basename(j[3])}')
    print()

    with multiprocessing.Pool(processes=len(JOBS)) as pool:
        results = pool.map(run_job, JOBS)

    print('\n=== ALL A-LEVEL JOBS COMPLETE ===')
    total_s = total_sk = total_e = 0
    for tag, pdf, saved, skipped, errors, err in results:
        fatal = f' [FATAL: {err}]' if err else ''
        print(f'  {tag} ({pdf[:50]}): {saved} saved, {skipped} skipped, {errors} errors{fatal}')
        total_s += saved; total_sk += skipped; total_e += errors
    print(f'\nGRAND TOTAL: {total_s} saved, {total_sk} skipped, {total_e} errors')
