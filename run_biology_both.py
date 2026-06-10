import multiprocessing, os, sys
os.environ.setdefault('DEEPSEEK_API_KEY', 'sk-116af79bcdc740dc914cf072fd735cb5')
os.environ.setdefault('PYTHONIOENCODING', 'utf-8')
from process_subject import process_textbook

JOBS = [
    (
        'MY-Biology', 'Biology', 5,
        r'C:\Users\Yong\Downloads\Learnova Malaysia\Form 5\MY-F5 Biology.pdf',
        11, 'F5 Biology KSSM Textbook', 'SPM', 'MY',
    ),
    (
        'AL-Biology', 'AL-Biology', 'AS-A2',
        r'C:\Users\Yong\Downloads\Learnova A Levels\AL-BIOLOGY.pdf',
        10, 'Cambridge A Level Biology Coursebook', 'A-Level', 'MY',
    ),
]

def run_job(args):
    subject_tag, subject_name, form, pdf_path, start_1idx, source_label, level, country = args
    safe = '%s_%s' % (subject_tag.replace('-','_'), os.path.basename(pdf_path)[:25].replace(' ','_'))
    log_path = r'C:\Learnova\logs\%s.log' % safe
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
            country=country,
        )
        print('DONE: %d saved, %d skipped, %d errors' % (saved, skipped, errors))
        sys.stdout.flush()
        return (subject_tag, form, saved, skipped, errors, None)
    except Exception as e:
        print('FATAL: %s' % e)
        sys.stdout.flush()
        return (subject_tag, form, 0, 0, 0, str(e))
    finally:
        sys.stdout.close()

if __name__ == '__main__':
    print('Launching 2 Biology jobs in parallel...')
    for j in JOBS:
        print('  %s (Form %s): %s' % (j[0], j[2], os.path.basename(j[3])))
    print()
    with multiprocessing.Pool(processes=2) as pool:
        results = pool.map(run_job, JOBS)
    print('\n=== BIOLOGY JOBS COMPLETE ===')
    total_s = total_sk = total_e = 0
    for tag, form, saved, skipped, errors, err in results:
        fatal = ' [FATAL: %s]' % err if err else ''
        print('  %s (Form %s): %d saved, %d skipped, %d errors%s' % (tag, form, saved, skipped, errors, fatal))
        total_s += saved; total_sk += skipped; total_e += errors
    print('\nGRAND TOTAL: %d saved, %d skipped, %d errors' % (total_s, total_sk, total_e))
