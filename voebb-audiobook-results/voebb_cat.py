#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""VÖBB main catalogue (aDISWeb) search via session POST. Usage: voebb_cat.py "term" [scope]"""
import subprocess, re, sys, html, json, os, time, urllib.parse

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36'
JAR='/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/vcat_cookies.txt'

def curl(args):
    return subprocess.run(['curl','-s','-A',UA]+args,capture_output=True,text=True).stdout

def new_session():
    # fresh cookie jar, get homepage
    if os.path.exists(JAR): os.remove(JAR)
    h=curl(['-c',JAR,'-L','https://www.voebb.de/'])
    m=re.search(r'<form action="([^"]+)"',h)
    ident=re.search(r'name="identity" value="([^"]*)"',h)
    req=re.search(r'name="requestCount" value="([^"]*)"',h)
    return h, m.group(1) if m else None, ident.group(1) if ident else None

def search(term, scope='Überall suchen', h=None, path=None, ident=None):
    if path is None:
        h,path,ident=new_session()
    base='https://www.voebb.de'+path
    loc=curl(['-b',JAR,'-c',JAR,'-o','/dev/null','-D','-','-e','https://www.voebb.de/','-X','POST',base,
        '--data-urlencode','identity='+ident,'--data-urlencode','keyCode=0','--data-urlencode','focus=',
        '--data-urlencode','stz=','--data-urlencode','source=','--data-urlencode','selected=',
        '--data-urlencode','requestCount=2','--data-urlencode','scriptEnabled=true','--data-urlencode','scrollPos=0',
        '--data-urlencode','THEMA2_1='+term,'--data-urlencode','THEMA1_1='+term,
        '--data-urlencode','SUCBER_1='+scope,'--data-urlencode','$Select='+scope,
        '--data-urlencode','$Autosuggest='+term,'--data-urlencode','$$GFBO_1=Suchen'])
    m=re.search(r'Location: (\S+)',loc)
    if not m:
        return {'term':term,'error':'no redirect','raw':loc[:400]}
    url=m.group(1)
    page=curl(['-b',JAR,'-c',JAR,url])
    return parse(page,term)

def parse(page,term):
    res={'term':term,'count':None,'items':[],'next':None}
    m=re.search(r'(\d[\d\.]*)\s*Treffer',re.sub('<[^>]+>',' ',page))
    if m: res['count']=m.group(1)
    for li in re.findall(r'<li class="rList_li.*?</li>',page,re.S):
        r={}
        t=re.search(r'<a href="([^"]+)" id="idfn\d+">(.*?)</a>',li,re.S)
        if not t: continue
        r['url']=html.unescape(t.group(1)); r['title']=html.unescape(re.sub('<[^>]+>','',t.group(2))).strip()
        ak=re.search(r'data-ajax="AK(\d+)"',li); r['ak']=ak.group(1) if ak else None
        av=re.search(r'rList_availability[^>]*>.*?alt="([^"]*)"',li,re.S); r['availability']=av.group(1) if av else None
        md=re.search(r'rList_medium[^>]*>.*?alt="([^"]*)"',li,re.S); r['medium']=md.group(1) if md else None
        nm=re.search(r'rList_name" style="width: 70%">(.*?)</div>',li,re.S)
        r['desc']=html.unescape(re.sub('<[^>]+>','',nm.group(1))).strip() if nm else None
        yr=re.search(r'rList_jahr" style="width: 18%">(.*?)</div>',li,re.S)
        r['year']=html.unescape(re.sub('<[^>]+>','',yr.group(1))).strip() if yr else None
        res['items'].append(r)
    return res

if __name__=='__main__':
    term=sys.argv[1]
    scope=sys.argv[2] if len(sys.argv)>2 else 'Überall suchen'
    out=search(term,scope)
    print(json.dumps(out,ensure_ascii=False,indent=1)[:6000])
