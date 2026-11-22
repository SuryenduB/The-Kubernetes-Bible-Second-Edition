#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""OverDrive author-only audiobook search (English) for all books.

IMPORTANT: the API returns only ~24 items per page even when limit=50 is
requested. Prolific authors (Stephen King: 81, Margaret Atwood: 72) therefore
need explicit pagination — run() pages through until len(items) >= totalItems.
Skipping this can miss the very title being searched for."""
import json, subprocess, sys, os, time, urllib.parse
sys.path.insert(0,'/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results')
from books47 import BOOKS
from od_api_batch import slim

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36'
OUT='/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/od_author.json'

def q(query, extra='&mediaType=audiobook&language=en&limit=50'):
    url='https://thunder.api.overdrive.com/v2/libraries/voebb/media?query='+urllib.parse.quote(query)+extra
    for a in range(3):
        p=subprocess.run(['curl','-s','-A',UA,'--max-time','60',url],capture_output=True,text=True)
        try: return json.loads(p.stdout)
        except Exception: time.sleep(2)
    return {}

def run():
    out=json.load(open(OUT)) if os.path.exists(OUT) else {}
    for n,title,author in BOOKS:
        k=str(n)
        if k in out and out[k].get('done'): continue
        rec={'author':author,'items':[],'done':True}
        d=q(author)
        if 'items' in d:
            rec['total']=d.get('totalItems')
            rec['items']=[slim(x) for x in d['items']]
        # Page through remaining results (page size ~24, independent of limit).
        have={it['id'] for it in rec['items']}
        page=1
        while rec.get('total') and len(rec['items'])<rec['total'] and page<8:
            page+=1
            d2=q(author, extra='&mediaType=audiobook&language=en&limit=50&page='+str(page))
            new=d2.get('items') or []
            if not new: break
            for x in new:
                s=slim(x)
                if s['id'] not in have:
                    have.add(s['id']); rec['items'].append(s)
            time.sleep(1.2)
        out[k]=rec
        json.dump(out,open(OUT,'w'),ensure_ascii=False,indent=1)
        print(n,author,'->',len(rec['items']),'/',rec.get('total'),flush=True)
        time.sleep(1.2)

if __name__=='__main__': run()
