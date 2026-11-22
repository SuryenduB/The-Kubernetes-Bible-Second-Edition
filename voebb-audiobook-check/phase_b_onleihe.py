"""Phase B: VÖBB Onleihe collection check (server-rendered POST search, same form the site posts)."""
import json, os, re, sys, subprocess, hashlib, threading
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
BOOKS = json.load(open(os.path.join(HERE, 'books.json')))
SEARCH = 'https://voebb.onleihe.de/berlin/frontend/search,0-0-0-0-0-0-0-0-0-0-0.html'
UA = ('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36')
CACHE = os.path.join(HERE, '.cache_onleihe')
os.makedirs(CACHE, exist_ok=True)
_lock = threading.Lock()

def post(url, data):
    key = hashlib.sha1((url + repr(sorted(data.items()))).encode()).hexdigest()
    p = os.path.join(CACHE, key + '.html')
    with _lock:
        if os.path.exists(p) and os.path.getsize(p) > 200:
            return open(p, encoding='utf-8', errors='replace').read()
    args = ['curl', '-sSL', '--max-time', '45', '-A', UA, '-X', 'POST', url]
    for k, v in data.items():
        args += ['--data-urlencode', f'{k}={v}']
    html = subprocess.run(args, capture_output=True).stdout.decode('utf-8', 'replace')
    with _lock:
        open(p, 'w', encoding='utf-8').write(html)
    return html

def hit_count(html):
    m = re.search(r'ergab\s+(keine\s+Titeltreffer|([\d.]+)\s+Titeltreffer)', html)
    if not m:
        return None
    if m.group(1).startswith('keine'):
        return 0
    try:
        return int(float(m.group(2).replace('.', '')))
    except Exception:
        return None

def cards(html):
    parts = re.split(r"test-id='mediaCard'", html)
    out = []
    for part in parts[1:]:
        def grab(tid):
            m = re.search(r"test-id='" + tid + r"'[^>]*>(.*?)</", part, re.S | re.I)
            return re.sub(r'<[^>]+>', '', m.group(1)).strip() if m else ''
        m = re.search(r"href=\"(mediaInfo[^\"]+)\"[^>]*test-id='mediaInfoLink'", part, re.I)
        if not m:
            m = re.search(r"test-id='mediaInfoLink'[^>]*href=\"([^\"]+)\"", part, re.I)
        out.append({'title': grab('cardTitle'), 'author': grab('cardAuthor'),
                    'subtitle': grab('cardSubTitle'), 'availability': grab('cardAvailability'),
                    'media_types': sorted(set(re.findall(r'test-id="(ic_[a-z_]+)"', part, re.I))),
                    'detail': ('https://voebb.onleihe.de/berlin/frontend/' + m.group(1)) if m else ''})
    return out

def search(query, elements=100):
    html = post(SEARCH, {'pText': query, 'cmdId': '703', 'sK': '1000', 'elementsPerPage': str(elements)})
    return {'query': query, 'total': hit_count(html), 'cards': cards(html), 'html': html}

def norm(s):
    import unicodedata
    s = unicodedata.normalize('NFKD', s or '')
    s = ''.join(c for c in s if not unicodedata.combining(c)).lower()
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9]+', ' ', s)).strip()

def cw(s):
    STOP = set('the a an of and or in on to with for from by at as is it its der die das ein eine'.split())
    return [w for w in norm(s).split() if w not in STOP]

def run_book(b):
    queries = [b['title']] + b.get('alt_titles', [])
    if b['author']:
        queries.append(f"{b['title']} {b['author'].split()[-1]}")
    res = {'id': b['id'], 'title': b['title'], 'author': b['author'], 'searches': [], 'hits': []}
    seen = set()
    for q in queries:
        r = search(q)
        res['searches'].append({'query': q, 'total': r['total'], 'cards': len(r['cards'])})
        for c in r['cards']:
            k = norm(c['title'])
            if k in seen:
                continue
            seen.add(k)
            tw = set(cw(b['title']))
            rw = set(cw(c['title'] + ' ' + c['subtitle']))
            c['match'] = round(len(tw & rw) / len(tw), 2) if tw else 0
            c['query'] = q
            res['hits'].append(c)
    res['title_hits'] = [c for c in res['hits'] if c['match'] >= 0.6]
    res['audio_hits'] = [c for c in res['title_hits'] if 'ic_eaudio' in c['media_types']]
    return res

def main():
    out = []
    with ThreadPoolExecutor(max_workers=5) as ex:
        for i, r in enumerate(ex.map(run_book, BOOKS)):
            out.append(r)
            print(f"[{r['id']:02d}] total={r['searches'][0]['total']} title_hits={len(r['title_hits'])} "
                  f"audio_hits={len(r['audio_hits'])}  {r['title'][:40]!r}", flush=True)
            json.dump(out, open(os.path.join(HERE, 'phase_b_onleihe.json'), 'w'), indent=1, ensure_ascii=False)

if __name__ == '__main__':
    main()
