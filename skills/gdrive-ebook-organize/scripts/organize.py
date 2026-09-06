#!/usr/bin/env python3
"""File loose GDrive ebooks into topic folders. Idempotent via plan.json (resume with --apply)."""
import argparse, json, os, re, subprocess, sys

DEFAULTS = {'cyber': '1WyNmzFzriT0mcEuY_BkT0DoVsg79Jpj-',
            'german': '1TixzFaypotPYmPbnFzPkJ5GGVxs2lvtf',
            'k8s': '12H6xX5Mfo8xlSO8wgVUiVRTtGrWCMQRb',
            'lit': '1Ygh_Y7bALZeDm_5GAeb6CZvhYZ621bml',
            'pers': '1UNBQGqflB4RBfnR9GUqyTdUaezvZq_Fo'}
for k, v in DEFAULTS.items():
    env = os.environ.get(f'GDRIVE_LIB_{k.upper()}')
    if env:
        DEFAULTS[k] = env

# (topic, [keywords]) — first match wins; keep specific folders before general ones
RULES = [
    ('pers', ['contract', 'driving license', 'employment', 'hello-fresh', 'photo', 'deployment',
              'getting started', 'antrag', 'resume', 'reisepass']),
    ('german', ['german', 'andre klein', 'andré klein', 'ferien', 'karneval', 'ahoi', 'palermo',
                'walzer', 'zürich', 'zurich', 'dresden', 'stuttgart', 'sylt', 'frankfurt', 'hamburg', 'wien', 'köln', 'koln']),
    ('k8s', ['kubernetes', 'cka', 'terraform', 'ansible', 'vmware', 'vsphere', 'veeam', 'powershell',
             'active directory', 'devops', 'bitbucket', 'github', 'linux command', 'azure',
             'cloud resume', 'zabbix', 'graph api']),
    ('cyber', ['copilot', 'defender', 'entra', 'sc-100', 'sc-200', 'sentinel', 'kql', 'xdr', 'siem',
               'zero trust', 'okta', 'identity', 'codex cli', 'claude code', 'vibe engineering',
               'cnapp', 'dspm', 'purview', 'pentest', 'forefront']),
    ('lit', ['dune', 'november 1918', 'infinity machine', 'history', 'biography', 'novel',
             'ruskin bond', 'hitchhiker', 'postwar', 'geetanjali', 'kiyosaki', 'malgudi', 'wild sheep']),
]

def gws_list(q, fields='files(id,name,mimeType,parents,createdTime,owners)'):
    r = subprocess.run(['gws', 'drive', 'files', 'list', '--params',
                        json.dumps({'pageSize': 200, 'fields': fields, 'q': q})],
                       capture_output=True, text=True)
    return json.loads(r.stdout[r.stdout.find('{'):]).get('files', [])

def topic_of(name):
    n = name.lower()
    for topic, kws in RULES:
        for kw in kws:
            if kw in n:
                return topic, kw
    return None, None

def build_plan(topic_ids):
    books = gws_list("(mimeType='application/epub+zip' or mimeType='application/pdf') and trashed=false")
    ids = set(topic_ids.values()) | {'1Rk649xSpWLBq2xNbYmIt3b20ZwbqdUms'}
    plan = []
    for b in books:
        if set(b.get('parents', [])) & ids:
            continue
        t, kw = topic_of(b['name'])
        mine = any(o.get('me') for o in b.get('owners', [])) if b.get('owners') else True
        plan.append({'id': b['id'], 'name': b['name'], 'parents': b.get('parents', []),
                     'topic': t, 'keyword': kw, 'unmovable': not mine,
                     'status': 'pending' if (t and mine) else 'skipped'})
    return plan

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--scan', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--out-dir', default=os.path.expanduser('~/.gdrive-organize'))
    for t in DEFAULTS:
        ap.add_argument(f'--folder-{t}', default=None)
    a = ap.parse_args()
    ids = {t: (getattr(a, f'folder_{t}') or DEFAULTS[t]) for t in DEFAULTS}
    os.makedirs(a.out_dir, exist_ok=True)
    pp = os.path.join(a.out_dir, 'plan.json')

    if a.scan or not os.path.exists(pp):
        plan = build_plan(ids)
        json.dump({'folders': ids, 'items': plan}, open(pp, 'w'), indent=1)
    else:
        saved = json.load(open(pp))
        plan, ids = saved['items'], saved.get('folders', ids)

    if a.scan or a.dry_run or not (a.apply):
        lines = []
        for it in plan:
            tag = 'UNMOVABLE(shared)' if it['unmovable'] else (it['topic'] or 'NO-RULE→leave')
            lines.append(f"[{it['status']}] {tag} :: {it['name'][:100]}")
        open(os.path.join(a.out_dir, 'plan.txt'), 'w').write('\n'.join(lines))
        print('\n'.join(lines))
        print(f"\npending={sum(1 for i in plan if i['status']=='pending')} "
              f"moved={sum(1 for i in plan if i['status']=='moved')} "
              f"skipped={sum(1 for i in plan if i['status']=='skipped')}")
        return

    # --apply
    def save():
        json.dump({'folders': ids, 'items': plan}, open(pp, 'w'), indent=1)
    for it in plan:
        if it['status'] != 'pending' or not it['topic'] or it['unmovable']:
            continue
        p = {'fileId': it['id'], 'addParents': ids[it['topic']]}
        if it['parents']:
            # remove first non-topic parent (usually Drive root)
            p['removeParents'] = it['parents'][0]
        r = subprocess.run(['gws', 'drive', 'files', 'update', '--params', json.dumps(p)],
                           capture_output=True, text=True)
        if r.returncode == 0:
            it['status'] = 'moved'
            print(f"MOVED → {it['topic']}: {it['name'][:80]}")
        else:
            it['status'] = 'failed'
            it['error'] = (r.stderr or r.stdout)[-200:]
            print(f"FAILED: {it['name'][:80]} :: {it['error'][-120:]}")
        save()
    print('DONE_BATCH')

if __name__ == '__main__':
    sys.exit(main())
