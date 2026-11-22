#!/usr/bin/env python3
# ============================================================
# voebb-audiobook-search skill — reference script
# Runtime layout: copy all scripts into ONE working directory
# (they default to /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/voebb-audiobook-results) and run them there; JSON outputs are
# written next to the scripts. See ../SKILL.md for the full
# workflow. Read-only public endpoints; no login required.
# ============================================================
# -*- coding: utf-8 -*-
"""Write final results.csv with correct CSV quoting."""
import csv, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else 'results.csv'

HEADER = ["Number","Book title","Author","English digital audiobook availability",
          "Other-language audiobook / physical CDs","Platform","Evidence link","Date checked","Notes"]

R = []
def row(n,t,a,st,other,plat,link,notes):
    R.append([str(n),t,a,st,other,plat,link,"2026-10-20",notes])

row(1,"The Complete Plays","Joe Orton","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook. OverDrive: 0 hits for author, exact title and individual plays (Loot; What the Butler Saw). Onleihe: none. Catalogue: no Orton audio (only other authors' 'Complete plays' and a Shakespeare CD set). Individual plays treated as partial only — none found.")
row(2,"Things Fall Apart","Chinua Achebe","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook. OverDrive: eBook only (0/2 copies; 3 holds). Onleihe: none. Catalogue: no audiobook.")
row(3,"Uncle Tom's Cabin","Harriet Beecher Stowe","AVAILABLE_NOW",
    "German CD (Onkel Toms Hütte – Hörmedia-Audioverl. 2007)","Onleihe (VÖBB)",
    "https://voebb.onleihe.de/berlin/frontend/mediaInfo,0-0-363593406-200-0-0-0-0-0-0-0.html",
    "English eAudio (Literizon, eAudio Stream), 1 copy / 1 available / 0 holds – 'Jetzt ausleihen'. OverDrive: none.")
row(4,"Gilead","Marilynne Robinson","WAITLIST","German CD (Argon 2016 ungekürzte Lesung)",
    "OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/335520",
    "Unabridged 8h55m (Tim Jerome). 0/2 copies; 4 holds – wait list.")
row(5,"White Teeth","Zadie Smith","WAITLIST","—","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/3886722",
    "Unabridged 18h38m. 0/2 copies; 2 holds – wait list.")
row(6,"Time Shelter","Georgi Gospodinov","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook. OverDrive: eBook only (0/2; 2 holds). Also searched 'Timeshelter'. Onleihe/catalogue: no audiobook.")
row(7,"Do Androids Dream of Electric Sheep?","Philip K. Dick","WAITLIST","—","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/123544",
    "Unabridged 9h12m (Scott Brick). 0/1 copy; 3 holds – wait list. Catalogue also lists the 'Blade Runner' film tie-in E-Audio of the same novel.")
row(8,"The Man in the High Castle","Philip K. Dick","NOT_FOUND_AFTER_FULL_SEARCH",
    "English CD (Blackstone, read by Tom Weiner, unabridged — available) + German E-Audio (Das Orakel vom Berge, Argon)",
    "—","—","No digital audiobook in OverDrive/Onleihe; only the English CD (physical) and German E-Audio are held.")
row(9,"No Country for Old Men","Cormac McCarthy","NOT_FOUND_AFTER_FULL_SEARCH",
    "English CD (Recorded Books, read by Tom Stechschulte, unabridged — available)","—","—",
    "No digital audiobook in OverDrive/Onleihe; only the English CD (physical) is held.")
row(10,"Midnight's Children","Salman Rushdie","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook in any source (exact/shortened/author searches).")
row(11,"Waiting for the Barbarians","J. M. Coetzee","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook. No Coetzee audiobook owned in VÖBB OverDrive; catalogue has only the film DVD.")
row(12,"Charlotte's Web","E. B. White","NOT_FOUND_AFTER_FULL_SEARCH",
    "English CD (read by the author, Listening Library, unabridged — currently not available)","—","—",
    "No digital audiobook; eBook owned (0/2). CD exists in the catalogue but is 'Zurzeit nicht verfügbar'.")
row(13,"Plainsong","Kent Haruf","NOT_FOUND_AFTER_FULL_SEARCH",
    "German eAudio (Das Band, das uns hält — Onleihe)","—","—",
    "No English audiobook in any source; only the German Onleihe eAudio and print/eBook editions.")
row(14,"The Stand","Stephen King","WAITLIST","German E-Audio (Das letzte Gefecht — Lübbe 2014)",
    "OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/589885",
    "Complete & uncut edition (unabridged 47h47m, Grover Gardner). 0/1 copy; 4 holds – wait list. Edition checked: no English abridged/dramatised audiobook owned.")
row(15,"How to Change Your Mind: The New Science of Psychedelics","Michael Pollan","WAITLIST","—",
    "OverDrive/Libby (VÖBB)","https://voebb.overdrive.com/media/3619131",
    "Two English editions owned, both 0 copies: 0/1 with 1 hold (Books on Tape, 13h35m); 0/3 with 0 holds (Penguin, 13h41m) – wait list.")
row(16,"The Bell Jar","Sylvia Plath","WAITLIST","—","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/4554951",
    "Unabridged 7h25m (Maggie Gyllenhaal). 0/4 copies; 6 holds – wait list. Caveat: the source photo partly obscured the title; title identified as The Bell Jar (Sylvia Plath).")
row(17,"The Amazing Adventures of Kavalier & Clay","Michael Chabon","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No audiobook owned; only the eBook edition (with bonus content).")
row(18,"The Shining","Stephen King","WAITLIST",
    "English CD (Simon & Schuster 2005, read by Campbell Scott — available)","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/858758",
    "Unabridged 15h50m (Campbell Scott). 0/1 copy; 4 holds – wait list.")
row(19,"Middlesex","Jeffrey Eugenides","WAITLIST",
    "German CD (Der Hörverlag 2003, Ulrich Matthes) + German eBook (Onleihe)","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/86990",
    "Unabridged 21h21m (Kristoffer Tabori). 0/3 copies; 0 holds (hold option shown) – wait list.")
row(20,"Austerlitz","W. G. Sebald","NOT_FOUND_AFTER_FULL_SEARCH",
    "German E-Audio + German CDs (Der Hörverlag)","—","—",
    "No English audiobook; only German audio editions are held.")
row(21,"Zen and the Art of Motorcycle Maintenance: An Inquiry into Values","Robert M. Pirsig","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook in any source (exact/shortened/author searches).")
row(22,"The Unbearable Lightness of Being","Milan Kundera","WAITLIST","—","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/3995095",
    "9h36m (Richmond Hoxie; abridged/unabridged not stated in record). 0/2 copies; 0 holds (hold option) – wait list.")
row(23,"A Confederacy of Dunces","John Kennedy Toole","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No audiobook; eBook only (0/1).")
row(24,"The Human Stain","Philip Roth","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook; catalogue has only the film DVD.")
row(25,"The Whites","Richard Price","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook in any source.")
row(26,"Great Expectations","Charles Dickens","AVAILABLE_NOW","—","Onleihe (VÖBB)",
    "https://voebb.onleihe.de/berlin/frontend/mediaInfo,0-0-363593207-200-0-0-0-0-0-0-0.html",
    "English eAudio (Literizon, eAudio Stream), 1 copy / 1 available / 0 holds – 'Jetzt ausleihen'. OverDrive also owns an unabridged recording (Simon Prebble, 18h32m) but it is 0/1 – wait list there.")
row(27,"Lullaby","Leïla Slimani","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook. Searched also as 'The Perfect Nanny' (US title of the same novel). Only Slimani audiobook owned is 'Adele' (0/1).")
row(28,"Spring","Ali Smith","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of 'Spring' (author's other audiobooks only, e.g. Gliff).")
row(29,"Fear and Loathing in Las Vegas","Hunter S. Thompson","NOT_FOUND_AFTER_FULL_SEARCH",
    "German CD (leicht gekürzte Lesung, Martin Semmelrogge — available)","—","—",
    "No English digital audiobook. Author's 'The Rum Diary' audiobook is owned, but not this title.")
row(30,"Atonement","Ian McEwan","WAITLIST",
    "English CDs (AudioGo unabridged — available; HarperCollins abridged — available)","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/3171769",
    "Two English editions owned, both 0/1 and holdable – wait list: unabridged 12h26m (Random House, Carole Boyd); abridged 6h03m (Phoenix, Josephine Bailey).")
row(31,"We Need to Talk About Kevin","Lionel Shriver","WAITLIST","—","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/681057",
    "Unabridged 16h10m (Coleen Marlo). 0/1 copy; 1 hold – wait list.")
row(32,"A Good Man Is Hard to Find and Other Stories","Flannery O'Connor","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No audiobook (neither the collection nor individual stories) in any source.")
row(33,"Amsterdam","Ian McEwan","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook in any source (author's other titles only).")
row(34,"American Pastoral","Philip Roth","WAITLIST","—","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/122669",
    "Unabridged 15h31m (Ron Silver). 0/1 copy; 2 holds – wait list.")
row(35,"Knots & Crosses","Ian Rankin","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of this title (author's other audiobooks only).")
row(36,"The Color Purple","Alice Walker","WAITLIST","—","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/9920633",
    "Unabridged 7h57m (read by the author). 0/1 copy; 1 hold – wait list.")
row(37,"The House of the Spirits","Isabel Allende","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook in any source (author's other titles only).")
row(38,"The Joke","Milan Kundera","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook (only film DVDs; the author's owned audiobooks are different titles).")
row(39,"Vernon Subutex 1","Virginie Despentes","NOT_FOUND_AFTER_FULL_SEARCH",
    "French CD (Audiolib, lu par Jacques Frantz — vol. 1, available) + German E-Audio vols 1–3 (Das Leben des Vernon Subutex)",
    "—","—","No English audiobook. Volume 1 verified for the French CD and German E-Audio (vol. 1); no EN edition in any source.")
row(40,"The Poisonwood Bible","Barbara Kingsolver","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of this title (author's other works only).")
row(41,"Atomised","Michel Houellebecq","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook. Searched also as 'The Elementary Particles' (US title of the same novel). Only Houellebecq English audiobook owned is 'Serotonin'.")
row(42,"Independence Day","Richard Ford","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook in any source.")
row(43,"The Glass Hotel","Emily St. John Mandel","NOT_FOUND_AFTER_FULL_SEARCH",
    "English CD (Random House, Dylan Moore — currently not available)","—","—",
    "No digital audiobook owned (author's Station Eleven etc. only). CD exists but is 'Zurzeit nicht verfügbar'.")
row(44,"The Death of Ivan Ilyich and Other Stories","Leo Tolstoy","NOT_FOUND_AFTER_FULL_SEARCH","—",
    "OverDrive/Libby (VÖBB) partial","https://voebb.overdrive.com/media/168206",
    "Collection not available as audiobook. Partial only: novella 'The Death of Ivan Ilyich' (Naxos, 2h51m, Oliver Ford Davies) is owned but 0/1 with 2 holds (wait list) — not the full 'and Other Stories' collection.")
row(45,"The Waiter","Matias Faldbakken","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No trace in OverDrive, Onleihe or catalogue (title/author searches).")
row(46,"The History Boys","Alan Bennett","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No audiobook (stage play); author's other audiobooks only.")
row(47,"The Woman Who Walked Into Doors","Roddy Doyle","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of this title.")
row(48,"The Living Sea of Waking Dreams","Richard Flanagan","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of this title (author's 'The Narrow Road to the Deep North' only).")
row(49,"The Watcher in the Shadows","Carlos Ruiz Zafón","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of this title ('The Shadow of the Wind' only).")
row(50,"Everything Is Illuminated","Jonathan Safran Foer","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of this title (author's other works only).")
row(51,"The Corrections","Jonathan Franzen","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of this title (author's Freedom, Purity, Crossroads etc. only).")
row(52,"The Narrow Road to the Deep North","Richard Flanagan","AVAILABLE_NOW",
    "English MP3 CDs (Blackstone, read by David Atlas, unabridged — available)","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/1817988",
    "Unabridged 14h59m (David Linski). 1/2 copies; 0 holds – 'Available'. E-Audio + MP3 CDs also in catalogue.")
row(53,"Station Eleven","Emily St. John Mandel","WAITLIST","—","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/1499830",
    "Unabridged 10h41m (Kirsten Potter). 0/2 copies; 6 holds – wait list.")
row(54,"The Little Goblin Girl","Illy Hymen","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No trace of title or author in OverDrive (exact + shortened title + author), Onleihe or catalogue.")
row(55,"The Luminaries","Eleanor Catton","NOT_FOUND_AFTER_FULL_SEARCH",
    "German eAudio (Der Wald — Onleihe)","—","—",
    "No English audiobook owned (audiobook exists globally but not in VÖBB). Catalogue holds the TV miniseries DVD only.")
row(56,"Empire of the Sun","J. G. Ballard","WAITLIST","—","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/143657",
    "Only the abridged English audiobook is owned (3h08m, Jeremy Irons). 0/1 copy; 2 holds – wait list. No unabridged EN audio edition owned.")
row(57,"Notes from Underground","Fyodor Dostoevsky","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook in any source (author's 'Crime and Punishment' only).")
row(58,"Celestial Bodies","Jokha Alharthi","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No audiobook; eBook only (0/2).")
row(59,"Freedom","Jonathan Franzen","AVAILABLE_NOW",
    "English CD (Harper Collins, read by David Ledoux, unabridged — available)","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/389422",
    "Unabridged 24h09m (David Ledoux). 1/2 copies; 0 holds – 'Available'. E-Audio + CD also in catalogue.")
row(60,"The Blind Assassin","Margaret Atwood","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of this title (author's other works only).")
row(61,"Wolf Hall","Hilary Mantel","AVAILABLE_NOW","—","OverDrive/Libby (VÖBB)",
    "https://voebb.overdrive.com/media/1004466",
    "Abridged edition (7h11m, Dan Stevens) available now (1/3; 0 holds). Unabridged edition (24h17m, Simon Slater) owned but on wait list (0/1; 1 hold). Edition distinction noted per requirement.")
row(62,"The Sea","John Banville","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of this title (author's 'The Singularities' only).")
row(63,"The Sense of an Ending","Julian Barnes","NOT_FOUND_AFTER_FULL_SEARCH",
    "English CD (AudioGo, narrated by Richard Morant, unabridged — available)","—","—",
    "No digital audiobook in OverDrive/Onleihe; only the English CD (physical) is held.")
row(64,"The Dying Animal","Philip Roth","NOT_FOUND_AFTER_FULL_SEARCH","—","—","—",
    "No English audiobook of this title (author's other works only).")

assert len(R) == 64, len(R)

with open(OUT,'w',newline='',encoding='utf-8') as f:
    w = csv.writer(f, quoting=csv.QUOTE_ALL)
    w.writerow(HEADER)
    for r in R:
        w.writerow(r)

print("wrote 64 rows")
# sanity: re-read
with open(OUT, newline='', encoding='utf-8') as f:
    rows = list(csv.reader(f))
print("reread rows:", len(rows)-1, "| cols ok:", all(len(r)==9 for r in rows))
from collections import Counter
c = Counter(r[3] for r in rows[1:])
print("status counts:", dict(c))
