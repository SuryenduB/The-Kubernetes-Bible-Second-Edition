"""Phase A2b: full sweep of the VÖBB OverDrive audiobook catalogue, handling both
counted subject listings and collection browse pages (no count -> paginate until exhausted)."""
import json, os, re, sys, urllib.parse, hashlib, threading
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tools_od import get, media_items, summarize, BASE

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, '.cache_sweep')
os.makedirs(CACHE, exist_ok=True)
_lock = threading.Lock()

def fetch(url):
    key = hashlib.sha1(url.encode()).hexdigest()
    p = os.path.join(CACHE, key + '.html')
    with _lock:
        if os.path.exists(p) and os.path.getsize(p) > 500:
            return open(p, encoding='utf-8', errors='replace').read()
    html = get(url)
    with _lock:
        open(p, 'w', encoding='utf-8').write(html)
    return html

def subject_ids():
    h = fetch(BASE + '/advanced-search')
    ids = [int(m.group(1)) for m in
           re.finditer(r'<option value=["\'](\d+)["\'] class="AdvancedSearch-select-option">', h)]
    return sorted(set(ids))

def url_for(subject, page):
    return BASE + '/search?' + urllib.parse.urlencode(
        {'sortBy': 'relevance', 'subject': subject, 'format': 'audiobook-overdrive', 'page': page})

def sweep_subject(subject, max_pages=200):
    items = {}
    page = 1
    while page <= max_pages:
        h = fetch(url_for(subject, page))
        m = re.search(r'Showing ([\d\-]+) of ([\d,]+) results', h)
        mi = media_items(h)
        new = 0
        for k, v in mi.items():
            if k not in items:
                items[k] = v
                new += 1
        if m:
            total = int(m.group(2).replace(',', ''))
            if page * 24 >= total:
                break
        else:
            if not mi or new == 0:
                break
        page += 1
    return subject, items, page

def main():
    subs = subject_ids()
    print("subjects:", len(subs), flush=True)
    corpus = {}
    done = 0
    with ThreadPoolExecutor(max_workers=6) as ex:
        for subject, items, pages in ex.map(sweep_subject, subs):
            done += 1
            corpus.update(items)
            if done % 25 == 0:
                print(f"  ...{done}/{len(subs)} subjects, corpus={len(corpus)}", flush=True)
    out = {k: summarize(v) for k, v in corpus.items()}
    json.dump(out, open(os.path.join(HERE, 'overdrive_audiobook_corpus.json'), 'w'), indent=1, ensure_ascii=False)
    en = sum(1 for v in out.values() if 'English' in (v.get('languages') or []))
    print("corpus records:", len(out), "english:", en)

if __name__ == '__main__':
    main()
