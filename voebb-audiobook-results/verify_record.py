#!/usr/bin/env python3
"""Fetch full VÖBB OverDrive record data for evidence. Usage: verify_record.py <id> [<id> ...]

Prints the fields that drive the availability badge (isAvailable / availableCopies /
ownedCopies / holdsCount / isHoldable / estimatedWaitDays / edition / languages /
duration) plus title, author, narrator, publisher. Saves raw results to od_verify.json.

Human-facing record link for the same item: https://voebb.overdrive.com/media/<id>
"""
import json, os, subprocess, sys, time

UA = ('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 Chrome/124 Safari/537.36')
OUT = 'od_verify.json'


def fetch(mid):
    url = f'https://thunder.api.overdrive.com/v2/libraries/voebb/media/{mid}'
    for _ in range(3):
        p = subprocess.run(['curl', '-s', '-A', UA, '--max-time', '45', url],
                           capture_output=True, text=True)
        try:
            return json.loads(p.stdout)
        except Exception:
            time.sleep(2)
    return {'error': 'parse'}


def slim(d):
    return {
        'title': d.get('title'),
        'subtitle': d.get('subtitle'),
        'author': d.get('firstCreatorName'),
        'narrator': ', '.join(c['name'] for c in d.get('creators', [])
                              if c.get('role') == 'Narrator'),
        'type': (d.get('type') or {}).get('name'),
        'edition': d.get('edition'),
        'lang': [l['id'] for l in d.get('languages', [])],
        'isOwned': d.get('isOwned'),
        'isAvailable': d.get('isAvailable'),
        'availableCopies': d.get('availableCopies'),
        'ownedCopies': d.get('ownedCopies'),
        'holdsCount': d.get('holdsCount'),
        'isHoldable': d.get('isHoldable'),
        'estimatedWaitDays': d.get('estimatedWaitDays'),
        'publisher': (d.get('publisher') or {}).get('name'),
        'publishDate': d.get('publishDateText'),
        'duration': [f.get('duration') for f in (d.get('formats') or [])
                     if f.get('duration')][:1],
    }


def main():
    ids = sys.argv[1:]
    if not ids:
        print(__doc__)
        return
    out = json.load(open(OUT)) if os.path.exists(OUT) else {}
    for i in ids:
        out[i] = slim(fetch(i))
        v = out[i]
        print(f"{i} | {v['title']} | {v['author']} | {v['type']} | ed={v['edition']} | "
              f"avail={v['isAvailable']} {v['availableCopies']}/{v['ownedCopies']} "
              f"holds={v['holdsCount']} holdable={v['isHoldable']} "
              f"wait={v['estimatedWaitDays']} | {v['narrator']} | {v['duration']}")
        time.sleep(1.0)
    json.dump(out, open(OUT, 'w'), ensure_ascii=False, indent=1)
    print('saved', OUT)


if __name__ == '__main__':
    main()
