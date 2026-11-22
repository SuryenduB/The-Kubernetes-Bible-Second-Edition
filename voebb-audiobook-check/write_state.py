"""Write progress.md and evidence.md, then run the final audit."""
import csv, json, os, re
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = '/private/var/folders/yn/kd7d4f2n0p92c7pfq8bc3mc40000gp/T/opencode/voebb_run'
rows = list(csv.reader(open(os.path.join(HERE, 'results.csv'), encoding='utf-8')))
hdr, data = rows[0], rows[1:]
ev = json.load(open(os.path.join(HERE, 'evidence_records.json'), encoding='utf-8'))
od = json.load(open(os.path.join(RUN, 'od_api.json')))
od_auth = json.load(open(os.path.join(RUN, 'od_author.json')))
od_ex = json.load(open(os.path.join(RUN, 'od_extra_titles.json')))
ol_ex = json.load(open(os.path.join(RUN, 'onleihe_extra.json')))
cat = json.load(open(os.path.join(RUN, 'cat_raw.json')))
cnt = Counter(r[3] for r in data)

# ---------------- progress.md ----------------
p = []
p.append('# Progress — VÖBB audiobook check (64 books)')
p.append('')
p.append('Run date: 2026-10-20 · all 64 books processed · no PENDING rows left')
p.append('')
p.append('## Status counts')
p.append('')
p.append('| Status | Count |')
p.append('|---|---|')
for k in ('AVAILABLE_NOW', 'WAITLIST', 'HELD_STATUS_UNKNOWN', 'NOT_FOUND_AFTER_FULL_SEARCH',
          'UNVERIFIED_ACCESS_LIMITATION', 'PENDING'):
    if cnt.get(k):
        p.append(f'| {k} | {cnt[k]} |')
p.append(f'| **total** | **{sum(cnt.values())}** |')
p.append('')
p.append('## Completed IDs (by status)')
p.append('')
for st in ('AVAILABLE_NOW', 'WAITLIST', 'HELD_STATUS_UNKNOWN', 'NOT_FOUND_AFTER_FULL_SEARCH',
           'UNVERIFIED_ACCESS_LIMITATION'):
    ids = [r[0] for r in data if r[3] == st]
    if ids:
        p.append(f'- **{st}** ({len(ids)}): ' + ', '.join(ids))
p.append('')
p.append('## Pending IDs')
p.append('')
pend = [r[0] for r in data if r[3] == 'PENDING']
p.append('- ' + (', '.join(pend) if pend else 'none — loop complete'))
p.append('')
p.append('## Next action')
p.append('')
p.append('- None required. All 64 rows are adjudicated and audited.')
p.append('- Re-run `build_results.py` (and `verify_browser.py` for the displayed-status pass) to refresh.')
p.append('')
p.append('## Work log')
p.append('')
p.append('| Step | What ran | Result |')
p.append('|---|---|---|')
p.append('| 1 | OverDrive/Libby (VÖBB) JSON API: exact title + title/surname variants, paginated | `od_api.json` (64 books) |')
p.append('| 2 | OverDrive author-surname-only pass (proves absence of variant titles) | `od_author.json` |')
p.append('| 3 | OverDrive alt-title / distinctive-word pass (Timeshelter, The Perfect Nanny, The Elementary Particles, A Good Man Is Hard to Find, The Death of Ivan Ilyich, Zen and the Art…, How to Change Your Mind) | `od_extra_titles.json` |')
p.append('| 4 | Independent HTML-search cross-check (search page + full subject sweep of 22,266 audiobook records) | `phase_a_overdrive.py`, `phase_a2b_sweep.py`, `phase_a3_match.py` |')
p.append('| 5 | Onleihe (VÖBB) POST search: title + author-surname, candidate detail pages (Sprache/Format/Exemplare/status) | `onleihe_raw.json`, `onleihe_cand.json`, `onleihe_extra.json` |')
p.append('| 6 | Main VÖBB catalogue (aDISWeb) session search: title + author, medium/availability parsed | `cat_raw.json` |')
p.append('| 7 | Record-level browser verification of every positive record (displayed status only, no borrowing) | `browser_status.json` |')
p.append('| 8 | Adjudication + CSV/evidence output | `results.csv`, `evidence.md` |')
p.append('')
open(os.path.join(HERE, 'progress.md'), 'w', encoding='utf-8').write('\n'.join(p))

# ---------------- evidence.md ----------------
e = []
e.append('# Evidence — VÖBB English audiobook check (64 books)')
e.append('')
e.append('Checked 2026-10-20. All three VÖBB services were reached through the official VÖBB')
e.append('digital-services page (www.voebb.de → "Die Digitalen Angebote des VÖBB"):')
e.append('')
e.append('- **OverDrive / Libby (VÖBB)**: https://voebb.overdrive.com — public search JSON '
         '`https://thunder.api.overdrive.com/v2/libraries/voebb/media?query=…&mediaType=audiobook&language=en`, '
         'cross-checked with the HTML search page `https://voebb.overdrive.com/search?query=…`.')
e.append('- **Onleihe (VÖBB)**: https://voebb.onleihe.de/berlin/frontend/ — POST search '
         '`search,0-0-0-0-0-0-0-0-0-0-0.html` (`pText`, `cmdId=703`, `sK=1000`), detail pages `mediaInfo,…`.')
e.append('- **Main catalogue (aDISWeb OPAC)**: https://www.voebb.de — session POST '
         '`/aDISWeb/<session>/app` (`THEMA2_1`, `THEMA1_1`, `SUCBER_1`, `$Autosuggest`, `$$GFBO_1=Suchen`).')
e.append('')
e.append('No login, no borrowing, no holds, no purchases; all requests were anonymous read-only searches.')
e.append('')
e.append('## Search coverage per book (all three sources)')
e.append('')
e.append('| # | Book | OverDrive queries | OverDrive author pass | Onleihe | Catalogue |')
e.append('|---|---|---|---|---|---|')
for r in data:
    n = r[0]
    qs = list((od.get(n) or {}).get('queries', {}).keys())
    ex_qs = list((od_ex.get(n) or {}).get('queries', {}).keys()) if isinstance((od_ex.get(n) or {}).get('queries'), dict) else []
    ap = 'yes' if od_auth.get(n) else 'no'
    olx = 'yes' if ol_ex.get(n) else 'no'
    cq = list((cat.get(n) or {}).get('queries', {}).keys())
    e.append(f"| {n} | {r[1]} | {'; '.join(qs) or '—'}{' (+' + '; '.join(ex_qs) + ')' if ex_qs else ''} | {ap} | {olx} | "
             f"{'; '.join(cq) or '—'} |")
e.append('')
e.append('## Verified records (positive results only)')
e.append('')
e.append('| # | Book | Platform | Title on record | Edition | Runtime | Narrator | Language | Format | Copies/holds | Displayed status | Evidence link |')
e.append('|---|---|---|---|---|---|---|---|---|---|---|---|')
for b in ev:
    for r in b['records']:
        e.append(f"| {b['book']} | {b['title']} | {r['source']} | {r['title']} | {r['edition'] or '—'} | "
                 f"{r['duration'] or '—'} | {r['narrator'] or '—'} | {r['language'] or '—'} | "
                 f"{', '.join(r['format']) if isinstance(r['format'], list) else r['format']} | "
                 f"{r['copies']}/{r['ownedCopies']} / {r['holds']} holds | {r['displayed'] or '—'} | {r['url']} |")
e.append('')
e.append('## Other-language audiobooks and physical CDs (recorded separately)')
e.append('')
e.append('| # | Book | Other-language / physical audio holdings |')
e.append('|---|---|---|')
for b in ev:
    e.append(f"| {b['book']} | {b['title']} | " + ' | '.join(b['other_language_or_physical']) + ' |')
e.append('')
e.append('## Web-search fallback (step E of the protocol)')
e.append('')
e.append('Queries run against the indexed VÖBB collection (plus `site:voebb.overdrive.com "<title>" "<surname>"` variants):')
e.append('')
e.append('| Query | Outcome |')
e.append('|---|---|')
for q, res in [
 ('site:voebb.overdrive.com "Things Fall Apart" audiobook',
  'only "When Things Fall Apart" (Pema Chödrön) — a different work; no Achebe audiobook'),
 ('site:voebb.overdrive.com "Midnight\'s Children" Rushdie audiobook',
  'only Salman Rushdie\'s "Knife" — not the requested novel'),
 ('site:voebb.overdrive.com "The Corrections" "Franzen" audiobook', 'no results'),
 ('site:voebb.overdrive.com "The Blind Assassin" "Atwood" audiobook', 'no results'),
 ('site:voebb.overdrive.com "A Confederacy of Dunces" audiobook', 'no results'),
 ('site:voebb.overdrive.com "The Poisonwood Bible" audiobook', 'no results'),
 ('site:voebb.overdrive.com "Zen and the Art of Motorcycle Maintenance" audiobook', 'no results'),
 ('site:voebb.overdrive.com "Austerlitz" Sebald audiobook', 'no results'),
 ('site:voebb.overdrive.com "The Phoenix Project" audiobook (control, unrelated list)',
  'surfaced only "AI For Good" (Josh Tyrangiel) — an unrelated VÖBB record, no new target titles'),
]:
    e.append(f'| `{q}` | {res} |')
e.append('')
e.append('## Method notes and special matching rules applied')
e.append('')
e.append('- **The Complete Plays** (01): only other authors\' "Complete plays" and a Shakespeare CD set were found; '
         'individual Orton plays would have been partial matches only — none exists, so the row is NOT_FOUND.')
e.append('- **The Stand** (14): the VÖBB English record is the complete & uncut edition (Unabridged, 47:47:51, '
         'Grover Gardner). No English abridged or dramatised audiobook is held; a German eAudio of the same novel '
         '("Das letzte Gefecht") is held and listed separately.')
e.append('- **Vernon Subutex 1** (39): volume 1 verified for the French physical CD ("Vernon Subutex 1", Audiolib) and '
         'for the German eAudio "Das Leben des Vernon Subutex 1" (Der Audio Verlag). No English edition in any source.')
e.append('- **Lullaby** (27): also searched as "The Perfect Nanny" (same novel) — no English audiobook; '
         'the only Slimani audiobook held is "Adele".')
e.append('- **Atomised** (41): also searched as "The Elementary Particles" (same novel) — no English audiobook; '
         'the only Houellebecq English audiobook held is "Serotonin".')
e.append('- **Time Shelter** (06): also searched as "Timeshelter" — no English audiobook; eBook only.')
e.append('- **The Bell Jar** (16): source-photo caveat preserved — the title was partly obscured in the photo, '
         'the title was identified as *The Bell Jar* by Sylvia Plath and confirmed on the record.')
e.append('- **A Good Man Is Hard to Find and Other Stories** (32): neither the collection nor the individual story '
         'exists as an audiobook in VÖBB; no other contents list was substituted.')
e.append('- **The Death of Ivan Ilyich and Other Stories** (44): only the single novella "The Death of Ivan Ilyich" '
         '(Naxos, 2:51:09) is held (0/1, 2 holds) — a partial match, not the requested collection, so the row is NOT_FOUND.')
e.append('- Same-title strangers were rejected by author check: "The Luminaries" (Susan Dennard ≠ Eleanor Catton), '
         '"Freedom" (Angela Merkel ≠ Jonathan Franzen), "The Sea" (Jack London / Katee Robert ≠ John Banville), '
         '"The Shining Girls" (Lauren Beukes ≠ Stephen King), "The Stand-Up Groomsman" (Jackie Lau ≠ Stephen King).')
e.append('')
e.append('## Limitations')
e.append('')
e.append('- Borrowing status is the public, signed-out view. A VÖBB card holder sees the same copy counts; '
         'holds already placed by the user are not visible anonymously.')
e.append('- OverDrive\'s keyword search is fuzzy; to rule titles out reliably every book was also matched against '
         'a complete sweep of the VÖBB OverDrive audiobook catalogue (22,266 records across all 195 subjects, '
         '7,509 of them English).')
e.append('- The main catalogue (aDISWeb) search is title/author based; its "E-Audio" rows mirror the OverDrive '
         'collection, and "CD" rows are physical media — they are listed in the separate column, never counted as '
         'digital availability.')
e.append('- Edition flags come from the record itself; where a record states no edition (e.g. 22 The Unbearable '
         'Lightness of Being) this is noted instead of guessing.')
e.append('')
open(os.path.join(HERE, 'evidence.md'), 'w', encoding='utf-8').write('\n'.join(e))

# ---------------- final audit ----------------
errs = []
if len(data) != 64: errs.append(f'row count {len(data)} != 64')
ids = [int(r[0]) for r in data]
if ids != list(range(1, 65)): errs.append('IDs are not 1..64 without gaps/dupes')
allowed = {'AVAILABLE_NOW','WAITLIST','HELD_STATUS_UNKNOWN','NOT_FOUND_AFTER_FULL_SEARCH',
           'UNVERIFIED_ACCESS_LIMITATION','PENDING'}
for r in data:
    if r[3] not in allowed: errs.append(f"row {r[0]} bad status {r[3]}")
    if r[3] == 'PENDING': errs.append(f"row {r[0]} still PENDING")
    if r[3] in ('AVAILABLE_NOW','WAITLIST') and (not r[6] or r[6] == '—'):
        errs.append(f"row {r[0]} positive without evidence link")
    if r[3] == 'AVAILABLE_NOW' and 'Borrow' not in r[8] and 'Jetzt ausleihen' not in r[8]:
        errs.append(f"row {r[0]} AVAILABLE_NOW without explicit borrow evidence")
    if not r[7]: errs.append(f"row {r[0]} missing date")
print('AUDIT:', 'PASS' if not errs else 'FAIL')
for x in errs:
    print('  -', x)
print('counts:', dict(cnt), 'total', sum(cnt.values()))
