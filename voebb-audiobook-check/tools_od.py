"""Fetch + parse VÖBB OverDrive search results (server-rendered page embeds mediaItems JSON)."""
import re, json, urllib.parse, subprocess, time

UA = ('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36')
BASE = 'https://voebb.overdrive.com'

def get(url, retries=3):
    """Fetch via curl (system trust store; the bundled Python lacks CA certs)."""
    last = None
    for attempt in range(retries):
        p = subprocess.run(['curl', '-sSL', '--max-time', '45', '-A', UA,
                            '-H', 'Accept-Language: en-US,en;q=0.9', url],
                           capture_output=True)
        if p.returncode == 0 and p.stdout:
            return p.stdout.decode('utf-8', 'replace')
        last = RuntimeError(p.stderr.decode('utf-8', 'replace')[:200])
        time.sleep(1.5 * (attempt + 1))
    raise last

def media_items(html):
    out = {}
    for m in re.finditer(r'window\.OverDrive\.mediaItems\s*=\s*', html):
        i = html.index('{', m.end())
        try:
            obj, _ = json.JSONDecoder().raw_decode(html[i:])
        except Exception:
            continue
        if isinstance(obj, dict):
            out.update(obj)
    return out

def search(query, language=None, media_type=None, extra=None):
    params = {'query': query}
    if language:
        params['language'] = language
    if media_type:
        params['mediaType'] = media_type
    if extra:
        params.update(extra)
    url = BASE + '/search?' + urllib.parse.urlencode(params)
    html = get(url)
    title_m = re.search(r'<title>(.*?)</title>', html, re.S)
    page_title = title_m.group(1).strip() if title_m else ''
    if page_title.startswith('Error'):
        return {'url': url, 'error': page_title, 'items': {}}
    items = media_items(html)
    return {'url': url, 'title': page_title, 'items': items, 'html': html}

def summarize(it):
    creators = [c.get('name') for c in it.get('creators', []) if c.get('role') in ('Author', None)]
    langs = [l.get('name') for l in it.get('languages', [])]
    fmts = [f.get('name') for f in it.get('formats', [])]
    isbns = []
    for f in it.get('formats', []):
        if f.get('isbn'):
            isbns.append(f['isbn'])
    return {
        'id': it.get('id'),
        'title': it.get('title'),
        'sortTitle': it.get('sortTitle'),
        'subtitle': it.get('subtitle'),
        'creators': creators,
        'narrators': [c.get('name') for c in it.get('creators', []) if c.get('role') == 'Narrator'],
        'firstCreatorName': it.get('firstCreatorName'),
        'languages': langs,
        'formats': fmts,
        'type': (it.get('type') or {}).get('name'),
        'publisher': (it.get('publisher') or {}).get('name'),
        'publishDate': it.get('publishDateText'),
        'isOwned': it.get('isOwned'),
        'availableCopies': it.get('availableCopies'),
        'ownedCopies': it.get('ownedCopies'),
        'holdsCount': it.get('holdsCount'),
        'estimatedWaitDays': it.get('estimatedWaitDays'),
        'isHoldable': it.get('isHoldable'),
        'isbns': sorted(set(isbns)),
        'reserveId': it.get('reserveId'),
        'description': re.sub(r'<[^>]+>', ' ', it.get('description') or '')[:400],
    }

if __name__ == '__main__':
    import sys
    for q in sys.argv[1:]:
        r = search(q, language='en', media_type='audiobook')
        print('###', q, '->', r.get('url'), 'items:', len(r.get('items', {})))
        for it in r.get('items', {}).values():
            s = summarize(it)
            print('   -', s['title'], '|', s['firstCreatorName'], '|', s['languages'], '|', s['formats'], '| type', s['type'],
                  '| owned', s['isOwned'], 'avail', s['availableCopies'], 'holds', s['holdsCount'], 'wait', s['estimatedWaitDays'])
