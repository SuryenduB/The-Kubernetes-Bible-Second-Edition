"""Phase D: open the actual records in a real browser and read the displayed
language / format / borrowing status (never clicking Borrow or Place a hold)."""
import json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
UA = None

def browse(*args):
    p = subprocess.run(['browse', *args], capture_output=True)
    return p.stdout.decode('utf-8', 'replace')

def body_text():
    raw = browse('get', 'text', 'body')
    try:
        return json.loads(raw[raw.find('{'):])['text']
    except Exception:
        return raw

def open_url(url, settle=3.0):
    browse('open', url, '--local')
    time.sleep(settle)
    t = body_text()
    if 'Interner Fehler' in t and 'voebb' in url:
        browse('open', 'https://www.voebb.de/')
        time.sleep(2.5)
        browse('open', url, '--local')
        time.sleep(settle)
        t = body_text()
    return t

def lines_of(t):
    out = []
    for l in t.split('\n'):
        l = re.sub(r'\s+', ' ', l).strip()
        if l:
            out.append(l)
    return out

def grab(t, pattern, limit=6):
    res = []
    for l in lines_of(t):
        if re.search(pattern, l, re.I) and len(l) < 160 and l not in res:
            res.append(l)
            if len(res) >= limit:
                break
    return res

def parse_overdrive(t):
    d = {}
    d['copies'] = grab(t, r'copies available')
    d['wait'] = grab(t, r'^\s*Wait time')
    d['actions'] = [l for l in grab(t, r'^(Place a hold|Borrow|Add to wish list|Listen to a sample|Add to history)$', 8)]
    d['edition'] = grab(t, r'Edition:')
    d['publisher'] = grab(t, r'^\s*(Books on Tape|Penguin|Random House|Macmillan|HarperCollins|Blackstone|Faber|Simon & Schuster|Clipper|Naxos|Headline|Hodder|Audiobooks|Audio|Tantor|HighBridge|Knopf|Pan Macmillan|Canongate)', 3)
    d['duration'] = grab(t, r'Duration:')
    d['isbn'] = grab(t, r'ISBN:')
    d['language'] = grab(t, r'^(English|German|French|Spanish|Italian)$', 4)
    d['format_line'] = grab(t, r'^(Audiobook|eBook|ebook)$', 3)
    d['narrator_block'] = grab(t, r'^(Narrator|Author|Sprecher)$', 4)
    d['release'] = grab(t, r'^\d{2}\.\d{2}\.\d{4}$|^(January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}$', 3)
    d['narrators'] = grab(t, r'^(Theodore O\'Brien|Scott Brick|Campbell Scott|Grover Gardner|Jeremy Irons|Maggie Gyllenhaal|Kristoffer Tabori|Simon Prebble|Ron Silver|Alice Walker|Carole Boyd|Coleen Marlo|Tim Jerome|Richmond Hoxie|Kirsten Potter|David Linski|Dan Stevens|Simon Slater|Pippa Bennett-Warner|Oliver Ford Davies|David Ledoux|Michael Pollan)$', 8)
    return d

def parse_onleihe(t):
    d = {}
    d['fields'] = grab(t, r'^(Titel Autor\*in|Autor\*in|Verlag|Format|Sprache|Dauer|ISBN|Serie|Art\.)', 24)
    d['status'] = grab(t, r'^(Verfügbar|Voraussichtlich verfügbar ab:|Ausgeliehen|Vormerker)', 4)
    d['actions'] = grab(t, r'^(Jetzt ausleihen|Vormerker setzen|Details)$', 5)
    return d

def main():
    targets = json.load(open(os.path.join(HERE, sys.argv[1])))
    out = []
    for t in targets:
        kind = t['kind']
        url = t['url']
        txt = open_url(url, t.get('settle', 3.0))
        rec = {'id': t.get('id'), 'kind': kind, 'url': url,
               'parsed': parse_overdrive(txt) if kind == 'overdrive' else parse_onleihe(txt)}
        out.append(rec)
        print(f"[{t.get('id')}] {kind} {url[-28:]} -> {rec['parsed'].get('copies') or rec['parsed'].get('status')}", flush=True)
        json.dump(out, open(os.path.join(HERE, sys.argv[2]), 'w'), indent=1, ensure_ascii=False)

if __name__ == '__main__':
    main()
