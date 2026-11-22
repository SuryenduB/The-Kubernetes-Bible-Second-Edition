"""Open every positive record in a real browser and read the displayed borrowing status.
Read-only: no Borrow / Place-a-hold button is ever clicked."""
import json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'browser_status.json')

def browse(*args):
    return subprocess.run(['browse', *args], capture_output=True).stdout.decode('utf-8', 'replace')

def body_text():
    raw = browse('get', 'text', 'body')
    try:
        return json.loads(raw[raw.find('{'):])['text']
    except Exception:
        return raw

def lines(t):
    return [re.sub(r'\s+', ' ', l).strip() for l in t.split('\n') if re.sub(r'\s+', ' ', l).strip()]

def read_page(url, settle=3.2):
    browse('open', url, '--local')
    time.sleep(settle)
    t = body_text()
    for _ in range(2):
        if 'copies available' in t or 'Jetzt ausleihen' in t or 'Vormerker' in t or 'Verfügbar' in t:
            break
        time.sleep(1.5)
        t = body_text()
    L = lines(t)
    disp = []
    for pat in (r'copies available', r'^Wait time', r'^Place a hold$', r'^Borrow$',
                r'^Jetzt ausleihen$', r'^Vormerker setzen$', r'^Verfügbar$',
                r'^Voraussichtlich verfügbar ab:', r'^Nicht verfügbar$'):
        for l in L:
            if re.search(pat, l, re.I):
                disp.append(l)
                break
    return {'display': '; '.join(dict.fromkeys(disp))}

def main():
    recs = json.load(open(os.path.join(HERE, 'evidence_records.json')))
    targets = []
    for b in recs:
        for r in b['records']:
            if r['source'].startswith('OverDrive'):
                targets.append({'key': 'od_' + r['url'].rsplit('/', 1)[-1], 'url': r['url'], 'book': b['book']})
            else:
                mid = re.search(r'mediaInfo,0-0-(\d+)-', r['url'])
                targets.append({'key': 'ol_' + (mid.group(1) if mid else r['url'][-10:]),
                                'url': r['url'], 'book': b['book']})
    out = []
    for t in targets:
        r = read_page(t['url'])
        r.update({'key': t['key'], 'url': t['url'], 'book': t['book']})
        out.append(r)
        print(f"[{t['book']:02d}] {t['key']:>16} {r['display'][:120]}", flush=True)
        json.dump(out, open(OUT, 'w'), indent=1, ensure_ascii=False)

if __name__ == '__main__':
    main()
