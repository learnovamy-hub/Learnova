import multiprocessing, os, sys
os.environ.setdefault('DEEPSEEK_API_KEY', 'sk-116af79bcdc740dc914cf072fd735cb5')
os.environ.setdefault('PYTHONIOENCODING', 'utf-8')
from process_subject import process_textbook

JOBS = [
    (
        'MY-Biology', 'Biology', 4,
        r'C:\Users\Yong\Downloads\Learnova Malaysia\Form 4\KSSM_2019_DP_DLP_BIOLOGY_FORM_4_PART_1.pdf',
        8, 'F4 Biology KSSM Textbook Part 1 (DLP)', 'SPM', 'MY',
        r'C:\Learnova\MY-Biology_F4_P1_results.json',
        'Bio_F4_P1',
    ),
    (
        'MY-Biology', 'Biology', 4,
        r'C:\Users\Yong\Downloads\Learnova Malaysia\Form 4\KSSM_2019_DP_DLP_BIOLOGY_FORM_4_PART_2.pdf',
        8, 'F4 Biology KSSM Textbook Part 2 (DLP)', 'SPM', 'MY',
        r'C:\Learnova\MY-Biology_F4_P2_results.json',
        'Bio_F4_P2',
    ),
]

def run_job(args):
    subject_tag, subject_name, form, pdf_path, start_1idx, source_label, level, country, backup_path, log_name = args
    log_path = r'C:\Learnova\logs\%s.log' % log_name
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
        return (log_name, saved, skipped, errors, None)
    except Exception as e:
        print('FATAL: %s' % e)
        sys.stdout.flush()
        return (log_name, 0, 0, 0, str(e))
    finally:
        sys.stdout.close()

if __name__ == '__main__':
    print('Launching F4 Biology Part 1 + Part 2 in parallel...')
    for j in JOBS:
        print('  %s: %s (%d start page)' % (j[8], os.path.basename(j[3]), j[4]))
    print()
    with multiprocessing.Pool(processes=2) as pool:
        results = pool.map(run_job, JOBS)
    print('\n=== F4 BIOLOGY COMPLETE ===')
    total_s = total_sk = total_e = 0
    for name, saved, skipped, errors, err in results:
        fatal = ' [FATAL: %s]' % err if err else ''
        print('  %s: %d saved, %d skipped, %d errors%s' % (name, saved, skipped, errors, fatal))
        total_s += saved; total_sk += skipped; total_e += errors
    print('\nGRAND TOTAL: %d saved, %d skipped, %d errors' % (total_s, total_sk, total_e))
