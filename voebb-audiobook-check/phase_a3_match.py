"""Phase A3: match the 64 requested books against the swept VÖBB OverDrive audiobook catalogue."""
import json, os, re, sys, unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from phase_a_overdrive import norm, content_words, surname

HERE = os.path.dirname(os.path.abspath(__file__))
corpus = json.load(open(os.path.join(HERE, 'overdrive_audiobook_corpus.json')))
BOOKS = json.load(open(os.path.join(HERE, 'books.json')))
PHASE_A = {x['id']: x for x in json.load(open(os.path.join(HERE, 'phase_a_overdrive.json')))}

# titles whose request contains a qualifier that a record may not repeat
PARTIAL_OK = {
    44: 'record covers only part of the requested collection',
    1: 'individual plays are partial matches only',
    39: 'must be volume 1',
}

def rec_words(rec):
    return set(content_words((rec.get('title') or '') + ' ' + (rec.get('subtitle') or '')))

def rec_main_words(rec):
    return set(content_words(rec.get('title') or ''))

def score(req_title, rec):
    ew = set(content_words(req_title))
    if not ew:
        return 0.0, 0.0
    main = len(ew & rec_main_words(rec)) / len(ew)
    full = len(ew & rec_words(rec)) / len(ew)
    return main, full

def authors_of(rec):
    return ' '.join(rec.get('creators') or [])

def match_book(b, titles):
    """titles: list of query titles to test (primary + alternatives)."""
    hits = []
    for it in corpus.values():
        langs = it.get('languages') or []
        if not it.get('formats'):
            continue
        is_audio = (it.get('type') or '').lower() == 'audiobook' or \
                   any('audiobook' in (f or '').lower() for f in it.get('formats') or [])
        if not is_audio:
            continue
        best = None
        for t in titles:
            main, full = score(t, it)
            s = max(main, full)
            if best is None or s > best[0]:
                best = (s, t, main, full)
        if not best:
            continue
        s, t, main, full = best
        an = norm(authors_of(it))
        sn = norm(surname(b['author']))
        ahit = bool(sn) and sn in an
        rec_id = it['id']
        if s >= 0.85 and ahit:
            hits.append({'rec_id': rec_id, 'score': round(s, 3), 'via_title': t,
                         'langs': langs, 'english': 'English' in langs, 'author_hit': True,
                         'rec': it})
        elif s >= 0.5:
            hits.append({'rec_id': rec_id, 'score': round(s, 3), 'via_title': t,
                         'langs': langs, 'english': 'English' in langs, 'author_hit': ahit,
                         'rec': it})
    return hits

out = []
for b in BOOKS:
    titles = [b['title']] + b.get('alt_titles', [])
    hits = match_book(b, titles)
    strong = [h for h in hits if h['score'] >= 0.85 and h['author_hit']]
    partial = [h for h in hits if h not in strong]
    out.append({'id': b['id'], 'title': b['title'], 'author': b['author'],
                'strong': strong, 'partial': partial})
    print(f"[{b['id']:02d}] strong={len(strong)} partial={len(partial)}  {b['title'][:42]!r}")
    for h in strong:
        r = h['rec']
        print(f"      ENG={h['english']} {r['title']!r} | {r.get('subtitle')!r} | {r.get('firstCreatorName')} | "
              f"narr={r.get('narrators')} | {r.get('formats')} | own={r.get('isOwned')} avail={r.get('availableCopies')} "
              f"holds={r.get('holdsCount')} wait={r.get('estimatedWaitDays')} | {r.get('isbns')} | {r.get('record_url')}")
    for h in partial:
        r = h['rec']
        print(f"      ~partial({h['score']}) {r['title']!r} | {r.get('firstCreatorName')} | {r.get('languages')}")

json.dump(out, open(os.path.join(HERE, 'phase_a3_matches.json'), 'w'), indent=1, ensure_ascii=False)
print('\nbooks with a strong English audiobook match:',
      sum(1 for x in out if any(h['english'] for h in x['strong'])))
