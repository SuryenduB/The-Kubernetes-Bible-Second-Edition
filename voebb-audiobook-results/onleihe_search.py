#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""Onleihe (VÖBB) search. POST search endpoint, parse media cards."""
import subprocess, re, html, json, sys, time, urllib.parse

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36'
URL='https://voebb.onleihe.de/berlin/frontend/search,0-0-0-0-0-0-0-0-0-0-0.html'

def search(term):
    out=subprocess.run(['curl','-s','-A',UA,'-X','POST',URL,
        '--data-urlencode','cmdId=703','--data-urlencode','sK=1000','--data-urlencode','pText='+term],
        capture_output=True,text=True).stdout
    page=out
    res={'term':term,'count':None,'items':[]}
    m=re.search(r'ergab ([\d\.]+) Titeltreffer',html.unescape(page))
    if m: res['count']=m.group(1)
    if 'keine Treffer' in page: res['count']='0'
    for card in re.split(r"test-id='mediaCard'",page)[1:]:
        c=card[:9000]
        t=re.search(r"test-id='cardTitle'>(.*?)</h3>",c,re.S)
        a=re.search(r"test-id='cardAuthor'>(.*?)</p>",c,re.S)
        link=re.search(r'href="(mediaInfo,[^"]+)"',c)
        icons=re.findall(r'<svg class="icon (ic_[a-z0-9]+)',c)
        genre=re.search(r"test-id='cardSubTitle'>(.*?)</h4>",c,re.S)
        abl=re.search(r"test-id='cardLabelAvailability'>(.*?)</b>",c,re.S)
        abv=re.search(r"test-id='cardAvailability'>(.*?)</span>",c,re.S)
        btn=re.search(r'<a href="mediaInfo[^"]*"[^>]*test-id=.setMarkerButton.[^>]*>(.*?)</a>',c,re.S)
        btn2=re.search(r'class="btn btn-primary[^"]*"[^>]*>(.*?)</a>',c,re.S)
        avtxt=None
        if abv:
            avtxt=((html.unescape(re.sub('<[^>]+>','',abl.group(1)).strip())+' ') if abl else '')+html.unescape(re.sub('<[^>]+>','',abv.group(1))).strip()
        res['items'].append({
          'title':html.unescape(re.sub('<[^>]+>','',t.group(1))).strip() if t else None,
          'author':html.unescape(re.sub('<[^>]+>','',a.group(1))).strip() if a else None,
          'subtitle':html.unescape(re.sub('<[^>]+>','',genre.group(1))).strip() if genre else None,
          'icons':icons,
          'link':'https://voebb.onleihe.de/berlin/frontend/'+link.group(1) if link else None,
          'avail_text':avtxt,
          'button':html.unescape(re.sub('<[^>]+>','',(btn or btn2).group(1))).strip() if (btn or btn2) else None,
        })
    return res

if __name__=='__main__':
    for term in sys.argv[1:]:
        r=search(term)
        print(json.dumps(r,ensure_ascii=False,indent=1)[:4000])
