#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
import sys, json, re, urllib.parse, subprocess, html

def fetch(url):
    return subprocess.run(['curl','-sL','--max-time','45',url],capture_output=True,text=True).stdout

def extract_media(h):
    marker='window.OverDrive.mediaItems = '
    i=h.find(marker)
    if i<0: return {}
    i+=len(marker)
    # brace match
    depth=0; instr=False; esc=False
    for j in range(i,len(h)):
        c=h[j]
        if instr:
            if esc: esc=False
            elif c=='\\': esc=True
            elif c=='"': instr=False
        else:
            if c=='"': instr=True
            elif c=='{': depth+=1
            elif c=='}':
                depth-=1
                if depth==0:
                    try: return json.loads(h[i:j+1])
                    except Exception as e:
                        print('JSONERR',e,file=sys.stderr); return {}
    return {}

def search(q,page=1):
    url='https://voebb.overdrive.com/search?query='+urllib.parse.quote(q)
    if page>1: url+='&page='+str(page)
    h=fetch(url)
    items=extract_media(h)
    m=re.search(r'Showing ([\d\-]+) of ([\d,]+) results',h)
    return items, (m.group(0) if m else '')

if __name__=='__main__':
    q=sys.argv[1]
    items,count=search(q)
    print('QUERY:',q,'|',count,'| items:',len(items))
    for k,v in items.items():
        au=', '.join(c['name'] for c in v.get('creators',[]) if c.get('role')=='Author')
        lang=','.join(l['id'] for l in v.get('languages',[]))
        print(f"{v.get('title')} | {au} | {v.get('type',{}).get('name')} | lang={lang} | owned={v.get('isOwned')} avail={v.get('isAvailable')} copies={v.get('availableCopies')}/{v.get('ownedCopies')} holds={v.get('holdsCount')} holdable={v.get('isHoldable')} | ed={v.get('edition')} | id={v.get('id')} | {v.get('publishDateText')}")
