#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""Batch VÖBB main catalogue search for all 64 books."""
import sys, os, json, time, re
sys.path.insert(0,'/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results')
import importlib.util
spec=importlib.util.spec_from_file_location('vc','/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/voebb_cat.py')
vc=importlib.util.module_from_spec(spec); spec.loader.exec_module(vc)
from books47 import BOOKS

OUT='/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/cat_raw.json'

def run():
    out=json.load(open(OUT)) if os.path.exists(OUT) else {}
    start=int(sys.argv[1]) if len(sys.argv)>1 else 1
    end=int(sys.argv[2]) if len(sys.argv)>2 else 999
    h,path,ident=vc.new_session()
    for n,title,author in BOOKS:
        if n<start or n>end: continue
        k=str(n)
        if k in out and out[k].get('done'): print(n,'cached'); continue
        surname=author.split()[-1]
        tclean=re.sub(r':.*$','',title)
        rec={'title':title,'author':author,'queries':{},'done':True}
        for q in [f'{tclean} {surname}', tclean]:
            try:
                r=vc.search(q,h=h,path=path,ident=ident)
            except Exception as e:
                r={'error':str(e)}
            rec['queries'][q]=r
            time.sleep(0.4)
            # refresh session token each search (identity is one-shot)
            h,path,ident=vc.new_session()
            time.sleep(0.4)
        out[k]=rec
        json.dump(out,open(OUT,'w'),ensure_ascii=False,indent=1)
        print(n,title,'done',flush=True)
    print('saved',OUT)

if __name__=='__main__': run()
