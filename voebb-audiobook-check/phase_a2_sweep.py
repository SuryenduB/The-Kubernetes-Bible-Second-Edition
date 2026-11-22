"""Phase A2: exhaustive sweep of the whole VÖBB OverDrive audiobook catalogue (all subjects,
all pages) so title matching does not depend on the fuzzy keyword search."""
import json, os, re, sys, urllib.parse, hashlib, threading, time
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
    ids = []
    for m in re.finditer(r'<option value=["\'](\d+)["\'] class="AdvancedSearch-select-option">', h):
        ids.append(int(m.group(1)))
    return sorted(set(ids))

def url_for(subject, page):
    return BASE + '/search?' + urllib.parse.urlencode(
        {'sortBy': 'relevance', 'subject': subject, 'format': 'audiobook-overdrive', 'page': page})

def sweep_subject(subject):
    items = {}
    urls = []
    page = 1
    while True:
        u = url_for(subject, page)
        h = fetch(u)
        m = re.search(r'Showing ([\d\-]+) of ([\d,]+) results', h)
        urls.append(u)
        mi = media_items(h)
        if mi:
            items.update(mi)
        if not m:
            break
        total = int(m.group(2).replace(',', ''))
        if page * 24 >= total or page >= 80:
            break
        page += 1
    return subject, items, urls

def main():
    subs = subject_ids()
    print("subjects:", len(subs), flush=True)
    corpus = {}
    per_subject = {}
    done = 0
    with ThreadPoolExecutor(max_workers=6) as ex:
        for subject, items, urls in ex.map(sweep_subject, subs):
            done += 1
            per_subject[subject] = {'items': len(items), 'pages': len(urls)}
            corpus.update(items)
            if done % 25 == 0:
                print(f"  ...{done}/{len(subs)} subjects, corpus={len(corpus)}", flush=True)
    out = {k: summarize(v) for k, v in corpus.items()}
    json.dump(out, open(os.path.join(HERE, 'overdrive_audiobook_corpus.json'), 'w'), indent=1, ensure_ascii=False)
    json.dump(per_subject, open(os.path.join(HERE, 'sweep_stats.json'), 'w'), indent=1)
    print("corpus records:", len(out))
    en = sum(1 for v in out.values() if 'English' in (v.get('languages') or []))
    print("english:", en)

if __name__ == '__main__':
    main()
