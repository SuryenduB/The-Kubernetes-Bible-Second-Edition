#!/usr/bin/env python3
"""Compare GDrive ebook inventory with NAS calibre library. Idempotent merge with state.json."""
import argparse, json, re, os, difflib
from collections import Counter

STOP = {'the','a','an','and','for','with','of','in','on','to','2nd','second','edition'}

def norm(s):
    s = s.lower()
    s = re.sub(r'z-?library\.sk.*', '', s)
    s = re.sub(r'1lib\.sk.*', '', s)
    s = re.sub(r'z-lib\.sk.*', '', s)
    s = re.sub(r'\(\d+\)', '', s)
    s = re.sub(r'\.(epub|pdf)$', '', s)
    s = re.sub(r'[^a-z0-9 ]', ' ', s)
    return re.sub(r'\s+', ' ', s).strip()

def sig(s):
    return set(w for w in norm(s).split() if len(w) > 2 and w not in STOP)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--gdrive', required=True)
    ap.add_argument('--nas-calibre', required=True)
    ap.add_argument('--nas-audio', required=True)
    ap.add_argument('--out-dir', required=True)
    a = ap.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)

    files = []
    for line in open(a.gdrive):
        line = line.strip()
        if line:
            files.extend(json.loads(line).get('files', []))
    books = [f for f in files
             if f.get('mimeType') in ('application/epub+zip', 'application/pdf')
             or f.get('name', '').lower().endswith(('.epub', '.pdf'))]

    nas_cal = open(a.nas_calibre).read()
    nas_files = re.findall(r'^(.+\.(epub|pdf))\s*$', nas_cal, re.M | re.I)
    nas_audio = [l.strip() for l in open(a.nas_audio) if l.strip()]
    nas_norms = [norm(n[0]) for n in nas_files] + [norm(x) for x in nas_audio]

    # load existing state to preserve progress
    sp = os.path.join(a.out_dir, 'state.json')
    old = json.load(open(sp)) if os.path.exists(sp) else {}

    missing, present = [], []
    for b in books:
        bs = sig(b['name'])
        hit = None
        for nn in nas_norms:
            ns = set(nn.split())
            if not bs:
                continue
            overlap = len(bs & ns) / max(1, len(bs))
            ratio = difflib.SequenceMatcher(None, norm(b['name']), nn).ratio()
            if overlap >= 0.6 or ratio > 0.75:
                hit = nn
                break
        (present if hit else missing).append((b, hit))

    state = {}
    for b, hit in present:
        prev = old.get(b['id'], {})
        state[b['id']] = {'name': b['name'], 'mimeType': b.get('mimeType', ''),
                          'createdTime': b.get('createdTime', ''),
                          'status': prev.get('status', 'skipped') if prev.get('status') in ('uploaded', 'verified') else 'skipped',
                          'nas_match': hit}
    for b, _ in missing:
        prev = old.get(b['id'], {})
        # keep terminal progress, else pending
        st = prev.get('status', 'pending') if prev.get('status') in ('pending', 'downloaded', 'uploaded', 'verified', 'failed') else 'pending'
        state[b['id']] = {'name': b['name'], 'mimeType': b.get('mimeType', ''),
                          'createdTime': b.get('createdTime', ''),
                          'status': st, 'attempts': prev.get('attempts', 0),
                          'local': prev.get('local', ''), 'error': prev.get('error', '')}

    with open(os.path.join(a.out_dir, 'missing.txt'), 'w') as f:
        for b, _ in sorted(missing, key=lambda x: x[0].get('createdTime', ''), reverse=True):
            f.write(f"{b['id']}\t{b['name']}\n")
    json.dump(state, open(sp, 'w'), indent=1)
    rep = (f"GDrive books: {len(books)} (pdf={sum(1 for b in books if b['name'].lower().endswith('.pdf'))}, "
           f"epub={sum(1 for b in books if b['name'].lower().endswith('.epub'))})\n"
           f"NAS calibre files: {len(nas_files)}, audio folders: {len(nas_audio)}\n"
           f"Present: {len(present)}, Missing: {len(missing)}\n"
           f"State: {dict(Counter(v['status'] for v in state.values()))}\n")
    open(os.path.join(a.out_dir, 'report.txt'), 'w').write(rep)
    print(rep)

if __name__ == '__main__':
    main()
