#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""OverDrive (VÖBB) search via public thunder API. Robust, structured."""
import json, subprocess, sys, os, time, urllib.parse
sys.path.insert(0,'/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results')
from books47 import BOOKS

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36'
OUT='/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/od_api.json'

def api(path):
    url='https://thunder.api.overdrive.com/v2/libraries/voebb/'+path
    for attempt in range(3):
        p=subprocess.run(['curl','-s','-A',UA,'--max-time','60',url],capture_output=True,text=True)
        try:
            return json.loads(p.stdout)
        except Exception:
            time.sleep(2)
    return {'error':'parse'}

def search(q, extra='', page=1, limit=50):
    path='media?query='+urllib.parse.quote(q)+f'&limit={limit}&page={page}'+extra
    d=api(path)
    return d

def slim(it):
    return {
      'id':it.get('id'),'title':it.get('title'),'subtitle':it.get('subtitle'),
      'author':it.get('firstCreatorName'),
      'narrator':', '.join(c['name'] for c in it.get('creators',[]) if c.get('role')=='Narrator'),
      'type':(it.get('type') or {}).get('name'),
      'lang':','.join(l['id'] for l in it.get('languages',[])),
      'owned':it.get('isOwned'),'avail':it.get('isAvailable'),
      'copies':it.get('availableCopies'),'ownedCopies':it.get('ownedCopies'),
      'holds':it.get('holdsCount'),'holdable':it.get('isHoldable'),
      'waitsdays':it.get('estimatedWaitDays'),'availType':it.get('availabilityType'),
      'edition':it.get('edition'),'publish':it.get('publishDateText'),
      'publisher':(it.get('publisher') or {}).get('name'),
      'formats':[f.get('name') for f in (it.get('formats') or [])],
      'duration':[f.get('duration') for f in (it.get('formats') or []) if f.get('duration')],
      'isbn':list({f.get('isbn') for f in (it.get('formats') or []) if f.get('isbn')}),
      'reserveId':it.get('reserveId'),
    }

def run():
    out=json.load(open(OUT)) if os.path.exists(OUT) else {}
    start=int(sys.argv[1]) if len(sys.argv)>1 else 1
    end=int(sys.argv[2]) if len(sys.argv)>2 else 999
    for n,title,author in BOOKS:
        if n<start or n>end: continue
        k=str(n)
        if k in out and out[k].get('done'): print(n,'cached',flush=True); continue
        surname=author.split()[-1]
        tclean=title.split(':')[0].strip()
        variants=[tclean, f'{tclean} {surname}']
        # special variant titles
        if n==6: variants.append('Timeshelter')
        if n==27: variants.append('The Perfect Nanny')
        if n==41: variants.append('The Elementary Particles')
        if n==32: variants.append('A Good Man Is Hard to Find')
        if n==44: variants.append('The Death of Ivan Ilyich')
        if n==21: variants.append('Zen and the Art of Motorcycle Maintenance')
        if n==15: variants.append('How to Change Your Mind')
        rec={'title':title,'author':author,'queries':{},'done':True}
        for q in variants:
            d=search(q)
            items=[]
            if isinstance(d,dict) and 'items' in d:
                items=[slim(x) for x in d['items']]
                total=d.get('totalItems')
                page=1
                while total and len(items)<total and page<3:
                    page+=1
                    d2=search(q,page=page)
                    if 'items' not in d2: break
                    items+= [slim(x) for x in d2['items']]
            rec['queries'][q]={'total':d.get('totalItems') if isinstance(d,dict) else None,
                               'mediaTypeFacets':{i['id']:i.get('totalItems') for i in ((d.get('facets') or {}).get('mediaTypes') or {}).get('items',[])} if isinstance(d,dict) and d.get('facets') else None,
                               'items':items}
            time.sleep(1.2)
        out[k]=rec
        json.dump(out,open(OUT,'w'),ensure_ascii=False,indent=1)
        print(n,title,'done',flush=True)
    print('saved',OUT,flush=True)

if __name__=='__main__': run()
