#!/usr/bin/env python3
"""Iteratively download missing GDrive ebooks and stage to NAS calibre-import. Crash-safe/idempotent."""
import argparse, json, os, subprocess, sys, re

NAS_IMPORT = '/share/Public/calibre-import'
NAS_HOST = 'admin@192.168.0.128'
SSH = ['sshpass', '-p', '558068', 'ssh', '-o', 'StrictHostKeyChecking=no']

def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)

def safe(name):
    return re.sub(r'[^\w.\- ]', '_', name).strip()[:150]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--state', required=True)
    ap.add_argument('--limit', type=int, default=10)
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--workdir', default=None,
                        help='Download dir (default: <state-dir>/downloads)')
    a = ap.parse_args()
    if not a.workdir:
        a.workdir = os.path.join(os.path.dirname(os.path.abspath(a.state)), 'downloads')
    os.makedirs(a.workdir, exist_ok=True)
    state = json.load(open(a.state))

    pending = [(fid, v) for fid, v in state.items() if v.get('status') in ('pending', 'failed')]
    pending.sort(key=lambda x: x[1].get('createdTime', ''), reverse=True)
    batch = pending[:a.limit]
    if not batch:
        print('NO_PENDING — all done or skipped')
        return

    def save():
        json.dump(state, open(a.state, 'w'), indent=1)

    for fid, meta in batch:
        name, local = meta['name'], os.path.join(a.workdir, f"{fid}_{safe(meta['name'])}")
        print(f'[{meta["status"]}] {name[:90]}')
        if a.dry_run:
            continue
        meta['attempts'] = meta.get('attempts', 0) + 1
        # 1. download (skip if already on disk)
        if not os.path.exists(local) or os.path.getsize(local) == 0:
            r = sh(['gws', 'drive', 'files', 'get',
                    '--params', json.dumps({'fileId': fid, 'alt': 'media'}),
                    '-o', local])
            if r.returncode != 0 or not os.path.exists(local):
                meta.update(status='failed', error=(r.stderr or r.stdout)[-300:])
                save()
                continue
        meta.update(status='downloaded', local=local)
        save()
        # 2. upload to NAS import staging
        r = sh(['sshpass', '-p', '558068', 'scp', '-o', 'StrictHostKeyChecking=no',
                local, f'{NAS_HOST}:{NAS_IMPORT}/'])
        if r.returncode != 0:
            meta.update(status='failed', error=(r.stderr or r.stdout)[-300:])
            save()
            continue
        # 3. verify remote exists (quote for spaces)
        base = os.path.basename(local)
        r = sh(SSH + [NAS_HOST, f'ls -l "{NAS_IMPORT}/{base}"'])
        meta.update(status='uploaded' if r.returncode == 0 else 'failed',
                    error='' if r.returncode == 0 else r.stderr[-300:])
        save()
    print('DONE_BATCH')

if __name__ == '__main__':
    sys.exit(main())
