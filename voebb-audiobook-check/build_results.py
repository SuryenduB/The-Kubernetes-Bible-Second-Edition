"""Final adjudication for the 64-book VÖBB audiobook check.

Derives every row from the collected evidence:
  * OverDrive / Libby (VÖBB)  -> od_api.json, od_author.json, od_extra_titles.json
  * Onleihe (VÖBB)            -> onleihe_cand.json, onleihe_extra.json
  * Main catalogue (aDISWeb)  -> cat_raw.json
Writes results.csv, progress.md, evidence.md.
"""
import csv, json, os, re
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = '/private/var/folders/yn/kd7d4f2n0p92c7pfq8bc3mc40000gp/T/opencode/voebb_run'
DATE = '2026-10-20'

BOOKS = [
 (1,"The Complete Plays","Joe Orton"),(2,"Things Fall Apart","Chinua Achebe"),
 (3,"Uncle Tom's Cabin","Harriet Beecher Stowe"),(4,"Gilead","Marilynne Robinson"),
 (5,"White Teeth","Zadie Smith"),(6,"Time Shelter","Georgi Gospodinov"),
 (7,"Do Androids Dream of Electric Sheep?","Philip K. Dick"),(8,"The Man in the High Castle","Philip K. Dick"),
 (9,"No Country for Old Men","Cormac McCarthy"),(10,"Midnight's Children","Salman Rushdie"),
 (11,"Waiting for the Barbarians","J. M. Coetzee"),(12,"Charlotte's Web","E. B. White"),
 (13,"Plainsong","Kent Haruf"),(14,"The Stand","Stephen King"),
 (15,"How to Change Your Mind: The New Science of Psychedelics","Michael Pollan"),
 (16,"The Bell Jar","Sylvia Plath"),(17,"The Amazing Adventures of Kavalier & Clay","Michael Chabon"),
 (18,"The Shining","Stephen King"),(19,"Middlesex","Jeffrey Eugenides"),(20,"Austerlitz","W. G. Sebald"),
 (21,"Zen and the Art of Motorcycle Maintenance: An Inquiry into Values","Robert M. Pirsig"),
 (22,"The Unbearable Lightness of Being","Milan Kundera"),(23,"A Confederacy of Dunces","John Kennedy Toole"),
 (24,"The Human Stain","Philip Roth"),(25,"The Whites","Richard Price"),
 (26,"Great Expectations","Charles Dickens"),(27,"Lullaby","Leïla Slimani"),(28,"Spring","Ali Smith"),
 (29,"Fear and Loathing in Las Vegas","Hunter S. Thompson"),(30,"Atonement","Ian McEwan"),
 (31,"We Need to Talk About Kevin","Lionel Shriver"),
 (32,"A Good Man Is Hard to Find and Other Stories","Flannery O'Connor"),(33,"Amsterdam","Ian McEwan"),
 (34,"American Pastoral","Philip Roth"),(35,"Knots & Crosses","Ian Rankin"),
 (36,"The Color Purple","Alice Walker"),(37,"The House of the Spirits","Isabel Allende"),
 (38,"The Joke","Milan Kundera"),(39,"Vernon Subutex 1","Virginie Despentes"),
 (40,"The Poisonwood Bible","Barbara Kingsolver"),(41,"Atomised","Michel Houellebecq"),
 (42,"Independence Day","Richard Ford"),(43,"The Glass Hotel","Emily St. John Mandel"),
 (44,"The Death of Ivan Ilyich and Other Stories","Leo Tolstoy"),(45,"The Waiter","Matias Faldbakken"),
 (46,"The History Boys","Alan Bennett"),(47,"The Woman Who Walked Into Doors","Roddy Doyle"),
 (48,"The Living Sea of Waking Dreams","Richard Flanagan"),(49,"The Watcher in the Shadows","Carlos Ruiz Zafón"),
 (50,"Everything Is Illuminated","Jonathan Safran Foer"),(51,"The Corrections","Jonathan Franzen"),
 (52,"The Narrow Road to the Deep North","Richard Flanagan"),(53,"Station Eleven","Emily St. John Mandel"),
 (54,"The Little Goblin Girl","Illy Hymen"),(55,"The Luminaries","Eleanor Catton"),
 (56,"Empire of the Sun","J. G. Ballard"),(57,"Notes from Underground","Fyodor Dostoevsky"),
 (58,"Celestial Bodies","Jokha Alharthi"),(59,"Freedom","Jonathan Franzen"),
 (60,"The Blind Assassin","Margaret Atwood"),(61,"Wolf Hall","Hilary Mantel"),(62,"The Sea","John Banville"),
 (63,"The Sense of an Ending","Julian Barnes"),(64,"The Dying Animal","Philip Roth"),
]

# German / other-language titles of the SAME work, verified against catalogue + Onleihe records
ALT_TITLES = {
 3: ["Onkel Toms Hütte"], 4: [], 7: ["Blade Runner"], 8: ["The Man in the High Castle", "Das Orakel vom Berge"],
 9: ["No country for old men", "Kein Land für alte Männer"], 12: ["Charlotte's Web", "Wilbur und Charlotte"],
 13: ["Das Band, das uns hält"], 14: ["The Stand", "Das letzte Gefecht"], 18: ["The shining"],
 19: ["Middlesex"], 20: ["Austerlitz"], 24: ["Der menschliche Makel"], 25: ["Die Unantastbaren"],
 26: ["Great expectations"], 29: ["Fear and loathing in Las Vegas"], 30: ["Atonement", "Abbitte"],
 39: ["Vernon Subutex 1", "Das Leben des Vernon Subutex"], 43: ["The glass hotel"], 50: ["Alles ist erleuchtet"],
 51: ["Die Korrekturen"], 52: ["The narrow road to the deep north"], 53: ["Station eleven", "Das Licht der letzten Tage"],
 55: ["Der Wald"], 59: ["Freedom", "Freiheit"], 61: ["Wolf hall", "Wölfe", "W komnatach Wolf Hall"],
 62: ["Die See"], 63: ["The sense of an ending", "Vom Ende einer Geschichte"], 64: ["Das sterbende Tier"],
}

od      = json.load(open(os.path.join(RUN, 'od_api.json')))
od_auth = json.load(open(os.path.join(RUN, 'od_author.json')))
od_ex   = json.load(open(os.path.join(RUN, 'od_extra_titles.json')))
ol      = json.load(open(os.path.join(RUN, 'onleihe_cand.json')))
ol_ex   = json.load(open(os.path.join(RUN, 'onleihe_extra.json')))
cat     = json.load(open(os.path.join(RUN, 'cat_raw.json')))
browser = {}
bpath = os.path.join(HERE, 'browser_status.json')
if os.path.exists(bpath):
    browser = {x['key']: x for x in json.load(open(bpath))}

STOP = set('the a an of and or in on to with for from by at as is it its'.split())
def norm(s):
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9]+', ' ', (s or '').lower())).strip()
def cw(s):
    return [w for w in norm(s).split() if w not in STOP]
def surname(a):
    return norm(a.split()[-1]) if a else ''
def overlap(req, blob):
    ew = set(cw(req)); rw = set(cw(blob))
    if not ew:
        return 0.0
    return len(ew & rw) / len(ew)

def od_items(n):
    out, seen = [], set()
    srcs = []
    rec = od.get(str(n)) or {}
    srcs += list((rec.get('queries') or {}).values())
    a = od_auth.get(str(n)) or {}
    if isinstance(a.get('queries'), dict):
        srcs += list(a['queries'].values())
    if a.get('items'):
        srcs.append({'items': a['items']})
    e = od_ex.get(str(n)) or {}
    if isinstance(e.get('queries'), dict):
        srcs += list(e['queries'].values())
    for q in srcs:
        for it in (q.get('items') or []):
            if it.get('id') in seen:
                continue
            seen.add(it.get('id')); out.append(it)
    return out

def od_audio(n, title, author, lang='en'):
    sn = surname(author)
    hits = []
    for it in od_items(n):
        if (it.get('type') or '').lower() != 'audiobook':
            continue
        langs = [l.strip() for l in (it.get('lang') or '').split(',') if l.strip()]
        if lang not in langs:
            continue
        if overlap(title, (it.get('title') or '') + ' ' + (it.get('subtitle') or '')) < 0.85:
            continue
        if sn and sn not in norm(it.get('author') or ''):
            continue
        hits.append(it)
    hits.sort(key=lambda x: (-(x.get('copies') or 0), x.get('title') or ''))
    return hits

def cat_items(n):
    out, seen = [], set()
    for q in (cat.get(str(n)) or {}).get('queries', {}).values():
        for it in q.get('items') or []:
            k = (it.get('ak'), it.get('title'))
            if k in seen:
                continue
            seen.add(k); out.append(it)
    return out

def cat_audio(n, aliases, author):
    """physical audiobook CDs of the same work (catalogue E-Audio rows mirror the digital
    OverDrive/Onleihe holdings and are therefore not repeated here)"""
    sn = surname(author)
    out = []
    for it in cat_items(n):
        if it.get('medium') != 'CD':
            continue
        t = (it.get('title') or '')
        blob = (t + ' ' + (it.get('desc') or '')).lower()
        if not any(overlap(a, t) >= 0.8 for a in aliases):
            continue
        if not sn or sn not in norm(blob):
            continue
        out.append(it)
    return out

def onleihe_items(n):
    items, seen = [], set()
    def add(a):
        u = ('|'.join(str(x) for x in (a.get('titel') or [])) + '|' +
             '|'.join(str(x) for x in (a.get('autor') or [])))
        if u in seen:
            return
        seen.add(u); items.append(a)
    for a in (ol.get(str(n)) or {}).get('candidates') or []:
        add(a)
    ex = ol_ex.get(str(n)) or {}
    for q in (ex.get('queries') or {}).values() if isinstance(ex.get('queries'), dict) else []:
        for it in (q.get('items') or []):
            add({'titel': [it.get('title')], 'autor': [it.get('author')],
                 'verlag': [], 'sprache': [], 'format': ['eAudio'] if 'ic_eaudio' in (it.get('icons') or []) else [],
                 'dauer': [], 'exemplare': [], 'status': it.get('avail_text'),
                 'borrow': it.get('button') == 'Jetzt ausleihen', 'url': it.get('link')})
    for it in (ex.get('author_query') or {}).get('items', []):
        if 'ic_eaudio' not in (it.get('icons') or []):
            continue
        add({'titel': [it.get('title')], 'autor': [it.get('author')], 'verlag': [],
             'sprache': [], 'format': ['eAudio'], 'dauer': [], 'exemplare': [],
             'status': it.get('avail_text'), 'borrow': it.get('button') == 'Jetzt ausleihen',
             'url': it.get('link')})
    return items

def ol_english_audio(n, title, author, aliases):
    sn = surname(author)
    out = []
    for a in onleihe_items(n):
        if 'Englisch' not in (a.get('sprache') or []):
            continue
        if not any('eAudio' in f for f in (a.get('format') or [])):
            continue
        blob = ' '.join(str(x) for x in (a.get('titel') or [])) + ' ' + ' '.join(str(x) for x in (a.get('autor') or []))
        if sn and sn not in norm(blob):
            continue
        if not any(overlap(al, blob) >= 0.8 for al in aliases):
            continue
        out.append(a)
    return out

rows, evidence = [], []
for n, title, author in BOOKS:
    aliases = [title] + ALT_TITLES.get(n, [])
    en_od = od_audio(n, title, author, 'en')
    other_od = od_audio(n, title, author, 'de') + [i for i in od_audio(n, title, author, 'fr')
                                                    if (i.get('lang') or '').find('fr') >= 0]
    en_ol = ol_english_audio(n, title, author, aliases)
    phys = cat_audio(n, aliases, author)
    sn_ol = surname(author)
    ol_other = []
    for a in onleihe_items(n):
        if not any('eAudio' in f for f in (a.get('format') or [])):
            continue
        if a in en_ol:
            continue
        if a.get('sprache') and 'Englisch' in a['sprache']:
            continue
        blob = ' '.join(str(x) for x in (a.get('titel') or [])) + ' ' + ' '.join(str(x) for x in (a.get('autor') or []))
        if sn_ol and sn_ol not in norm(blob):
            continue
        if not any(overlap(al, blob) >= 0.8 for al in aliases):
            continue
        ol_other.append(a)

    notes, other, ev = [], [], []
    od_now = [i for i in en_od if (i.get('copies') or 0) >= 1 and i.get('avail')]
    ol_now = [a for a in en_ol if a.get('borrow')]
    status, platform, link = 'NOT_FOUND_AFTER_FULL_SEARCH', '—', '—'
    if od_now:
        status, platform = 'AVAILABLE_NOW', 'OverDrive/Libby (VÖBB)'
        link = f"https://voebb.overdrive.com/media/{od_now[0]['id']}"
    elif ol_now:
        status, platform = 'AVAILABLE_NOW', 'Onleihe (VÖBB)'
        link = ol_now[0].get('url')
    elif en_od:
        status, platform = 'WAITLIST', 'OverDrive/Libby (VÖBB)'
        link = f"https://voebb.overdrive.com/media/{en_od[0]['id']}"
    elif en_ol:
        status, platform = 'WAITLIST', 'Onleihe (VÖBB)'
        link = en_ol[0].get('url')

    for it in en_od:
        ed = it.get('edition') or 'edition not stated in record'
        dur = (it.get('duration') or [None])[0]
        disp = browser.get(f"od_{it.get('id')}", {}).get('display', '')
        notes.append(f"OverDrive EN audiobook: {it.get('title')} [{ed}]"
                     + (f", {dur}" if dur else '') +
                     f", narrator {it.get('narrator') or 'n/a'}, {it.get('publisher')}, {it.get('publish')}; "
                     f"{it.get('copies')}/{it.get('ownedCopies')} copies, {it.get('holds')} holds, "
                     f"wait {it.get('waitsdays')}d, holdable={it.get('holdable')}"
                     + (f"; page shows: {disp}" if disp else ''))
        ev.append({'book': n, 'source': 'OverDrive/Libby (VÖBB)', 'title': it.get('title'),
                   'edition': ed, 'duration': dur, 'narrator': it.get('narrator'),
                   'language': it.get('lang'), 'format': it.get('formats'), 'publisher': it.get('publisher'),
                   'copies': it.get('copies'), 'ownedCopies': it.get('ownedCopies'), 'holds': it.get('holds'),
                   'waitDays': it.get('waitsdays'), 'holdable': it.get('holdable'),
                   'url': f"https://voebb.overdrive.com/media/{it.get('id')}", 'displayed': disp})
    for a in en_ol:
        ex = a.get('exemplare') or []
        mid = re.search(r'mediaInfo,0-0-(\d+)-', a.get('url', '') or '')
        disp = browser.get('ol_' + (mid.group(1) if mid else ''), {}).get('display', '')
        notes.append(f"Onleihe EN eAudio: {' / '.join(str(x) for x in (a.get('titel') or []))} — {' / '.join(str(x) for x in (a.get('autor') or []))}, "
                     f"{' / '.join(a.get('verlag') or [])}, Sprache {'/'.join(a.get('sprache') or [])}, "
                     f"Format {'/'.join(a.get('format') or [])}, {a.get('dauer')} min, {ex} -> {a.get('status')}"
                     + (f"; page shows: {disp}" if disp else ''))
        ev.append({'book': n, 'source': 'Onleihe (VÖBB)', 'title': ' / '.join(a.get('titel') or []),
                   'edition': '', 'duration': a.get('dauer'), 'narrator': '', 'language': 'Englisch',
                   'format': a.get('format'), 'publisher': ' / '.join(a.get('verlag') or []),
                   'copies': (ex[1] if len(ex) > 1 else None), 'ownedCopies': (ex[0] if ex else None),
                   'holds': (ex[2] if len(ex) > 2 else None), 'waitDays': None, 'holdable': a.get('hold'),
                   'url': a.get('url'), 'displayed': disp})
    for it in other_od:
        other.append(f"Other-language eAudio (OverDrive): {it.get('title')} [{it.get('lang')}], "
                     f"{it.get('publisher')}, {it.get('copies')}/{it.get('ownedCopies')} copies")
    for a in ol_other:
        other.append(f"Other-language eAudio (Onleihe): {' / '.join(str(x) for x in (a.get('titel') or []))} "
                     f"({'/'.join(a.get('sprache') or []) or 'German-language edition, language not shown on list card'})")
    for it in phys:
        med = 'physical CD'
        other.append(f"{med}: {(it.get('title') or '')[:60]} — {(it.get('desc') or '')[:80]} ({it.get('availability')})")
    if not other:
        other = ['—']
    if status == 'NOT_FOUND_AFTER_FULL_SEARCH':
        qs = list((od.get(str(n)) or {}).get('queries', {}).keys())
        notes.append('No English digital audiobook. OverDrive queries: ' + '; '.join(qs) +
                     ' | plus surname-only author pass' +
                     (' and alt-title pass' if od_ex.get(str(n)) else '') +
                     '; Onleihe: title + author-surname pass; main catalogue: title + author.')
    rows.append([str(n), title, author, status, ' | '.join(other), platform, link, DATE, ' | '.join(notes)])
    evidence.append({'book': n, 'title': title, 'author': author, 'status': status,
                      'platform': platform, 'evidence_link': link, 'records': ev,
                      'other_language_or_physical': other})

out_csv = os.path.join(HERE, 'results.csv')
with open(out_csv, 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f, quoting=csv.QUOTE_ALL)
    w.writerow(["Number","Book title","Author","English digital audiobook availability",
                "Other-language audiobook / physical CDs","Platform","Evidence link","Date checked","Notes"])
    for r in rows:
        w.writerow(r)
json.dump(evidence, open(os.path.join(HERE, 'evidence_records.json'), 'w'), indent=1, ensure_ascii=False)

cnt = Counter(r[3] for r in rows)
print('rows:', len(rows))
for k in sorted(cnt):
    print(f'  {k}: {cnt[k]}')
print()
for r in rows:
    print(f"  {r[0]:>2} {r[3]:<28} {r[1][:44]:<44} {r[5]}")
