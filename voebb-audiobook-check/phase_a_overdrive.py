"""Phase A: VÖBB OverDrive / Libby — English digital audiobook check for all 64 books.

Uses the platform's own Advanced-Search parameters (query=Title, creator=Author,
language, mediaType) and the retry ladder from the protocol.
"""
import json, os, re, sys, time, unicodedata, urllib.parse, hashlib, threading
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tools_od import get, media_items, summarize, BASE

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, '.cache')
os.makedirs(CACHE, exist_ok=True)
_lock = threading.Lock()

BOOKS = json.load(open(os.path.join(HERE, 'books.json')))

# ---------- helpers ----------
def norm(s):
    s = unicodedata.normalize('NFKD', s or '')
    s = ''.join(c for c in s if not unicodedata.combining(c)).lower()
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9]+', ' ', s)).strip()

STOP = set('the a an of and or in on to with for from by at as is it its'.split())

def content_words(s):
    return [w for w in norm(s).split() if w not in STOP]

def surname(author):
    a = re.sub(r'^(Mr|Ms|Mrs|Dr|Prof)\.?\s+', '', author.strip())
    a = re.sub(r'\s+', ' ', a)
    parts = [p for p in a.split(' ') if p]
    if not parts:
        return ''
    last = parts[-1]
    if ',' in last:
        last = last.split(',')[0]
    return last.strip()

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

def adv(query=None, creator=None, language=None, media_type=None, page=None):
    p = {}
    if query: p['query'] = query
    if creator: p['creator'] = creator
    if language: p['language'] = language
    if media_type: p['mediaType'] = media_type
    if page and page > 1: p['page'] = page
    url = BASE + '/search?' + urllib.parse.urlencode(p)
    h = fetch(url)
    m = re.search(r'Showing ([\d\-]+) of ([\d,]+) results', h)
    return {'url': url,
            'total': int(m.group(2).replace(',', '')) if m else 0,
            'shown': m.group(1) if m else '',
            'items': media_items(h)}

def title_score(expected, rec):
    """How well does the record title match the requested title (ignoring a subtitle)."""
    ew = content_words(expected)
    if not ew:
        return 0.0, 0
    rec_words = set(content_words((rec.get('title') or '') + ' ' + (rec.get('subtitle') or '')))
    rec_main = set(content_words(rec.get('title') or ''))
    best = 0.0
    for k in range(1, len(ew) + 1):
        core = ew[:k]
        r = len(set(core) & rec_main) / len(set(core))
        best = max(best, r)
    # also allow the record title to be a superset of the requested words
    r2 = len(set(ew) & rec_words) / len(set(ew))
    return max(best, r2), len(ew)

def author_hit(author, rec):
    creators = ' '.join(rec.get('creators') or [])
    n = norm(creators)
    sn = norm(surname(author))
    return bool(sn) and sn in n

# ---------- per book ----------
def run_book(b):
    title, author = b['title'], b['author']
    res = {'id': b['id'], 'title': title, 'author': author, 'notes_in': b.get('notes', ''),
           'alt_titles': b.get('alt_titles', []), 'search_log': [],
           'en_audiobook_candidates': [], 'other_lang_candidates': [], 'ebook_candidates': []}
    seen = {}

    def collect(**kw):
        r = adv(**kw)
        res['search_log'].append({'url': r['url'], 'total': r['total'], 'shown': r['shown'],
                                  'kind': kw})
        out = []
        for it in r['items'].values():
            s = summarize(it)
            if s['id'] in seen:
                continue
            seen[s['id']] = True
            s['title_score'] = round(title_score(title, s)[0], 3)
            s['author_hit'] = author_hit(author, s)
            s['record_url'] = f"{BASE}/media/{s['id']}"
            out.append(s)
        return out

    # 1) exact advanced search: Title + Author + English + audiobook
    cands = collect(query=title, creator=author, language='en', media_type='audiobook')
    res['en_audiobook_candidates'] += [s for s in cands
                                        if s['title_score'] >= 0.8 and (s['author_hit'] or not s['creators'])]
    # 2) title only, English + audiobook
    cands = collect(query=title, language='en', media_type='audiobook')
    res['en_audiobook_candidates'] += [s for s in cands
                                        if s['title_score'] >= 0.8 and (s['author_hit'] or not s['creators'])]
    # 3) author only -> inspect the author's audiobooks
    cands = collect(creator=author, language='en', media_type='audiobook')
    res['en_audiobook_candidates'] += [s for s in cands
                                        if s['title_score'] >= 0.6 and s['author_hit']]
    # 4) alternative titles
    for alt in res['alt_titles']:
        cands = collect(query=alt, language='en', media_type='audiobook')
        res['en_audiobook_candidates'] += [s for s in cands
                                            if s['title_score'] >= 0.8 and (s['author_hit'] or not s['creators'])]
    # 5) shortened title (no subtitle/punctuation) + author surname
    short = ' '.join(content_words(title)[:5])
    cands = collect(query=f"{short} {surname(author)}", language='en', media_type='audiobook')
    res['en_audiobook_candidates'] += [s for s in cands
                                        if s['title_score'] >= 0.8 and s['author_hit']]
    # 6) without the language filter -> other-language audiobooks recorded separately
    for q in [title, f"{short} {surname(author)}"]:
        cands = collect(query=q, media_type='audiobook')
        res['other_lang_candidates'] += [s for s in cands
                                         if s['title_score'] >= 0.8 and (s['author_hit'] or not s['creators'])]
    # 7) no format filter -> does VÖBB hold the book as ebook?
    cands = collect(query=title, creator=author, language='en')
    res['ebook_candidates'] += [s for s in cands if s['title_score'] >= 0.8 and s['author_hit']]
    return res

def main():
    out = []
    with ThreadPoolExecutor(max_workers=6) as ex:
        for i, r in enumerate(ex.map(run_book, BOOKS)):
            out.append(r)
            print(f"[{r['id']:02d}] en_cand={len(r['en_audiobook_candidates'])} "
                  f"other={len(r['other_lang_candidates'])} ebook={len(r['ebook_candidates'])}  {r['title'][:44]!r}",
                  flush=True)
            json.dump(out, open(os.path.join(HERE, 'phase_a_overdrive.json'), 'w'), indent=1, ensure_ascii=False)

if __name__ == '__main__':
    main()
