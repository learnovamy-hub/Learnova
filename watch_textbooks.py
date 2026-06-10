"""
TASK 2 — Watches C:\learnova_app\textbooks\ for new SPM PDFs.
When a known missing file appears, auto-processes it with the correct MY- tag.
Polls every 60 seconds. Tracks processed files to avoid re-processing.
"""

import os, sys, time, json, multiprocessing
os.environ.setdefault('DEEPSEEK_API_KEY', 'sk-116af79bcdc740dc914cf072fd735cb5')
os.environ.setdefault('PYTHONIOENCODING', 'utf-8')

WATCH_DIR  = r'C:\learnova_app\textbooks'
STATE_FILE = r'C:\Learnova\watcher_state.json'
POLL_SECS  = 60

# filename fragment → (subject_tag, subject_name, form, start_page_1idx, source_label)
WATCH_MAP = {
    'f4 add maths':        ('MY-AddMaths',        'AddMaths',        4, 11, 'F4 Additional Mathematics KSSM Textbook'),
    'matematik_tambahan_tingkatan_4': ('MY-AddMaths', 'AddMaths',    4, 11, 'F4 Additional Mathematics KSSM Textbook'),
    'dlp additional mathematics form 4': ('MY-AddMaths','AddMaths',  4, 11, 'F4 Additional Mathematics KSSM Textbook (DLP)'),
    'f4 bahasa melayu':    ('MY-BahasaMalaysia',  'BahasaMalaysia',  4,  8, 'F4 Bahasa Malaysia KSSM Textbook'),
    'f4 bahasa malaysia':  ('MY-BahasaMalaysia',  'BahasaMalaysia',  4,  8, 'F4 Bahasa Malaysia KSSM Textbook'),
    'f4 english':          ('MY-English',          'English',         4,  4, 'F4 English KSSM Textbook'),
    'f4 sejarah':          ('MY-Sejarah',          'Sejarah',         4, 11, 'F4 Sejarah KSSM Textbook'),
    'f5 biology':          ('MY-Biology',          'Biology',         5, 11, 'F5 Biology KSSM Textbook'),
    'biology form 5':      ('MY-Biology',          'Biology',         5, 11, 'F5 Biology KSSM Textbook'),
    'my-f5 biology':       ('MY-Biology',          'Biology',         5, 11, 'F5 Biology KSSM Textbook'),
}


def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, 'r') as f:
            return json.load(f)
    return {'processed': []}


def save_state(state):
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


def match_pdf(filename):
    lower = filename.lower().replace('.pdf', '')
    for key, config in WATCH_MAP.items():
        if key in lower:
            return config
    return None


def process_in_subprocess(args):
    from process_subject import process_textbook
    subject_tag, subject_name, form, pdf_path, start_1idx, source_label = args
    safe = f"WATCHER_{subject_tag.replace('MY-','')}_{os.path.basename(pdf_path)[:20].replace(' ','_')}"
    log_path = rf'C:\Learnova\logs\{safe}.log'
    sys.stdout = open(log_path, 'w', encoding='utf-8', buffering=1)
    sys.stderr = sys.stdout
    try:
        saved, skipped, errors = process_textbook(
            pdf_path=pdf_path, subject_tag=subject_tag, subject_name=subject_name,
            form=form, source_label=source_label, start_page=start_1idx - 1, end_page=None)
        msg = f'DONE: {saved} saved, {skipped} skipped, {errors} errors'
        print(msg); sys.stdout.flush()
        return (subject_tag, saved, skipped, errors, None)
    except Exception as e:
        print(f'FATAL: {e}'); sys.stdout.flush()
        return (subject_tag, 0, 0, 0, str(e))
    finally:
        sys.stdout.close()


def main():
    print(f'Watcher started. Polling {WATCH_DIR} every {POLL_SECS}s...')
    print('Watching for: ' + ', '.join(WATCH_MAP.keys()))
    sys.stdout.flush()

    state = load_state()

    while True:
        try:
            if not os.path.isdir(WATCH_DIR):
                time.sleep(POLL_SECS)
                continue

            for fname in os.listdir(WATCH_DIR):
                if not fname.lower().endswith('.pdf'):
                    continue
                fpath = os.path.join(WATCH_DIR, fname)
                if fpath in state['processed']:
                    continue

                config = match_pdf(fname)
                if config is None:
                    continue

                subject_tag, subject_name, form, start_1idx, source_label = config
                print(f'\n[WATCHER] New file detected: {fname}')
                print(f'[WATCHER] Processing as {subject_tag} F{form}...')
                sys.stdout.flush()

                state['processed'].append(fpath)
                save_state(state)

                job_args = (subject_tag, subject_name, form, fpath, start_1idx, source_label)
                with multiprocessing.Pool(1) as pool:
                    results = pool.map(process_in_subprocess, [job_args])
                tag, saved, skipped, errors, err = results[0]

                if err:
                    print(f'[WATCHER] FATAL for {tag}: {err}')
                else:
                    print(f'[WATCHER] COMPLETE {tag} F{form}: {saved} saved, {skipped} skipped, {errors} errors')
                sys.stdout.flush()

        except Exception as e:
            print(f'[WATCHER] Loop error: {e}')
            sys.stdout.flush()

        time.sleep(POLL_SECS)


if __name__ == '__main__':
    main()
