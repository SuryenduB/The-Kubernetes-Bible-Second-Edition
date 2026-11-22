#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""Supplementary Onleihe pass: author-surname search + extra pages for big result sets."""
import json, re, subprocess, time, os, sys, html
sys.path.insert(0,'/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results')
from books47 import BOOKS
from onleihe_search import search

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36'
OUT='/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/onleihe_extra.json'

def page_url(n):  # n>=2
    return f'https://voebb.onleihe.de/berlin/frontend/search,0-0-0-700-0-0-{n-2}-1000-0-0-0.html'

def fetch_page(url):
    p=subprocess.run(['curl','-s','-A',UA,url],capture_output=True,text=True).stdout
    res={'count':None,'items':[]}
    m=re.search(r'ergab ([\d\.]+) Titeltreffer',html.unescape(p))
    if m: res['count']=m.group(1)
    for card in re.split(r"test-id='mediaCard'",p)[1:]:
        c=card[:9000]
        t=re.search(r"test-id='cardTitle'>(.*?)</h3>",c,re.S)
        a=re.search(r"test-id='cardAuthor'>(.*?)</p>",c,re.S)
        link=re.search(r'href="(mediaInfo,[^"]+)"',c)
        icons=re.findall(r'<svg class="icon (ic_[a-z0-9]+)',c)
        res['items'].append({
          'title':html.unescape(re.sub('<[^>]+>','',t.group(1))).strip() if t else None,
          'author':html.unescape(re.sub('<[^>]+>','',a.group(1))).strip() if a else None,
          'icons':icons,
          'link':'https://voebb.onleihe.de/berlin/frontend/'+link.group(1) if link else None})
    return res

def run():
    out=json.load(open(OUT)) if os.path.exists(OUT) else {}
    for n,title,author in BOOKS:
        k=str(n)
        if k in out and out[k].get('done'): continue
        surname=author.split()[-1]
        rec={'author_query':None,'extra_pages':[],'done':True}
        try:
            rec['author_query']=search(surname)
        except Exception as e:
            rec['author_query']={'error':str(e)}
        time.sleep(1.2)
        base=json.load(open('/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/onleihe_raw.json')).get(k,{})
        maxcount=0
        for q,qv in base.get('queries',{}).items():
            try: maxcount=max(maxcount,int(qv.get('count') or 0))
            except Exception: pass
        if maxcount>20:
            for p in (2,3):
                try:
                    rec['extra_pages'].append({'page':p,'data':fetch_page(page_url(p))})
                except Exception as e:
                    rec['extra_pages'].append({'page':p,'error':str(e)})
                time.sleep(1.2)
        out[k]=rec
        json.dump(out,open(OUT,'w'),ensure_ascii=False,indent=1)
        print(n,title,'extra done',flush=True)
    print('saved',OUT)

if __name__=='__main__': run()
