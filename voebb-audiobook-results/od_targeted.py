#!/usr/bin/env python3
"""Targeted OverDrive search restricted to audiobook + English for each book.
Pages fully; reports every item whose title matches the target loosely and
whose author matches (or title is an exact match)."""
import json, re, subprocess, sys, time, urllib.parse, unicodedata, os
HERE=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,HERE)
from books47 import BOOKS

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36'
OUT=os.path.join(HERE,'od_targeted.json')

def norm(s):
    s=unicodedata.normalize('NFKD',s or '').lower()
    return re.sub(r'\s+',' ',re.sub(r'[^a-z0-9 ]',' ',s)).strip()

def fetch(q,page=1):
    url=('https://thunder.api.overdrive.com/v2/libraries/voebb/media?query='
         +urllib.parse.quote(q)+f'&mediaType=audiobook&language=en&limit=50&page={page}')
    for a in range(3):
        p=subprocess.run(['curl','-s','-A',UA,'--max-time','60',url],capture_output=True,text=True)
        try: return json.loads(p.stdout)
        except Exception: time.sleep(2)
    return {}

def slim(it):
    return {'id':it.get('id'),'title':it.get('title'),'subtitle':it.get('subtitle'),
            'author':it.get('firstCreatorName'),
            'narrator':', '.join(c['name'] for c in it.get('creators',[]) if c.get('role')=='Narrator'),
            'type':(it.get('type') or {}).get('name'),'edition':it.get('edition'),
            'lang':','.join(l['id'] for l in it.get('languages',[])),
            'avail':it.get('isAvailable'),'copies':it.get('availableCopies'),
            'ownedCopies':it.get('ownedCopies'),'holds':it.get('holdsCount'),
            'holdable':it.get('isHoldable'),'wait':it.get('estimatedWaitDays'),
            'publisher':(it.get('publisher') or {}).get('name'),
            'publish':it.get('publishDateText'),
            'duration':[f.get('duration') for f in (it.get('formats') or []) if f.get('duration')][:1]}

ALT={16:['11/22/63',"eleven twenty two sixty three"],
     19:['Vernon Subutex'],
     23:['Zen and the Art of Motorcycle Maintenance'],
     28:['The Thirty-Two'],
     29:['Stories of Stephen Dixon'],
     34:['Four Novels of the 1960s'],
     45:['Extinction Bernhard']}

def run():
    out=json.load(open(OUT)) if os.path.exists(OUT) else {}
    for n,title,author in BOOKS:
        k=str(n)
        if k in out and out[k].get('done'): continue
        surname=author.split()[-1]
        tclean=title.split(':')[0].strip()
        qs=[tclean, f'{tclean} {surname}']+ALT.get(n,[])
        rec={'title':title,'author':author,'queries':{},'done':True}
        for q in qs:
            d=fetch(q); items=[]
            total=d.get('totalItems') or 0
            items=[slim(x) for x in (d.get('items') or [])]
            page=1
            while len(items)<total and page<6:
                page+=1
                d2=fetch(q,page)
                new=d2.get('items') or []
                if not new: break
                items+=[slim(x) for x in new]
                time.sleep(1.0)
            rec['queries'][q]={'total':total,'items':items}
            time.sleep(1.1)
        out[k]=rec
        json.dump(out,open(OUT,'w'),ensure_ascii=False,indent=1)
        print(n,title,'->',{q:v['total'] for q,v in rec['queries'].items()},flush=True)

if __name__=='__main__': run()
