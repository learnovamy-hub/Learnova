import fitz
files = {
    'MY-F5 Biology': r'C:\Users\Yong\Downloads\Learnova Malaysia\Form 5\MY-F5 Biology.pdf',
    'AL-Biology':    r'C:\Users\Yong\Downloads\Learnova A Levels\AL-BIOLOGY.pdf',
}
for name, path in files.items():
    doc = fitz.open(path)
    pages = len(doc)
    samples = []
    for i in [10, 15, 20]:
        if i < pages:
            t = doc[i].get_text(sort=True).strip()
            samples.append('p%d: %dw' % (i+1, len(t.split())))
    doc.close()
    print('%s: %d pages | %s' % (name, pages, ' | '.join(samples)))
