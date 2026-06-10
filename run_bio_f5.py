import multiprocessing, os, sys
os.environ.setdefault('DEEPSEEK_API_KEY', 'sk-116af79bcdc740dc914cf072fd735cb5')
os.environ.setdefault('PYTHONIOENCODING', 'utf-8')
from process_subject import process_textbook

JOBS = [(
    'MY-Biology', 'Biology', 5,
    r'C:\Users\Yong\Downloads\biology form 5.pdf', 11,
    'F5 Biology KSSM Textbook',
)]

def run_job(args):
    subject_tag, subject_name, form, pdf_path, start_1idx, source = args
    log = rf'C:\Learnova\logs\Biology_F5_biology_form_5.log'
    sys.stdout = open(log, 'w', encoding='utf-8', buffering=1)
    sys.stderr = sys.stdout
    try:
        saved, skipped, errors = process_textbook(
            pdf_path=pdf_path, subject_tag=subject_tag, subject_name=subject_name,
            form=form, source_label=source, start_page=start_1idx-1, end_page=None)
        print(f'DONE: {saved} saved, {skipped} skipped, {errors} errors')
        sys.stdout.flush()
        return (subject_tag, form, saved, skipped, errors, None)
    except Exception as e:
        print(f'FATAL: {e}'); sys.stdout.flush()
        return (subject_tag, form, 0, 0, 0, str(e))
    finally:
        sys.stdout.close()

if __name__ == '__main__':
    print('Launching MY-Biology F5...')
    with multiprocessing.Pool(1) as pool:
        results = pool.map(run_job, JOBS)
    tag, form, saved, skipped, errors, err = results[0]
    print(f'\nDONE: {tag} F{form}: {saved} saved, {skipped} skipped, {errors} errors')
    if err: print(f'FATAL: {err}')
