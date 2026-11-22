#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""Strict candidate extraction: English audiobooks in VÖBB OverDrive whose title matches well."""
import json, re, sys, unicodedata
sys.path.insert(0,'/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results')
from books47 import BOOKS

def norm(s):
    if not s: return ''
    s=unicodedata.normalize('NFKD',s).lower()
    s=s.replace('&',' and ')
    s=re.sub(r'[^a-z0-9 ]',' ',s)
    return re.sub(r'\s+',' ',s).strip()

SPECIAL={6:['time shelter','timeshelter'],
         27:['lullaby','the perfect nanny'],
         41:['atomised','the elementary particles','atomized'],
         32:['a good man is hard to find and other stories','a good man is hard to find'],
         44:['the death of ivan ilyich and other stories','the death of ivan ilyich'],
         21:['zen and the art of motorcycle maintenance an inquiry into values','zen and the art of motorcycle maintenance'],
         15:['how to change your mind the new science of psychedelics','how to change your mind'],
         39:['vernon subutex 1','vernon subutex'],
         49:['the watcher in the shadows','the watcher in the shadows a mystery'],
        }

od=json.load(open('/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/od_api.json'))

def close(tv,tn):
    if tv==tn: return True
    # allow subtitle continuation
    if tn.startswith(tv+' '): return True
    if tv.startswith(tn+' '): return True
    return False

for n,title,author in BOOKS:
    v=od.get(str(n))
    if not v: continue
    vs=[norm(x) for x in (SPECIAL.get(n) or [title.split(':')[0]])]
    surname=norm(author.split()[-1])
    seen={}
    for q,qv in v['queries'].items():
        for it in qv.get('items') or []:
            seen[it['id']]=it
    rows=[]
    for it in seen.values():
        tn=norm(it['title'] or '')
        if it['type']!='Audiobook': continue
        if 'en' not in (it['lang'] or ''): continue
        if not any(close(tv,tn) for tv in vs): continue
        rows.append(it)
    print('='*100)
    print(f"{n:02d} {title} | {author}  -> audiobook candidates: {len(rows)}")
    for it in rows:
        okau = surname in norm(it['author'] or '') or norm(it['author'] or '') in surname
        print(f"   {'AUTH-OK' if okau else 'AUTH??'} [ed={it['edition']}] {it['title']} | {it['author']} | narr:{it['narrator']} | avail={it['avail']} copies={it['copies']}/{it['ownedCopies']} holds={it['holds']} holdable={it['holdable']} waitd={it['waitsdays']} | dur={it['duration']} | id={it['id']} | {it['publisher']} | {it['publish']}")
