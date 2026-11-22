#!/usr/bin/env python3
"""Supplementary OverDrive title searches (distinctive words, alt titles,
punctuation-free variants) for the 47-book list."""
import json, subprocess, sys, os, time, urllib.parse
HERE=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,HERE)
from od_api_batch import slim

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36'
OUT=os.path.join(HERE,'od_extra_titles.json')

EXTRA={
 1:['Difficult Men Martin','Brett Martin','Difficult Men TV'],
 2:['Harari','Sapiens brief history'],
 3:['Reitman','Scientology Reitman'],
 4:['Shot by Shot','Katz film directing','Film Directing'],
 5:['Mackendrick','On Film Making Mackendrick','Film-making'],
 6:['Weston directing','Directing Actors Weston'],
 7:['Diamond negotiating','Getting More Diamond'],
 8:['Ackroyd London','London biography Ackroyd','Thames Ackroyd'],
 9:['Edith Hamilton','Hamilton mythology'],
 10:['Fry Mythos','Stephen Fry Greek'],
 11:['Pinker','Blank Slate Pinker'],
 12:['Rippon','Gendered Brain Rippon'],
 13:['Barber maps','London maps Barber','History in Maps'],
 14:['Inshaw','Lambirth','David Inshaw Lambirth'],
 15:['Richard Price','The Whites Price','Whites novel Price'],
 16:['11/22/63','112263','Kennedy King','King Kennedy time'],
 17:['Kaufman Antkind','Antkind Kaufman'],
 18:['Kundera','The Joke Kundera','Zert'],
 19:['Despentes','Vernon Subutex','Subutex Despentes'],
 20:['The Stand King','Stand complete uncut'],
 21:['Mandel','Glass Hotel Mandel'],
 22:['Houellebecq','Possibility Island Houellebecq','La Possibilite'],
 23:['Pirsig','Motorcycle Maintenance','Zen motorcycle'],
 24:['Kundera','Unbearable Lightness','Nesnesitelna'],
 25:['Zafon','Watcher Shadows Zafon','Luces de Septiembre'],
 26:['Catton','The Luminaries Catton'],
 27:['Gospodinov','Time Shelter Gospodinov','Timeshelter'],
 28:['McVeigh','The 32 McVeigh','Thirty Two McVeigh'],
 29:['Stephen Dixon','Dixon stories','Stories of Stephen Dixon'],
 30:['August Wilson','Wilson plays','Pittsburgh Cycle','Fences Wilson'],
 31:['Franzen','The Corrections Franzen'],
 32:['Flanagan','Living Sea Waking Dreams','Living Sea Flanagan'],
 33:['Flanagan','Narrow Road Deep North','Narrow Road Flanagan'],
 34:['Philip K Dick','Four Novels 1960s','Dick four novels'],
 35:['Man in the High Castle','High Castle Dick'],
 36:['Pessoa','Book of Disquiet','Livro do Desassossego'],
 37:['Eugenides','Middlesex Eugenides'],
 38:['Powers','The Overstory Powers'],
 39:['Chabon','Kavalier Clay','Kavalier and Clay'],
 40:['Franzen','Freedom Franzen'],
 41:['Roddy Doyle','Woman Walked Into Doors','Paula Spencer'],
 42:['Dostoevsky','Notes from Underground','Zapiski iz podpolya'],
 43:['Atwood','Blind Assassin','Blind Assassin Atwood'],
 44:['Richard Ford','Independence Day Ford','Bascombe'],
 45:['Bernhard','Extinction Bernhard','Ausloschung'],
 46:['Woodrell','Winter Bone Woodrell','Winters Bone'],
 47:['Ryman','Child Garden Ryman','Geoff Ryman'],
}

def api(path):
    url='https://thunder.api.overdrive.com/v2/libraries/voebb/'+path
    for a in range(3):
        p=subprocess.run(['curl','-s','-A',UA,'--max-time','60',url],capture_output=True,text=True)
        try: return json.loads(p.stdout)
        except Exception: time.sleep(2)
    return {}

def search(q,page=1):
    return api('media?query='+urllib.parse.quote(q)+f'&limit=50&page={page}')

def run():
    out=json.load(open(OUT)) if os.path.exists(OUT) else {}
    for n in sorted(EXTRA):
        k=str(n)
        if k in out and out[k].get('done'): continue
        rec={'queries':{},'done':True}
        for q in EXTRA[n]:
            d=search(q)
            items=[slim(x) for x in d.get('items',[])] if 'items' in d else []
            page=1
            while d.get('totalItems',0)>len(items) and page<2:
                page+=1
                d2=search(q,page)
                if 'items' not in d2: break
                items+=[slim(x) for x in d2['items']]
            rec['queries'][q]={'total':d.get('totalItems'),'items':items}
            time.sleep(1.2)
        out[k]=rec
        json.dump(out,open(OUT,'w'),ensure_ascii=False,indent=1)
        print(n,'extra titles done',flush=True)
    print('saved',OUT)

if __name__=='__main__': run()
