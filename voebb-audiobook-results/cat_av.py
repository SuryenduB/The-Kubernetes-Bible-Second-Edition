#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""Catalogue: audiobook-format (E-Audio/CD) matches per book."""
import json, re, sys, unicodedata
sys.path.insert(0,'/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results')
from books47 import BOOKS

def norm(s):
    if not s: return ''
    s=unicodedata.normalize('NFKD',s).lower().replace('&',' and ')
    s=re.sub(r'[^a-z0-9 ]',' ',s)
    return re.sub(r'\s+',' ',s).strip()

SPECIAL={6:['time shelter','timeshelter'],27:['lullaby','the perfect nanny'],
         41:['atomised','the elementary particles','atomized'],
         32:['a good man is hard to find'],44:['the death of ivan ilyich'],
         21:['zen and the art of motorcycle maintenance'],15:['how to change your mind'],
         39:['vernon subutex'],2:['things fall apart']}

cat=json.load(open('/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/cat_raw.json'))
want={'E-Audio','CD','Hörbuch','E-Ressource','DVD'}
for n,title,author in BOOKS:
    v=cat.get(str(n))
    if not v: continue
    vs=[norm(x) for x in (SPECIAL.get(n) or [title.split(':')[0]])]
    seen={}
    for q,qv in v['queries'].items():
        for it in qv.get('items') or []:
            seen[it.get('ak')]=it
    rows=[]
    for it in seen.values():
        tn=norm(it['title'] or '')
        if not any(tv in tn for tv in vs): continue
        if (it['medium'] or '') not in want: continue
        rows.append(it)
    print('='*100)
    print(f"{n:02d} {title} -> catalogue A/V matches: {len(rows)}")
    for it in rows:
        print(f"   [{it['medium']}] {it['title'][:110]} | {it['desc'][:150] if it['desc'] else ''} | {it['year']} | {it['availability']} | AK{it['ak']}")
