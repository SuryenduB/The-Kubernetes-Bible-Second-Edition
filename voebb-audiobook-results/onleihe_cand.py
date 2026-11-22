#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""Extract Onleihe title-matching candidates for all 64 books and detail-check them."""
import json, re, sys, unicodedata, os, time
sys.path.insert(0,'/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results')
from onleihe_info import info
from books47 import BOOKS

def norm(s):
    if not s: return ''
    s=unicodedata.normalize('NFKD',s).lower()
    s=re.sub(r'[^a-z0-9 ]',' ',s)
    return re.sub(r'\s+',' ',s).strip()

SPECIAL={27:['time shelter','timeshelter'],
         19:['vernon subutex'],
         28:['the 32','thirty two'],
         16:['11 22 63','112263'],
         34:['four novels of the 1960s']}

raw=json.load(open('/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/onleihe_raw.json'))
CACHE='/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/onleihe_details.json'
det=json.load(open(CACHE)) if os.path.exists(CACHE) else {}

out={}
for n,title,author in BOOKS:
    vs=SPECIAL.get(n) or [norm(title.split(':')[0])]
    v=raw.get(str(n)) or {}
    cands={}
    for q,qv in v.get('queries',{}).items():
        for it in qv.get('items') or []:
            tn=norm(it['title'] or '')
            if any(tv in tn or tn in tv for tv in vs):
                cands[it['link']]=it
    detailed=[]
    for link,it in cands.items():
        if link not in det:
            try: det[link]=info(link)
            except Exception as e: det[link]={'error':str(e)}
            time.sleep(0.7)
            json.dump(det,open(CACHE,'w'),ensure_ascii=False,indent=1)
        detailed.append(det[link])
    out[n]={'title':title,'author':author,'candidates':detailed}

json.dump(out,open('/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/onleihe_cand.json','w'),ensure_ascii=False,indent=1)
for n in sorted(out):
    o=out[n]
    print('='*80)
    print(f"{n:02d} {o['title']} | {o['author']}")
    for d in o['candidates']:
        print('   ',d.get('titel'),'|',d.get('autor'),'| sprache',d.get('sprache'),'| format',d.get('format'),'| status',d.get('status'),'| ex',d.get('exemplare'),'| url',d.get('url'))
