#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""Summarise candidate matches per book from all three raw sources."""
import json, re, sys, unicodedata

def norm(s):
    if not s: return ''
    s=unicodedata.normalize('NFKD',s)
    s=s.lower()
    s=re.sub(r'[^a-z0-9 ]',' ',s)
    s=re.sub(r'\s+',' ',s).strip()
    return s

SPECIAL={6:['time shelter','timeshelter'],
         27:['lullaby','the perfect nanny'],
         41:['atomised','the elementary particles','atomized'],
         }

def load(p):
    try: return json.load(open(p))
    except Exception: return {}

od=load('/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/od_api.json'); ol=load('/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/onleihe_raw.json'); cat=load('/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/cat_raw.json')

BOOKS=[(n,t,a) for n,t,a in [(int(k),v['title'],v['author']) for k,v in od.items()]] if od else []
BOOKS.sort()

def title_variants(n,title):
    t=title.split(':')[0].strip()
    vs=[norm(t)]
    if n in SPECIAL: vs=SPECIAL[n]
    return vs

def report(n,title,author):
    print('='*90)
    print(f'{n:02d} {title} | {author}')
    surname=author.split()[-1]
    tvs=title_variants(n,title)
    # ---- OverDrive
    v=od.get(str(n))
    if v:
        seen={}
        for q,qv in v['queries'].items():
            for it in qv.get('items') or []:
                seen[it['id']]=it
        print(' OVERDRIVE items (all):',len(seen))
        for it in seen.values():
            tn=norm(it['title'] or '')
            match=any(tv in tn or tn in tv for tv in tvs)
            interesting = match or (it['type']=='Audiobook' and 'en' in (it['lang'] or ''))
            if not interesting: continue
            flag='***' if (match and it['type']=='Audiobook' and 'en' in (it['lang'] or '') and it['owned']) else '   '
            print(f"  {flag} [{it['type']}] {it['title']} | {it['author']} | narr:{it['narrator']} | lang={it['lang']} | ed={it['edition']} | owned={it['owned']} avail={it['avail']} copies={it['copies']}/{it['ownedCopies']} holds={it['holds']} holdable={it['holdable']} waitd={it['waitsdays']} | dur={it['duration']} | id={it['id']}")
    # ---- Onleihe
    o=ol.get(str(n))
    if o:
        seen={}
        for q,qv in o['queries'].items():
            for it in qv.get('items') or []:
                seen[(it['title'],it['author'])]=it
        hits=[]
        for it in seen.values():
            tn=norm(it['title'] or '')
            if any(tv in tn or tn in tv for tv in tvs):
                hits.append(it)
        print(' ONLEIHE title matches:',len(hits))
        for it in hits:
            print(f"   [{','.join(it['icons'])}] {it['title']} | {it['author']} | avail={it['avail_text']} btn={it['button']} | {it['link']}")
    # ---- Catalogue
    c=cat.get(str(n))
    if c:
        seen={}
        for q,qv in c['queries'].items():
            for it in qv.get('items') or []:
                seen[it.get('ak')]=it
        hits=[]
        for it in seen.values():
            tn=norm(it['title'] or '')
            if any(tv in tn or tn in tv for tv in tvs):
                hits.append(it)
        print(' CATALOGUE title matches:',len(hits))
        for it in hits:
            print(f"   [{it['medium']}] {it['title']} | {it['desc']} | {it['year']} | {it['availability']} | AK{it['ak']}")
    print()

if __name__=='__main__':
    rng=range(1,65)
    if len(sys.argv)>1: rng=range(int(sys.argv[1]),int(sys.argv[2])+1)
    for n,t,a in BOOKS:
        if n in rng: report(n,t,a)
