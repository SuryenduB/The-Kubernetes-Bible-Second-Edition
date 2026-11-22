"""Drive the VÖBB physical catalogue (aDISWeb) via the browse CLI; record hits + material format."""
import json, re, subprocess, os, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from batch2 import build_queries

HERE = os.path.dirname(os.path.abspath(__file__))
BOOKS = json.load(open(os.path.join(HERE, 'tech_books.json'))) + [
    {"raw": "AI for Everyday IT Accelerate workplace productivity (Chrissy LeMaire, Brandon Abshire)"}]

def run(cmd):
    return subprocess.run(cmd, capture_output=True).stdout.decode('utf-8', 'replace')

def browse(*args):
    return run(['browse', *args])

def body_text():
    raw = browse('get', 'text', 'body')
    try:
        return json.loads(raw[raw.find('{'):])['text']
    except Exception:
        return raw

def search_one(query):
    for attempt in range(3):
        browse('fill', '#Autosuggest', query)
        browse('press', 'Enter')
        time.sleep(3.2)
        t = body_text()
        if 'Interner Fehler' not in t and len(t) > 2000:
            break
        # session broke -> reset
        browse('open', 'https://www.voebb.de/')
        time.sleep(3)
    res = {'query': query}
    m = re.search(r'Gesucht wurde mit "([^"]*)",\s*Treffer:\s*(\d+)', t)
    if m:
        res['hits'] = int(m.group(2))
        res['searched'] = m.group(1)
    elif 'Kein Treffer im Suchbereich "Bibliotheksbestand"' in t:
        res['hits'] = 0
        res['searched'] = re.search(r'"Freie Suche = ([^"]*)"', t).group(1) if re.search(r'"Freie Suche = ([^"]*)"', t) else query
        res['ferleihe_hits'] = 'Es gibt Treffer im Suchbereich "Fernleihe (deutschlandweit)"' in t
    elif 'war erfolglos' in t:
        res['hits'] = 0
        m2 = re.search(r'Ihre Suche mit "([^"]*)"', t)
        res['searched'] = m2.group(1) if m2 else query
    else:
        res['hits'] = None
    entries = re.findall(r'(?m)^(\d{1,3})(.+)$', t)
    out = []
    for num, title in entries:
        title = re.sub(r'\s+', ' ', title).strip()
        if not title or re.search(r'(Sie müssen angemeldet|Trefferliste filtern|Titel exportieren|facebook|'
                                  r'Suchen Sie nach|Weitere Treffer|Kein Treffer)', title, re.I):
            continue
        out.append(title)
    res['entries'] = out[:10]
    res['audio_entries'] = [e for e in out if re.search(r'\[Ton\]|\[CD\]|Hörbuch|Audiobook|\[Audio\]|\bMC\b', e, re.I)]
    return res

def main():
    res = []
    for i, b in enumerate(BOOKS):
        title, author, queries = build_queries(b['raw'])
        r = search_one(title)
        alt = None
        if not r.get('hits'):
            alt = search_one(queries[1] if len(queries) > 1 else title)
        rec = {'raw': b['raw'], 'title_query': title, 'author_guess': author,
               'primary': r, 'alt': alt}
        res.append(rec)
        audio = r.get('audio_entries', []) + (alt or {}).get('audio_entries', [])
        print(f"[{i+1}/{len(BOOKS)}] hits={r.get('hits')} alt={None if not alt else alt.get('hits')} "
              f"audio={len(audio)}  {b['raw'][:52]!r}", flush=True)
        json.dump(res, open(os.path.join(HERE, 'adis_results.json'), 'w'), indent=1, ensure_ascii=False)

if __name__ == '__main__':
    main()
