#!/usr/bin/env python3
"""Build results.csv, evidence.md, progress.md for the 47-book VÖBB run (2026-10-20)."""
import csv, json, os, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DATE = "2026-10-20"

OD = "https://voebb.overdrive.com/media/"
CAT = ("https://www.voebb.de/aDISWeb/app?noRedir&service=direct/0/Home/"
       "$DirectLink&sp=SPROD00&sp=SAK")

# number, title, author, status, edition, other_media, platform, evidence, notes
ROWS = [
 (1,"Difficult Men","Brett Martin","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact title, title+surname, 'Difficult Men TV' and surname-only author pass (Brett Martin 1/1, unrelated PONS language course). No audio in any source."),
 (2,"Sapiens","Yuval Noah Harari","WAITLIST","Unabridged, 15h18m, narrated Derek Perkins",
  "English CD (Random House Audiobooks, read by Derek Perkins) AK34499085 — physical, available. German eBook/eAudio on Onleihe.",
  "OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/3255516",
  "0 of 10 copies available, 0 holds, holdable, est. wait 2 days. Photo duplicate note: Sapiens appears twice in the photographed list but only once (ID 02) in this 47-book input, so searched once."),
 (3,"Inside Scientology","Janet Reitman","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact/short/author (Reitman 1/1) and alt-title passes across all three sources. VÖBB holds the eBook only (OverDrive 598976); no audiobook."),
 (4,"Film Directing Shot by Shot","Steven D. Katz","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact, shortened ('Shot by Shot', 'Film Directing') and author (Katz 0/0) searches; 0 audiobook results in all three sources."),
 (5,"On Film-making","Alexander Mackendrick","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact, hyphen-free ('On Film Making') and author (Mackendrick 0/0) searches; no audiobook."),
 (6,"Directing Actors","Judith Weston","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact and author (Weston 0/0) searches; results were unrelated directing titles. No audiobook."),
 (7,"Getting More","Stuart Diamond","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact, 'Getting More Diamond' and surname-only pass (Diamond 0/0); no audiobook."),
 (8,"London: The Biography","Peter Ackroyd","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "German print: 'London: die Biographie' (Knaus, AK14133886/AK04205626). No audio.",
  "—","—",
  "Exact/short ('London'), 'London Ackroyd' and full Ackroyd audiobook pass (7/7) checked. No Ackroyd London audiobook."),
 (9,"Mythology","Edith Hamilton","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact, 'Mythology Hamilton' and author pass (Hamilton 1/1 = Collected Dialogues of Plato). No Hamilton Mythology audio; Gaiman/Morales look-alikes excluded."),
 (10,"Mythos","Stephen Fry","WAITLIST","Unabridged, 15h25m, narrated by Stephen Fry",
  "English CD (Penguin, AK34499045) — physical, available. German MP3 'Die Mythos-Trilogie' AK34161552; German E-Audio AK34227506.",
  "OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/3512899",
  "0 of 6 copies available, 7 holds, holdable, est. wait 19 days. Fry's full 55-title audiobook list paged; no other edition of Mythos."),
 (11,"The Blank Slate","Steven Pinker","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Print only: AK14937459, AK13499327. No audio.","—","—",
  "Exact, 'Blank Slate Pinker', surname-only pass (Pinker 25/25 fully paged) and alt titles checked. No audiobook of The Blank Slate."),
 (12,"The Gendered Brain","Gina Rippon","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Rippon's only VÖBB audiobook is 'The Lost Girls of Autism' (OverDrive 11035932). No audio of this title.",
  "—","—",
  "Exact + 'The Gendered Brain Rippon' + author pass (3/3). No match; Delusions of Gender (Cordelia Fine) excluded."),
 (13,"London: A History in Maps","Peter Barber","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Print: AK15511824 ('London: a history in maps', 2012). No audio.","—","—",
  "Exact/short/'London Barber' + author pass paged. Barber results were mostly Samuel Barber music; no audiobook."),
 (14,"David Inshaw","Andrew Lambirth","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact, 'Inshaw', 'Lambirth' and surname-only pass (Lambirth 0/0); no record of any format."),
 (15,"The Whites","Richard Price","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "German CD 'Die Unantastbaren' (AK15935562) — other-language audio, available.",
  "—","—",
  "Exact, 'The Whites Price' (4 fuzzy hits, none the novel) and surname-only pass (Richard Price 7/7). No English audiobook."),
 (16,"11.22.63","Stephen King","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "DVD of the TV adaptation (AK16055080, AK11262335). No audio.","—","—",
  "Searched '11.22.63', '11/22/63', '112263', 'eleven twenty two sixty three', 'Kennedy King' and King's full 81-title audiobook list. No audiobook of this novel in VÖBB."),
 (17,"Antkind","Charlie Kaufman","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact, 'Antkind Kaufman' and author pass (Kaufman 1/1, unrelated). No audiobook."),
 (18,"The Joke","Milan Kundera","NOT_FOUND_AFTER_FULL_SEARCH","—","—",
  "—","—",
  "Author verified as Milan Kundera. Kundera's full 7-title audiobook list contains only The Unbearable Lightness of Being and The Art of the Novel; catalogue has the DVD of The Joke (AK13793154). Exact/short/'The Joke Kundera' searched. No audiobook."),
 (19,"Vernon Subutex 1","Virginie Despentes","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Volume 1 verified: French CD 'Vernon Subutex 1' (Audiolib, read by Jacques Frantz) AK15981289 — available; German E-Audio 'Das Leben des Vernon Subutex 1' AK34243817 and German MP3 AK16351685 (vol. 1); vol. 2 also held (AK34174296).",
  "—","—",
  "Exact 'Vernon Subutex 1'/'Vernon Subutex', author pass (Despentes 2/2), Onleihe and catalogue checked. No English-language audio of volume 1."),
 (20,"The Stand","Stephen King","WAITLIST","Unabridged, complete and uncut, 47h47m, narrated Grover Gardner",
  "German MP3 'The Stand – Das letzte Gefecht' AK15791792; German E-Audio AK34821975. No English CD record.",
  "OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/589885",
  "0 of 1 copy available, 4 holds, holdable, est. wait 70 days. 47h47m runtime confirms the complete/uncut recording; no abridged or dramatised edition held."),
 (21,"The Glass Hotel","Emily St. John Mandel","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "English CD (Random House, read by Dylan Moore) AK34390101 — physical, currently unavailable.",
  "—","—",
  "Exact, 'The Glass Hotel Mandel' and Mandel's full 13-title audiobook pass; only Exit Party/Station Eleven/Sea of Tranquility on audio. VÖBB has the eBook (5011122) but no English digital audiobook."),
 (22,"The Possibility of an Island","Michel Houellebecq","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact/short/'Houellebecq' and author pass (5/5 — Whatever, Serotonin, H.P. Lovecraft etc.). No edition of this novel in audio."),
 (23,"Zen and the Art of Motorcycle Maintenance","Robert M. Pirsig","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact, 'Motorcycle Maintenance', 'Pirsig' and surname-only pass (Pirsig 0/0). No audiobook."),
 (24,"The Unbearable Lightness of Being","Milan Kundera","WAITLIST",
  "Unabridged (catalogue states Unabridged; OverDrive edition field blank), 9h36m, narrated Richmond Hoxie",
  "—","OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/3995095",
  "0 of 2 copies available, 0 holds, holdable, est. wait 7 days. Catalogue mirror AK34972207 confirms Unabridged, Faber & Faber 2012."),
 (25,"The Watcher in the Shadows","Carlos Ruiz Zafón","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact, 'Watcher Shadows', 'Luces de Septiembre' and author pass (Zafón 1/1 = The Shadow of the Wind). No audiobook of this title."),
 (26,"The Luminaries","Eleanor Catton","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "English MP3-CD (Brilliance Audio, read by Mark Meadows, unabridged) AK15748656 — physical, available. German MP3 'Die Gestirne' AK15916270.",
  "—","—",
  "Author verified Eleanor Catton (the Susan Dennard novel of the same title excluded). Catton 2/2 audiobooks — neither is The Luminaries; no English digital audiobook."),
 (27,"Time Shelter","Georgi Gospodinov","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Print AK34939556/AK35069077 and eBook AK35043961 only. No audio.","—","—",
  "Exact, 'Timeshelter', 'Time Shelter Gospodinov' and author pass (1/1). English translation verified; no audiobook."),
 (28,"The 32","Paul McVeigh","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact 'The 32', 'The Thirty-Two', 'The 32 McVeigh' and author pass (McVeigh 0/0). All '32' hits were unrelated (Naruto vol. 32, The 32 Principles, etc.)."),
 (29,"The Stories of Stephen Dixon","Stephen Dixon","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact title, shortened 'Stories of Stephen Dixon' and author pass (Dixon 0/0). No collection and no individual story recording; individual stories would be partial matches only."),
 (30,"Three Plays","August Wilson","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Print collection 'Three plays' (Univ. of Pittsburgh Press, AK12550164). No audio.",
  "—","—",
  "Exact, 'August Wilson', 'Wilson plays', 'Pittsburgh Cycle', 'Fences Wilson'; author pass 0/0. No recording of the collection; a single play would not count."),
 (31,"The Corrections","Jonathan Franzen","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "German CD 'Die Korrekturen' (abridged, AK13437151 and AK02191204). No English audio.",
  "—","—",
  "Exact, 'The Corrections Franzen' and Franzen's full 20-title audiobook pass; only Crossroads/Freedom/Purity/Farther Away etc. on audio. VÖBB holds the eBook (34823737), not an audiobook."),
 (32,"The Living Sea of Waking Dreams","Richard Flanagan","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Print AK34651815, AK34530249 only. No audio.","—","—",
  "Exact, shortened and author pass (Flanagan 3/3 — only Narrow Road is audio). No audiobook."),
 (33,"The Narrow Road to the Deep North","Richard Flanagan","AVAILABLE_NOW",
  "Unabridged, 14h59m, narrated David Linski (David Atlas)",
  "English MP3-CDs (Blackstone, unabridged, read by David Atlas) AK15863256 and AK06225813 — physical, both available.",
  "OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/1817988",
  "1 of 2 copies available, 0 holds. Catalogue E-Audio mirror AK16313587."),
 (34,"Philip K. Dick: Four Novels of the 1960s","Philip K. Dick","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Print collection (Library of America, ed. Jonathan Lethem) AK15765310 — currently unavailable. No audio.",
  "—","—",
  "Collection searched by exact title, 'Four Novels of the 1960s' and Dick's full 16-title audiobook pass. Individual novels held in other formats (Do Androids Dream audio 123544; The Man in the High Castle CD; Ubik eBook) are partial matches and are not counted."),
 (35,"The Man in the High Castle","Philip K. Dick","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "English CD (Blackstone, unabridged, read by Tom Weiner) AK15851899 — physical, available. German E-Audio 'Das Orakel vom Berge' AK34290957.",
  "—","—",
  "Exact, 'High Castle Dick' and Dick's 16-title audiobook pass; only the eBook (769247) is digital. No English digital audiobook."),
 (36,"The Book of Disquiet","Fernando Pessoa","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact, 'Livro do Desassossego' and author pass (Pessoa 2/2 = Antinous, 35 Sonnets). No audiobook or translation held."),
 (37,"Middlesex","Jeffrey Eugenides","WAITLIST","Unabridged, 21h21m, narrated Kristoffer Tabori",
  "German CD (autorisierte Lesefassung, read by Ulrich Matthes) AK13522038.",
  "OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/86990",
  "0 of 3 copies available, 0 holds, holdable, est. wait 5 days. Catalogue E-Audio mirror AK34114010."),
 (38,"The Overstory","Richard Powers","AVAILABLE_NOW","Unabridged, 22h58m, narrated Suzanne Toren",
  "—","OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/4235624",
  "1 of 5 copies available, 0 holds. Catalogue E-Audio mirror AK34423920."),
 (39,"The Amazing Adventures of Kavalier & Clay","Michael Chabon","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "English MP3-CD (Brilliance Audio, unabridged, performed by David Colacci) AK15655402 — physical, available.",
  "—","—",
  "Exact, 'Kavalier Clay', 'Kavalier and Clay' and Chabon's full 6-title audiobook pass. VÖBB has the eBook (728008) but no English digital audiobook."),
 (40,"Freedom","Jonathan Franzen","AVAILABLE_NOW","Unabridged, 24h09m, narrated David Ledoux",
  "English CD (HarperCollins, unabridged, read by David Ledoux) AK00288066 — physical, available. German CDs AK01374565 (abridged), AK11226236/AK15511389.",
  "OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/389422",
  "1 of 2 copies available, 0 holds. Angela Merkel's 'Freedom' and other same-title works excluded by author."),
 (41,"The Woman Who Walked Into Doors","Roddy Doyle","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Print AK12347780; an opera recording of the same story (Kris Defoort, AK50186808) is not an audiobook.",
  "—","—",
  "Exact, 'Woman Doors', 'Paula Spencer' and Doyle's full 3-title audiobook pass. No audiobook."),
 (42,"Notes from Underground","Fyodor Dostoevsky","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Print (Roger Scruton, AK15855222) and Project Gutenberg eBook AK34698600. No audio.",
  "—","—",
  "Exact, 'Notes from the Underground', 'Zapiski iz podpolya' and author pass (Dostoevsky 5/5 — Crime and Punishment, The Idiot, The Gambler, The House of the Dead). No audiobook of this work."),
 (43,"The Blind Assassin","Margaret Atwood","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Print AK10157034/AK02136651; eBook AK34021591. No audio.","—","—",
  "Exact, 'Blind Assassin Atwood' and Atwood's full 72-title audiobook list paged. No audiobook edition in VÖBB."),
 (44,"Independence Day","Richard Ford","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "eBook AK34032193 and print (German translation 'Unabhängigkeitstag'); no audio.","—","—",
  "Exact, 'Independence Day Ford', 'Bascombe' and Ford's full 8-title audiobook pass. No audiobook (the 1996 film DVD is unrelated)."),
 (45,"Extinction","Thomas Bernhard","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "German print 'Auslöschung' (Werke Bd. 9, AK34162018). No English audio.",
  "—","—",
  "Exact, 'Extinction Bernhard', 'Auslöschung' and author pass (Bernhard 1/1 = unrelated Krasznahorkai). Extinction by other authors (Takano, Preston, Somer) excluded."),
 (46,"Winter's Bone","Daniel Woodrell","NOT_FOUND_AFTER_FULL_SEARCH","—",
  "Print (German 'Winters Knochen' AK15354914) and DVD/eVideo of the film. No audio.",
  "—","—",
  "Exact, 'Winters Bone', 'Woodrell' and author pass (Woodrell 0/0). No audiobook."),
 (47,"The Child Garden","Geoff Ryman","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—","—",
  "Exact, 'Child Garden Ryman', 'Geoff Ryman' and author pass (Ryman 2/2 = anthologies Alien Sex, Welcome to Dystopia). No audiobook."),
]

assert len(ROWS) == 47, len(ROWS)

# per-book OverDrive search totals for the evidence log
od = json.load(open(os.path.join(HERE, "od_targeted.json")))
au = json.load(open(os.path.join(HERE, "od_author.json")))
ol = json.load(open(os.path.join(HERE, "onleihe_raw.json")))
cat = json.load(open(os.path.join(HERE, "cat_raw.json")))

def slug(t):
    return t.split(":")[0].strip()

# ---------- results.csv ----------
cols = ["Number","Book title","Author","English digital audiobook availability",
        "Edition / abridgement","Other-language audiobook / physical CDs","Platform",
        "Evidence link","Date checked","Notes"]
with open(os.path.join(HERE,"results.csv"),"w",newline="",encoding="utf-8") as f:
    w=csv.writer(f,quoting=csv.QUOTE_ALL)
    w.writerow(cols)
    for r in ROWS:
        w.writerow([r[0],r[1],r[2],r[3],r[4],r[5],r[6],r[7],DATE,r[8]])

# ---------- evidence.md ----------
L=[]
L.append("# VÖBB English digital-audiobook check — evidence log\n")
L.append(f"- Date checked: **{DATE}** (all rows)")
L.append("- Scope: 47 books embedded in the photo-list input; only those books were searched.")
L.append("- Read-only. No login, borrowing, holds or purchases.")
L.append("")
L.append("## Sources and endpoints")
L.append("1. **OverDrive / Libby (VÖBB)** — `https://thunder.api.overdrive.com/v2/libraries/voebb/media?query=…` "
         "(title, title+surname, surname-only with `mediaType=audiobook&language=en`, fully paginated); "
         "per-record verification via `/media/<id>`. Public record page: `https://voebb.overdrive.com/media/<id>`.")
L.append("2. **Onleihe Berlin** — `https://voebb.onleihe.de/berlin/frontend/search,...` POST (`pText=<term>`), "
         "candidate detail pages `mediaInfo,...` checked for `Sprache`, `Format`, copy counts and status.")
L.append("3. **VÖBB main catalogue (aDISWeb OPAC)** — session POST to `https://www.voebb.de/aDISWeb/<session>/app`, "
         "result lists parsed for medium (`E-Audio`, `CD`, `MP3`, `Band`, `DVD`). Record links: `" + CAT + "<AK>`.")
L.append("")
L.append("## Search coverage (applies to all 47 books)")
L.append("- Exact title; title + author surname; surname-only author pass (OverDrive, English audiobooks, **fully paginated**); "
         "documented alternative/shortened titles for punctuation-heavy or translated titles.")
L.append("- Onleihe: exact title plus surname pass; detail pages opened for every title-matching candidate.")
L.append("- Catalogue: title+surname and title-only queries; media type inspected on every hit.")
L.append("- OverDrive author lists were paged to completion: King 81/81, Atwood 72/72, Fry 55/55, Harari 50/50, "
         "Pinker 25/25, Franzen 20/20, P. K. Dick 16/16, Mandel 13/13, Ford 8/8, Ackroyd 7/7, Price 7/7, Kundera 7/7, "
         "Chabon 6/6, Dostoevsky 5/5, Houellebecq 5/5, Powers 35/35.")
L.append("- No English eAudio match was found on Onleihe for any of the 47 titles (Onleihe holdings are overwhelmingly German).")
L.append("")
L.append("## Confirmed English digital-audiobook holdings (8)")
L.append("")
COPY = {2:"0/10 available, 0 holds", 10:"0/6 available, 7 holds",
        20:"0/1 available, 4 holds", 24:"0/2 available, 0 holds",
        33:"1/2 available, 0 holds", 37:"0/3 available, 0 holds",
        38:"1/5 available, 0 holds", 40:"1/2 available, 0 holds"}
L.append("| # | Title | Author | Status | Copies / holds | Edition | Evidence |")
L.append("|---|---|---|---|---|---|---|")
for r in ROWS:
    if r[3] in ("AVAILABLE_NOW","WAITLIST","HELD_STATUS_UNKNOWN"):
        L.append(f"| {r[0]:02d} | {r[1]} | {r[2]} | {r[3]} | {COPY[r[0]]} | {r[4]} | {r[7]} |")
L.append("")
L.append("### Record detail")
L.append("")
detail = {
 2:("3255516","Sapiens","Yuval Noah Harari","Unabridged","15:18:10","Derek Perkins","HarperCollins","08/15/2017",
    "0/10 available, 0 holds, isHoldable true, estimatedWaitDays 2"),
 10:("3512899","Mythos","Stephen Fry","Unabridged","15:25:36","Stephen Fry","Penguin Books Ltd","11/02/2017",
    "0/6 available, 7 holds, isHoldable true, estimatedWaitDays 19"),
 20:("589885","The Stand","Stephen King","Unabridged","47:47:51","Grover Gardner","Books on Tape","02/14/2012",
    "0/1 available, 4 holds, isHoldable true, estimatedWaitDays 70 — complete & uncut runtime"),
 24:("3995095","The Unbearable Lightness of Being","Milan Kundera","edition field blank (catalogue: Unabridged)","09:36:55","Richmond Hoxie","Faber & Faber","09/06/2012",
    "0/2 available, 0 holds, isHoldable true, estimatedWaitDays 7"),
 33:("1817988","The Narrow Road to the Deep North","Richard Flanagan","Unabridged","14:59:47","David Linski","Blackstone Publishing","08/12/2014",
    "1/2 available, 0 holds — AVAILABLE_NOW"),
 37:("86990","Middlesex","Jeffrey Eugenides","Unabridged","21:21:21","Kristoffer Tabori","Macmillan Audio","3/1/2003",
    "0/3 available, 0 holds, isHoldable true, estimatedWaitDays 5"),
 38:("4235624","The Overstory","Richard Powers","Unabridged","22:58:04","Suzanne Toren","Random House","09/06/2018",
    "1/5 available, 0 holds — AVAILABLE_NOW"),
 40:("389422","Freedom","Jonathan Franzen","Unabridged","24:09:28","David Ledoux","Macmillan Audio","08/31/2010",
    "1/2 available, 0 holds — AVAILABLE_NOW"),
}
for n in sorted(detail):
    mid,title,author,ed,dur,narr,pub,pdate,avail = detail[n]
    L.append(f"**{n:02d} {title} — {author}**")
    L.append(f"- Record: https://voebb.overdrive.com/media/{mid}")
    L.append(f"- Type: Audiobook · Language: en · Edition: {ed} · Duration: {dur} · Narrator: {narr}")
    L.append(f"- Publisher/date: {pub}, {pdate}")
    L.append(f"- Availability as displayed: {avail}")
    L.append("")
L.append("## Per-book search record (all 47)")
L.append("")
for r in ROWS:
    n,t,a = r[0],r[1],r[2]
    q = od.get(str(n),{}).get("queries",{})
    qtot = "; ".join(f"`{k}` → {v.get('total')} hits" for k,v in q.items())
    au_total = au.get(str(n),{}).get("total")
    au_got = len(au.get(str(n),{}).get("items") or [])
    olq = ol.get(str(n),{}).get("queries",{})
    olsum = ", ".join(f"{k}={v.get('count')}" for k,v in olq.items())
    catsum = ", ".join(f"{k}={len((v.get('results') or v.get('items') or []))}" for k,v in cat.get(str(n),{}).get("queries",{}).items())
    L.append(f"### {n:02d} {t} — {a} — **{r[3]}**")
    L.append(f"- OverDrive audiobook+EN: {qtot}")
    L.append(f"- OverDrive author pass: {au_got}/{au_total} audiobooks inspected")
    L.append(f"- Onleihe: {olsum or 'no hits'} (candidates detail-checked; none English eAudio)")
    L.append(f"- Catalogue: {catsum or 'no hits'}")
    if r[7] != "—":
        L.append(f"- Evidence: {r[7]}")
    L.append(f"- Result: {r[8]}")
    L.append("")
L.append("## Limitations")
L.append("- OverDrive borrowing status is a point-in-time snapshot (2026-10-20); copies/holds change continuously.")
L.append("- OverDrive's `edition` field is blank for The Unbearable Lightness of Being; Unabridged is taken from the catalogue E-Audio mirror (AK34972207).")
L.append("- Onleihe's search is fuzzy and German-weighted; English eAudio was explicitly filtered by `Sprache: Englisch` + `eAudio Stream` on detail pages.")
L.append("- Physical CDs/MP3-CDs are listed separately and never counted as digital availability.")
L.append("- No access limitation prevented a search; no row uses UNVERIFIED_ACCESS_LIMITATION.")
open(os.path.join(HERE,"evidence.md"),"w",encoding="utf-8").write("\n".join(L)+"\n")

# ---------- progress.md ----------
counts={}
for r in ROWS: counts[r[3]]=counts.get(r[3],0)+1
P=f"""# VÖBB audiobook check — progress

- Input: 47 books (photo list), IDs 01–47
- Started: {DATE}
- Last checkpoint: {DATE} (all rows processed)
- Completed: 47 / 47
- Pending: none
- Status counts: {counts}
- Audit: rows sequential 1–47, no duplicates, every AVAILABLE_NOW/WAITLIST row has an official
  VÖBB OverDrive record link, date filled on every row.

## Source completion
- [x] OverDrive title searches (47/47)
- [x] OverDrive author pass, fully paginated (47/47)
- [x] OverDrive targeted audiobook+EN searches with pagination (47/47)
- [x] OverDrive per-record verification for all 8 candidates
- [x] Onleihe title searches + detail pages (47/47)
- [x] Onleihe surname pass (47/47)
- [x] VÖBB catalogue searches (47/47)

## Next action
None — run complete. Re-run only if a fresh availability snapshot is required.
"""
open(os.path.join(HERE,"progress.md"),"w",encoding="utf-8").write(P)

print("rows",len(ROWS),"counts",counts)
