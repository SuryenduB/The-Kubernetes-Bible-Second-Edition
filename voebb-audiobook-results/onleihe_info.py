#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""Fetch Onleihe mediaInfo details for candidate IDs."""
import subprocess, re, html, json, sys, time

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36'

def info(url):
    h=subprocess.run(['curl','-s','-A',UA,'--max-time','45',url],capture_output=True,text=True).stdout
    t=re.sub(r'<script.*?</script>','',h,flags=re.S)
    t=re.sub(r'<style.*?</style>','',t,flags=re.S)
    t=re.sub(r'<[^>]+>',' ',t); t=html.unescape(t); t=re.sub(r'\s+',' ',t)
    out={'url':url}
    for key,pat in [('titel',r'Titel: (.*?) Autor'),('autor',r'Autor\*in: (.*?) (?:Verlag|Jahr|Kategorie)'),
                    ('verlag',r'Verlag: (.*?) (?:Kategorie|Jahr|Dateigr|Sprache)'),
                    ('sprache',r'Sprache: (\w+)'),('format',r'Format: ([A-Za-z]+ ?[A-Za-z]*)'),
                    ('dauer',r'Dauer: (\d+) min'),
                    ('exemplare',r'(\d+) Exemplare (\d+) Verfügbar (\d+) Vormerker')]:
        m=re.search(pat,t)
        out[key]=m.groups() if m and m.groups() else (m.group(1) if m else None)
    m=re.search(r'(Verfügbar|Voraussichtlich verfügbar ab: [\d\.]+|Nicht verfügbar)',t)
    out['status']=m.group(1) if m else None
    out['borrow']= 'Jetzt ausleihen' in t
    out['hold']= 'Vormerker setzen' in t
    if out['format'] is None:
        out['format']='eAudio' if 'Dauer:' in t else None
    return out

if __name__=='__main__':
    for u in sys.argv[1:]:
        print(json.dumps(info(u),ensure_ascii=False))
        time.sleep(0.8)
