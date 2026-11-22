#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
"""Batch OverDrive (VÖBB) search for the 64-book list. Saves raw JSON per book."""
import json, re, sys, time, urllib.parse, subprocess, os

BOOKS = [
 (1,"The Complete Plays","Joe Orton"),
 (2,"Things Fall Apart","Chinua Achebe"),
 (3,"Uncle Tom's Cabin","Harriet Beecher Stowe"),
 (4,"Gilead","Marilynne Robinson"),
 (5,"White Teeth","Zadie Smith"),
 (6,"Time Shelter","Georgi Gospodinov"),
 (7,"Do Androids Dream of Electric Sheep?","Philip K. Dick"),
 (8,"The Man in the High Castle","Philip K. Dick"),
 (9,"No Country for Old Men","Cormac McCarthy"),
 (10,"Midnight's Children","Salman Rushdie"),
 (11,"Waiting for the Barbarians","J. M. Coetzee"),
 (12,"Charlotte's Web","E. B. White"),
 (13,"Plainsong","Kent Haruf"),
 (14,"The Stand","Stephen King"),
 (15,"How to Change Your Mind: The New Science of Psychedelics","Michael Pollan"),
 (16,"The Bell Jar","Sylvia Plath"),
 (17,"The Amazing Adventures of Kavalier & Clay","Michael Chabon"),
 (18,"The Shining","Stephen King"),
 (19,"Middlesex","Jeffrey Eugenides"),
 (20,"Austerlitz","W. G. Sebald"),
 (21,"Zen and the Art of Motorcycle Maintenance: An Inquiry into Values","Robert M. Pirsig"),
 (22,"The Unbearable Lightness of Being","Milan Kundera"),
 (23,"A Confederacy of Dunces","John Kennedy Toole"),
 (24,"The Human Stain","Philip Roth"),
 (25,"The Whites","Richard Price"),
 (26,"Great Expectations","Charles Dickens"),
 (27,"Lullaby","Leïla Slimani"),
 (28,"Spring","Ali Smith"),
 (29,"Fear and Loathing in Las Vegas","Hunter S. Thompson"),
 (30,"Atonement","Ian McEwan"),
 (31,"We Need to Talk About Kevin","Lionel Shriver"),
 (32,"A Good Man Is Hard to Find and Other Stories","Flannery O'Connor"),
 (33,"Amsterdam","Ian McEwan"),
 (34,"American Pastoral","Philip Roth"),
 (35,"Knots & Crosses","Ian Rankin"),
 (36,"The Color Purple","Alice Walker"),
 (37,"The House of the Spirits","Isabel Allende"),
 (38,"The Joke","Milan Kundera"),
 (39,"Vernon Subutex 1","Virginie Despentes"),
 (40,"The Poisonwood Bible","Barbara Kingsolver"),
 (41,"Atomised","Michel Houellebecq"),
 (42,"Independence Day","Richard Ford"),
 (43,"The Glass Hotel","Emily St. John Mandel"),
 (44,"The Death of Ivan Ilyich and Other Stories","Leo Tolstoy"),
 (45,"The Waiter","Matias Faldbakken"),
 (46,"The History Boys","Alan Bennett"),
 (47,"The Woman Who Walked Into Doors","Roddy Doyle"),
 (48,"The Living Sea of Waking Dreams","Richard Flanagan"),
 (49,"The Watcher in the Shadows","Carlos Ruiz Zafón"),
 (50,"Everything Is Illuminated","Jonathan Safran Foer"),
 (51,"The Corrections","Jonathan Franzen"),
 (52,"The Narrow Road to the Deep North","Richard Flanagan"),
 (53,"Station Eleven","Emily St. John Mandel"),
 (54,"The Little Goblin Girl","Illy Hymen"),
 (55,"The Luminaries","Eleanor Catton"),
 (56,"Empire of the Sun","J. G. Ballard"),
 (57,"Notes from Underground","Fyodor Dostoevsky"),
 (58,"Celestial Bodies","Jokha Alharthi"),
 (59,"Freedom","Jonathan Franzen"),
 (60,"The Blind Assassin","Margaret Atwood"),
 (61,"Wolf Hall","Hilary Mantel"),
 (62,"The Sea","John Banville"),
 (63,"The Sense of an Ending","Julian Barnes"),
 (64,"The Dying Animal","Philip Roth"),
]

OUT='/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results/od_raw.json'

def fetch(url):
    return subprocess.run(['curl','-sL','--max-time','60','-A','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36',url],capture_output=True,text=True).stdout

def extract_media(h):
    marker='window.OverDrive.mediaItems = '
    i=h.find(marker)
    if i<0: return {}
    i+=len(marker)
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
                    except Exception: return {}
    return {}

def search(q):
    url='https://voebb.overdrive.com/search?query='+urllib.parse.quote(q)
    h=fetch(url)
    items=extract_media(h)
    m=re.search(r'Showing ([\d\-,]+) of ([\d,]+) results',h)
    return items,(m.group(2) if m else '?')

def slim(v):
    return {
      'title':v.get('title'),'subtitle':v.get('subtitle'),
      'author':', '.join(c['name'] for c in v.get('creators',[]) if c.get('role')=='Author'),
      'narrator':', '.join(c['name'] for c in v.get('creators',[]) if c.get('role')=='Narrator'),
      'type':(v.get('type') or {}).get('name'),
      'lang':','.join(l['id'] for l in v.get('languages',[])),
      'owned':v.get('isOwned'),'avail':v.get('isAvailable'),
      'copies':v.get('availableCopies'),'ownedCopies':v.get('ownedCopies'),
      'holds':v.get('holdsCount'),'holdable':v.get('isHoldable'),
      'edition':v.get('edition'),'publish':v.get('publishDateText'),
      'id':v.get('id'),'reserveId':v.get('reserveId'),
      'publisher':(v.get('publisher') or {}).get('name'),
      'isbn':[f.get('isbn') for f in (v.get('formats') or []) if f.get('isbn')][:3],
      'duration':[f.get('duration') for f in (v.get('formats') or []) if f.get('duration')][:2],
    }

def main():
    out=json.load(open(OUT)) if os.path.exists(OUT) else {}
    start=int(sys.argv[1]) if len(sys.argv)>1 else 1
    end=int(sys.argv[2]) if len(sys.argv)>2 else 999
    for n,title,author in BOOKS:
        if n<start or n>end: continue
        key=str(n)
        if key in out and out[key].get('done'): 
            print(n,'cached'); continue
        surname=author.split()[-1]
        title_clean=re.sub(r':.*$','',title)
        variants=[f'{title_clean} {surname}', title_clean, f'{surname} {title_clean}']
        if '?' in title_clean: variants.append(title_clean.replace('?',''))
        rec={'title':title,'author':author,'queries':{},'done':True}
        for q in variants:
            try:
                items,total=search(q)
            except Exception as e:
                rec['queries'][q]={'error':str(e)}; continue
            rec['queries'][q]={'total':total,'items':{k:slim(v) for k,v in items.items()}}
            time.sleep(1.2)
        out[key]=rec
        json.dump(out,open(OUT,'w'),ensure_ascii=False,indent=1)
        print(n,title,'| variants:',len(variants))
    print('saved',OUT)

if __name__=='__main__': main()
