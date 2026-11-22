# VÖBB English digital-audiobook check — evidence log

- Date checked: **2026-10-20** (all rows)
- Scope: 47 books embedded in the photo-list input; only those books were searched.
- Read-only. No login, borrowing, holds or purchases.

## Sources and endpoints
1. **OverDrive / Libby (VÖBB)** — `https://thunder.api.overdrive.com/v2/libraries/voebb/media?query=…` (title, title+surname, surname-only with `mediaType=audiobook&language=en`, fully paginated); per-record verification via `/media/<id>`. Public record page: `https://voebb.overdrive.com/media/<id>`.
2. **Onleihe Berlin** — `https://voebb.onleihe.de/berlin/frontend/search,...` POST (`pText=<term>`), candidate detail pages `mediaInfo,...` checked for `Sprache`, `Format`, copy counts and status.
3. **VÖBB main catalogue (aDISWeb OPAC)** — session POST to `https://www.voebb.de/aDISWeb/<session>/app`, result lists parsed for medium (`E-Audio`, `CD`, `MP3`, `Band`, `DVD`). Record links: `https://www.voebb.de/aDISWeb/app?noRedir&service=direct/0/Home/$DirectLink&sp=SPROD00&sp=SAK<AK>`.

## Search coverage (applies to all 47 books)
- Exact title; title + author surname; surname-only author pass (OverDrive, English audiobooks, **fully paginated**); documented alternative/shortened titles for punctuation-heavy or translated titles.
- Onleihe: exact title plus surname pass; detail pages opened for every title-matching candidate.
- Catalogue: title+surname and title-only queries; media type inspected on every hit.
- OverDrive author lists were paged to completion: King 81/81, Atwood 72/72, Fry 55/55, Harari 50/50, Pinker 25/25, Franzen 20/20, P. K. Dick 16/16, Mandel 13/13, Ford 8/8, Ackroyd 7/7, Price 7/7, Kundera 7/7, Chabon 6/6, Dostoevsky 5/5, Houellebecq 5/5, Powers 35/35.
- No English eAudio match was found on Onleihe for any of the 47 titles (Onleihe holdings are overwhelmingly German).

## Confirmed English digital-audiobook holdings (8)

| # | Title | Author | Status | Copies / holds | Edition | Evidence |
|---|---|---|---|---|---|---|
| 02 | Sapiens | Yuval Noah Harari | WAITLIST | 0/10 available, 0 holds | Unabridged, 15h18m, narrated Derek Perkins | https://voebb.overdrive.com/media/3255516 |
| 10 | Mythos | Stephen Fry | WAITLIST | 0/6 available, 7 holds | Unabridged, 15h25m, narrated by Stephen Fry | https://voebb.overdrive.com/media/3512899 |
| 20 | The Stand | Stephen King | WAITLIST | 0/1 available, 4 holds | Unabridged, complete and uncut, 47h47m, narrated Grover Gardner | https://voebb.overdrive.com/media/589885 |
| 24 | The Unbearable Lightness of Being | Milan Kundera | WAITLIST | 0/2 available, 0 holds | Unabridged (catalogue states Unabridged; OverDrive edition field blank), 9h36m, narrated Richmond Hoxie | https://voebb.overdrive.com/media/3995095 |
| 33 | The Narrow Road to the Deep North | Richard Flanagan | AVAILABLE_NOW | 1/2 available, 0 holds | Unabridged, 14h59m, narrated David Linski (David Atlas) | https://voebb.overdrive.com/media/1817988 |
| 37 | Middlesex | Jeffrey Eugenides | WAITLIST | 0/3 available, 0 holds | Unabridged, 21h21m, narrated Kristoffer Tabori | https://voebb.overdrive.com/media/86990 |
| 38 | The Overstory | Richard Powers | AVAILABLE_NOW | 1/5 available, 0 holds | Unabridged, 22h58m, narrated Suzanne Toren | https://voebb.overdrive.com/media/4235624 |
| 40 | Freedom | Jonathan Franzen | AVAILABLE_NOW | 1/2 available, 0 holds | Unabridged, 24h09m, narrated David Ledoux | https://voebb.overdrive.com/media/389422 |

### Record detail

**02 Sapiens — Yuval Noah Harari**
- Record: https://voebb.overdrive.com/media/3255516
- Type: Audiobook · Language: en · Edition: Unabridged · Duration: 15:18:10 · Narrator: Derek Perkins
- Publisher/date: HarperCollins, 08/15/2017
- Availability as displayed: 0/10 available, 0 holds, isHoldable true, estimatedWaitDays 2

**10 Mythos — Stephen Fry**
- Record: https://voebb.overdrive.com/media/3512899
- Type: Audiobook · Language: en · Edition: Unabridged · Duration: 15:25:36 · Narrator: Stephen Fry
- Publisher/date: Penguin Books Ltd, 11/02/2017
- Availability as displayed: 0/6 available, 7 holds, isHoldable true, estimatedWaitDays 19

**20 The Stand — Stephen King**
- Record: https://voebb.overdrive.com/media/589885
- Type: Audiobook · Language: en · Edition: Unabridged · Duration: 47:47:51 · Narrator: Grover Gardner
- Publisher/date: Books on Tape, 02/14/2012
- Availability as displayed: 0/1 available, 4 holds, isHoldable true, estimatedWaitDays 70 — complete & uncut runtime

**24 The Unbearable Lightness of Being — Milan Kundera**
- Record: https://voebb.overdrive.com/media/3995095
- Type: Audiobook · Language: en · Edition: edition field blank (catalogue: Unabridged) · Duration: 09:36:55 · Narrator: Richmond Hoxie
- Publisher/date: Faber & Faber, 09/06/2012
- Availability as displayed: 0/2 available, 0 holds, isHoldable true, estimatedWaitDays 7

**33 The Narrow Road to the Deep North — Richard Flanagan**
- Record: https://voebb.overdrive.com/media/1817988
- Type: Audiobook · Language: en · Edition: Unabridged · Duration: 14:59:47 · Narrator: David Linski
- Publisher/date: Blackstone Publishing, 08/12/2014
- Availability as displayed: 1/2 available, 0 holds — AVAILABLE_NOW

**37 Middlesex — Jeffrey Eugenides**
- Record: https://voebb.overdrive.com/media/86990
- Type: Audiobook · Language: en · Edition: Unabridged · Duration: 21:21:21 · Narrator: Kristoffer Tabori
- Publisher/date: Macmillan Audio, 3/1/2003
- Availability as displayed: 0/3 available, 0 holds, isHoldable true, estimatedWaitDays 5

**38 The Overstory — Richard Powers**
- Record: https://voebb.overdrive.com/media/4235624
- Type: Audiobook · Language: en · Edition: Unabridged · Duration: 22:58:04 · Narrator: Suzanne Toren
- Publisher/date: Random House, 09/06/2018
- Availability as displayed: 1/5 available, 0 holds — AVAILABLE_NOW

**40 Freedom — Jonathan Franzen**
- Record: https://voebb.overdrive.com/media/389422
- Type: Audiobook · Language: en · Edition: Unabridged · Duration: 24:09:28 · Narrator: David Ledoux
- Publisher/date: Macmillan Audio, 08/31/2010
- Availability as displayed: 1/2 available, 0 holds — AVAILABLE_NOW

## Per-book search record (all 47)

### 01 Difficult Men — Brett Martin — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Difficult Men` → 11 hits; `Difficult Men Martin` → 0 hits
- OverDrive author pass: 1/1 audiobooks inspected
- Onleihe: Difficult Men=1, Martin Difficult Men=0 (candidates detail-checked; none English eAudio)
- Catalogue: Difficult Men Martin=15, Difficult Men=22
- Result: Exact title, title+surname, 'Difficult Men TV' and surname-only author pass (Brett Martin 1/1, unrelated PONS language course). No audio in any source.

### 02 Sapiens — Yuval Noah Harari — **WAITLIST**
- OverDrive audiobook+EN: `Sapiens` → 69 hits; `Sapiens Harari` → 35 hits
- OverDrive author pass: 50/50 audiobooks inspected
- Onleihe: Sapiens=27, Harari Sapiens=3 (candidates detail-checked; none English eAudio)
- Catalogue: Sapiens Harari=22, Sapiens=22
- Evidence: https://voebb.overdrive.com/media/3255516
- Result: 0 of 10 copies available, 0 holds, holdable, est. wait 2 days. Photo duplicate note: Sapiens appears twice in the photographed list but only once (ID 02) in this 47-book input, so searched once.

### 03 Inside Scientology — Janet Reitman — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Inside Scientology` → 2 hits; `Inside Scientology Reitman` → 1 hits
- OverDrive author pass: 1/1 audiobooks inspected
- Onleihe: Inside Scientology=1, Reitman Inside Scientology=0 (candidates detail-checked; none English eAudio)
- Catalogue: Inside Scientology Reitman=1, Inside Scientology=7
- Result: Exact/short/author (Reitman 1/1) and alt-title passes across all three sources. VÖBB holds the eBook only (OverDrive 598976); no audiobook.

### 04 Film Directing Shot by Shot — Steven D. Katz — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Film Directing Shot by Shot` → 0 hits; `Film Directing Shot by Shot Katz` → 0 hits
- OverDrive author pass: 0/0 audiobooks inspected
- Onleihe: Film Directing Shot by Shot=1, Katz Film Directing Shot by Shot=0 (candidates detail-checked; none English eAudio)
- Catalogue: Film Directing Shot by Shot Katz=6, Film Directing Shot by Shot=22
- Result: Exact, shortened ('Shot by Shot', 'Film Directing') and author (Katz 0/0) searches; 0 audiobook results in all three sources.

### 05 On Film-making — Alexander Mackendrick — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `On Film-making` → 43 hits; `On Film-making Mackendrick` → 0 hits
- OverDrive author pass: 0/0 audiobooks inspected
- Onleihe: On Film-making=10, Mackendrick On Film-making=0 (candidates detail-checked; none English eAudio)
- Catalogue: On Film-making Mackendrick=6, On Film-making=22
- Result: Exact, hyphen-free ('On Film Making') and author (Mackendrick 0/0) searches; no audiobook.

### 06 Directing Actors — Judith Weston — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Directing Actors` → 9 hits; `Directing Actors Weston` → 0 hits
- OverDrive author pass: 0/0 audiobooks inspected
- Onleihe: Directing Actors=8, Weston Directing Actors=0 (candidates detail-checked; none English eAudio)
- Catalogue: Directing Actors Weston=6, Directing Actors=22
- Result: Exact and author (Weston 0/0) searches; results were unrelated directing titles. No audiobook.

### 07 Getting More — Stuart Diamond — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Getting More` → 33 hits; `Getting More Diamond` → 0 hits
- OverDrive author pass: 0/0 audiobooks inspected
- Onleihe: Getting More=125, Diamond Getting More=0 (candidates detail-checked; none English eAudio)
- Catalogue: Getting More Diamond=18, Getting More=22
- Result: Exact, 'Getting More Diamond' and surname-only pass (Diamond 0/0); no audiobook.

### 08 London: The Biography — Peter Ackroyd — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `London` → 699 hits; `London Ackroyd` → 1 hits
- OverDrive author pass: 7/7 audiobooks inspected
- Onleihe: London=763, Ackroyd London=0 (candidates detail-checked; none English eAudio)
- Catalogue: London Ackroyd=22, London=22
- Result: Exact/short ('London'), 'London Ackroyd' and full Ackroyd audiobook pass (7/7) checked. No Ackroyd London audiobook.

### 09 Mythology — Edith Hamilton — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Mythology` → 1282 hits; `Mythology Hamilton` → 3 hits
- OverDrive author pass: 1/1 audiobooks inspected
- Onleihe: Mythology=69, Hamilton Mythology=0 (candidates detail-checked; none English eAudio)
- Catalogue: Mythology Hamilton=7, Mythology=22
- Result: Exact, 'Mythology Hamilton' and author pass (Hamilton 1/1 = Collected Dialogues of Plato). No Hamilton Mythology audio; Gaiman/Morales look-alikes excluded.

### 10 Mythos — Stephen Fry — **WAITLIST**
- OverDrive audiobook+EN: `Mythos` → 23 hits; `Mythos Fry` → 9 hits
- OverDrive author pass: 55/55 audiobooks inspected
- Onleihe: Mythos=371, Fry Mythos=0 (candidates detail-checked; none English eAudio)
- Catalogue: Mythos Fry=22, Mythos=22
- Evidence: https://voebb.overdrive.com/media/3512899
- Result: 0 of 6 copies available, 7 holds, holdable, est. wait 19 days. Fry's full 55-title audiobook list paged; no other edition of Mythos.

### 11 The Blank Slate — Steven Pinker — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Blank Slate` → 2 hits; `The Blank Slate Pinker` → 2 hits
- OverDrive author pass: 25/25 audiobooks inspected
- Onleihe: The Blank Slate=0, Pinker The Blank Slate=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Blank Slate Pinker=4, The Blank Slate=22
- Result: Exact, 'Blank Slate Pinker', surname-only pass (Pinker 25/25 fully paged) and alt titles checked. No audiobook of The Blank Slate.

### 12 The Gendered Brain — Gina Rippon — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Gendered Brain` → 14 hits; `The Gendered Brain Rippon` → 1 hits
- OverDrive author pass: 3/3 audiobooks inspected
- Onleihe: The Gendered Brain=0, Rippon The Gendered Brain=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Gendered Brain Rippon=2, The Gendered Brain=22
- Result: Exact + 'The Gendered Brain Rippon' + author pass (3/3). No match; Delusions of Gender (Cordelia Fine) excluded.

### 13 London: A History in Maps — Peter Barber — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `London` → 699 hits; `London Barber` → 5 hits
- OverDrive author pass: 1/1 audiobooks inspected
- Onleihe: London=763, Barber London=0 (candidates detail-checked; none English eAudio)
- Catalogue: London Barber=22, London=22
- Result: Exact/short/'London Barber' + author pass paged. Barber results were mostly Samuel Barber music; no audiobook.

### 14 David Inshaw — Andrew Lambirth — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `David Inshaw` → 0 hits; `David Inshaw Lambirth` → 0 hits
- OverDrive author pass: 0/0 audiobooks inspected
- Onleihe: David Inshaw=0, Lambirth David Inshaw=0 (candidates detail-checked; none English eAudio)
- Catalogue: David Inshaw Lambirth=0, David Inshaw=3
- Result: Exact, 'Inshaw', 'Lambirth' and surname-only pass (Lambirth 0/0); no record of any format.

### 15 The Whites — Richard Price — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Whites` → 865 hits; `The Whites Price` → 4 hits
- OverDrive author pass: 7/7 audiobooks inspected
- Onleihe: The Whites=158, Price The Whites=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Whites Price=22, The Whites=22
- Result: Exact, 'The Whites Price' (4 fuzzy hits, none the novel) and surname-only pass (Richard Price 7/7). No English audiobook.

### 16 11.22.63 — Stephen King — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `11.22.63` → 0 hits; `11.22.63 King` → 0 hits; `11/22/63` → 6 hits; `eleven twenty two sixty three` → 1 hits
- OverDrive author pass: 81/81 audiobooks inspected
- Onleihe: 11.22.63=0, King 11.22.63=0 (candidates detail-checked; none English eAudio)
- Catalogue: 11.22.63 King=5, 11.22.63=5
- Result: Searched '11.22.63', '11/22/63', '112263', 'eleven twenty two sixty three', 'Kennedy King' and King's full 81-title audiobook list. No audiobook of this novel in VÖBB.

### 17 Antkind — Charlie Kaufman — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Antkind` → 0 hits; `Antkind Kaufman` → 0 hits
- OverDrive author pass: 1/1 audiobooks inspected
- Onleihe: Antkind=0, Kaufman Antkind=0 (candidates detail-checked; none English eAudio)
- Catalogue: Antkind Kaufman=1, Antkind=1
- Result: Exact, 'Antkind Kaufman' and author pass (Kaufman 1/1, unrelated). No audiobook.

### 18 The Joke — Milan Kundera — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Joke` → 53 hits; `The Joke Kundera` → 1 hits
- OverDrive author pass: 7/7 audiobooks inspected
- Onleihe: The Joke=20, Kundera The Joke=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Joke Kundera=4, The Joke=22
- Result: Author verified as Milan Kundera. Kundera's full 7-title audiobook list contains only The Unbearable Lightness of Being and The Art of the Novel; catalogue has the DVD of The Joke (AK13793154). Exact/short/'The Joke Kundera' searched. No audiobook.

### 19 Vernon Subutex 1 — Virginie Despentes — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Vernon Subutex 1` → 1 hits; `Vernon Subutex 1 Despentes` → 1 hits; `Vernon Subutex` → 1 hits
- OverDrive author pass: 2/2 audiobooks inspected
- Onleihe: Vernon Subutex 1=3, Despentes Vernon Subutex 1=3 (candidates detail-checked; none English eAudio)
- Catalogue: Vernon Subutex 1 Despentes=18, Vernon Subutex 1=19
- Result: Exact 'Vernon Subutex 1'/'Vernon Subutex', author pass (Despentes 2/2), Onleihe and catalogue checked. No English-language audio of volume 1.

### 20 The Stand — Stephen King — **WAITLIST**
- OverDrive audiobook+EN: `The Stand` → 345 hits; `The Stand King` → 42 hits
- OverDrive author pass: 81/81 audiobooks inspected
- Onleihe: The Stand=914, King The Stand=7 (candidates detail-checked; none English eAudio)
- Catalogue: The Stand King=22, The Stand=22
- Evidence: https://voebb.overdrive.com/media/589885
- Result: 0 of 1 copy available, 4 holds, holdable, est. wait 70 days. 47h47m runtime confirms the complete/uncut recording; no abridged or dramatised edition held.

### 21 The Glass Hotel — Emily St. John Mandel — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Glass Hotel` → 4 hits; `The Glass Hotel Mandel` → 3 hits
- OverDrive author pass: 13/13 audiobooks inspected
- Onleihe: The Glass Hotel=0, Mandel The Glass Hotel=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Glass Hotel Mandel=15, The Glass Hotel=22
- Result: Exact, 'The Glass Hotel Mandel' and Mandel's full 13-title audiobook pass; only Exit Party/Station Eleven/Sea of Tranquility on audio. VÖBB has the eBook (5011122) but no English digital audiobook.

### 22 The Possibility of an Island — Michel Houellebecq — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Possibility of an Island` → 1 hits; `The Possibility of an Island Houellebecq` → 0 hits
- OverDrive author pass: 5/5 audiobooks inspected
- Onleihe: The Possibility of an Island=0, Houellebecq The Possibility of an Island=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Possibility of an Island Houellebecq=0, The Possibility of an Island=22
- Result: Exact/short/'Houellebecq' and author pass (5/5 — Whatever, Serotonin, H.P. Lovecraft etc.). No edition of this novel in audio.

### 23 Zen and the Art of Motorcycle Maintenance — Robert M. Pirsig — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Zen and the Art of Motorcycle Maintenance` → 0 hits; `Zen and the Art of Motorcycle Maintenance Pirsig` → 0 hits
- OverDrive author pass: 0/0 audiobooks inspected
- Onleihe: Zen and the Art of Motorcycle Maintenance=0, Pirsig Zen and the Art of Motorcycle Maintenance=0 (candidates detail-checked; none English eAudio)
- Catalogue: Zen and the Art of Motorcycle Maintenance Pirsig=10, Zen and the Art of Motorcycle Maintenance=12
- Result: Exact, 'Motorcycle Maintenance', 'Pirsig' and surname-only pass (Pirsig 0/0). No audiobook.

### 24 The Unbearable Lightness of Being — Milan Kundera — **WAITLIST**
- OverDrive audiobook+EN: `The Unbearable Lightness of Being` → 6 hits; `The Unbearable Lightness of Being Kundera` → 5 hits
- OverDrive author pass: 7/7 audiobooks inspected
- Onleihe: The Unbearable Lightness of Being=0, Kundera The Unbearable Lightness of Being=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Unbearable Lightness of Being Kundera=22, The Unbearable Lightness of Being=22
- Evidence: https://voebb.overdrive.com/media/3995095
- Result: 0 of 2 copies available, 0 holds, holdable, est. wait 7 days. Catalogue mirror AK34972207 confirms Unabridged, Faber & Faber 2012.

### 25 The Watcher in the Shadows — Carlos Ruiz Zafón — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Watcher in the Shadows` → 0 hits; `The Watcher in the Shadows Zafon` → 0 hits
- OverDrive author pass: 1/1 audiobooks inspected
- Onleihe: The Watcher in the Shadows=1, Zafon The Watcher in the Shadows=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Watcher in the Shadows Zafon=0, The Watcher in the Shadows=7
- Result: Exact, 'Watcher Shadows', 'Luces de Septiembre' and author pass (Zafón 1/1 = The Shadow of the Wind). No audiobook of this title.

### 26 The Luminaries — Eleanor Catton — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Luminaries` → 9 hits; `The Luminaries Catton` → 0 hits
- OverDrive author pass: 2/2 audiobooks inspected
- Onleihe: The Luminaries=1, Catton The Luminaries=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Luminaries Catton=10, The Luminaries=22
- Result: Author verified Eleanor Catton (the Susan Dennard novel of the same title excluded). Catton 2/2 audiobooks — neither is The Luminaries; no English digital audiobook.

### 27 Time Shelter — Georgi Gospodinov — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Time Shelter` → 9 hits; `Time Shelter Gospodinov` → 1 hits
- OverDrive author pass: 1/1 audiobooks inspected
- Onleihe: Time Shelter=0, Gospodinov Time Shelter=0 (candidates detail-checked; none English eAudio)
- Catalogue: Time Shelter Gospodinov=3, Time Shelter=22
- Result: Exact, 'Timeshelter', 'Time Shelter Gospodinov' and author pass (1/1). English translation verified; no audiobook.

### 28 The 32 — Paul McVeigh — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The 32` → 45 hits; `The 32 McVeigh` → 45 hits; `The Thirty-Two` → 19 hits
- OverDrive author pass: 0/0 audiobooks inspected
- Onleihe: The 32=51, McVeigh The 32=0 (candidates detail-checked; none English eAudio)
- Catalogue: The 32 McVeigh=2, The 32=22
- Result: Exact 'The 32', 'The Thirty-Two', 'The 32 McVeigh' and author pass (McVeigh 0/0). All '32' hits were unrelated (Naruto vol. 32, The 32 Principles, etc.).

### 29 The Stories of Stephen Dixon — Stephen Dixon — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Stories of Stephen Dixon` → 0 hits; `The Stories of Stephen Dixon Dixon` → 0 hits; `Stories of Stephen Dixon` → 0 hits
- OverDrive author pass: 0/0 audiobooks inspected
- Onleihe: The Stories of Stephen Dixon=0, Dixon The Stories of Stephen Dixon=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Stories of Stephen Dixon Dixon=10, The Stories of Stephen Dixon=10
- Result: Exact title, shortened 'Stories of Stephen Dixon' and author pass (Dixon 0/0). No collection and no individual story recording; individual stories would be partial matches only.

### 30 Three Plays — August Wilson — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Three Plays` → 84 hits; `Three Plays Wilson` → 0 hits
- OverDrive author pass: 0/0 audiobooks inspected
- Onleihe: Three Plays=4, Wilson Three Plays=0 (candidates detail-checked; none English eAudio)
- Catalogue: Three Plays Wilson=22, Three Plays=22
- Result: Exact, 'August Wilson', 'Wilson plays', 'Pittsburgh Cycle', 'Fences Wilson'; author pass 0/0. No recording of the collection; a single play would not count.

### 31 The Corrections — Jonathan Franzen — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Corrections` → 35 hits; `The Corrections Franzen` → 2 hits
- OverDrive author pass: 20/20 audiobooks inspected
- Onleihe: The Corrections=88, Franzen The Corrections=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Corrections Franzen=22, The Corrections=22
- Result: Exact, 'The Corrections Franzen' and Franzen's full 20-title audiobook pass; only Crossroads/Freedom/Purity/Farther Away etc. on audio. VÖBB holds the eBook (34823737), not an audiobook.

### 32 The Living Sea of Waking Dreams — Richard Flanagan — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Living Sea of Waking Dreams` → 0 hits; `The Living Sea of Waking Dreams Flanagan` → 0 hits
- OverDrive author pass: 3/3 audiobooks inspected
- Onleihe: The Living Sea of Waking Dreams=0, Flanagan The Living Sea of Waking Dreams=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Living Sea of Waking Dreams Flanagan=2, The Living Sea of Waking Dreams=7
- Result: Exact, shortened and author pass (Flanagan 3/3 — only Narrow Road is audio). No audiobook.

### 33 The Narrow Road to the Deep North — Richard Flanagan — **AVAILABLE_NOW**
- OverDrive audiobook+EN: `The Narrow Road to the Deep North` → 3 hits; `The Narrow Road to the Deep North Flanagan` → 2 hits
- OverDrive author pass: 3/3 audiobooks inspected
- Onleihe: The Narrow Road to the Deep North=0, Flanagan The Narrow Road to the Deep North=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Narrow Road to the Deep North Flanagan=7, The Narrow Road to the Deep North=9
- Evidence: https://voebb.overdrive.com/media/1817988
- Result: 1 of 2 copies available, 0 holds. Catalogue E-Audio mirror AK16313587.

### 34 Philip K. Dick: Four Novels of the 1960s — Philip K. Dick — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Philip K. Dick` → 16 hits; `Philip K. Dick Dick` → 16 hits; `Four Novels of the 1960s` → 1 hits
- OverDrive author pass: 16/16 audiobooks inspected
- Onleihe: Philip K. Dick=3, Dick Philip K. Dick=3 (candidates detail-checked; none English eAudio)
- Catalogue: Philip K. Dick Dick=22, Philip K. Dick=22
- Result: Collection searched by exact title, 'Four Novels of the 1960s' and Dick's full 16-title audiobook pass. Individual novels held in other formats (Do Androids Dream audio 123544; The Man in the High Castle CD; Ubik eBook) are partial matches and are not counted.

### 35 The Man in the High Castle — Philip K. Dick — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Man in the High Castle` → 4 hits; `The Man in the High Castle Dick` → 3 hits
- OverDrive author pass: 16/16 audiobooks inspected
- Onleihe: The Man in the High Castle=0, Dick The Man in the High Castle=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Man in the High Castle Dick=15, The Man in the High Castle=22
- Result: Exact, 'High Castle Dick' and Dick's 16-title audiobook pass; only the eBook (769247) is digital. No English digital audiobook.

### 36 The Book of Disquiet — Fernando Pessoa — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Book of Disquiet` → 2 hits; `The Book of Disquiet Pessoa` → 0 hits
- OverDrive author pass: 2/2 audiobooks inspected
- Onleihe: The Book of Disquiet=0, Pessoa The Book of Disquiet=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Book of Disquiet Pessoa=1, The Book of Disquiet=22
- Result: Exact, 'Livro do Desassossego' and author pass (Pessoa 2/2 = Antinous, 35 Sonnets). No audiobook or translation held.

### 37 Middlesex — Jeffrey Eugenides — **WAITLIST**
- OverDrive audiobook+EN: `Middlesex` → 2 hits; `Middlesex Eugenides` → 2 hits
- OverDrive author pass: 6/6 audiobooks inspected
- Onleihe: Middlesex=3, Eugenides Middlesex=1 (candidates detail-checked; none English eAudio)
- Catalogue: Middlesex Eugenides=22, Middlesex=22
- Evidence: https://voebb.overdrive.com/media/86990
- Result: 0 of 3 copies available, 0 holds, holdable, est. wait 5 days. Catalogue E-Audio mirror AK34114010.

### 38 The Overstory — Richard Powers — **AVAILABLE_NOW**
- OverDrive audiobook+EN: `The Overstory` → 10 hits; `The Overstory Powers` → 8 hits
- OverDrive author pass: 35/35 audiobooks inspected
- Onleihe: The Overstory=0, Powers The Overstory=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Overstory Powers=21, The Overstory=21
- Evidence: https://voebb.overdrive.com/media/4235624
- Result: 1 of 5 copies available, 0 holds. Catalogue E-Audio mirror AK34423920.

### 39 The Amazing Adventures of Kavalier & Clay — Michael Chabon — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Amazing Adventures of Kavalier & Clay` → 1 hits; `The Amazing Adventures of Kavalier & Clay Chabon` → 1 hits
- OverDrive author pass: 6/6 audiobooks inspected
- Onleihe: The Amazing Adventures of Kavalier & Clay=0, Chabon The Amazing Adventures of Kavalier & Clay=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Amazing Adventures of Kavalier & Clay Chabon=9, The Amazing Adventures of Kavalier & Clay=9
- Result: Exact, 'Kavalier Clay', 'Kavalier and Clay' and Chabon's full 6-title audiobook pass. VÖBB has the eBook (728008) but no English digital audiobook.

### 40 Freedom — Jonathan Franzen — **AVAILABLE_NOW**
- OverDrive audiobook+EN: `Freedom` → 378 hits; `Freedom Franzen` → 2 hits
- OverDrive author pass: 20/20 audiobooks inspected
- Onleihe: Freedom=37, Franzen Freedom=0 (candidates detail-checked; none English eAudio)
- Catalogue: Freedom Franzen=22, Freedom=22
- Evidence: https://voebb.overdrive.com/media/389422
- Result: 1 of 2 copies available, 0 holds. Angela Merkel's 'Freedom' and other same-title works excluded by author.

### 41 The Woman Who Walked Into Doors — Roddy Doyle — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Woman Who Walked Into Doors` → 0 hits; `The Woman Who Walked Into Doors Doyle` → 0 hits
- OverDrive author pass: 3/3 audiobooks inspected
- Onleihe: The Woman Who Walked Into Doors=0, Doyle The Woman Who Walked Into Doors=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Woman Who Walked Into Doors Doyle=4, The Woman Who Walked Into Doors=22
- Result: Exact, 'Woman Doors', 'Paula Spencer' and Doyle's full 3-title audiobook pass. No audiobook.

### 42 Notes from Underground — Fyodor Dostoevsky — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Notes from Underground` → 1 hits; `Notes from Underground Dostoevsky` → 0 hits
- OverDrive author pass: 5/5 audiobooks inspected
- Onleihe: Notes from Underground=1, Dostoevsky Notes from Underground=0 (candidates detail-checked; none English eAudio)
- Catalogue: Notes from Underground Dostoevsky=1, Notes from Underground=22
- Result: Exact, 'Notes from the Underground', 'Zapiski iz podpolya' and author pass (Dostoevsky 5/5 — Crime and Punishment, The Idiot, The Gambler, The House of the Dead). No audiobook of this work.

### 43 The Blind Assassin — Margaret Atwood — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Blind Assassin` → 4 hits; `The Blind Assassin Atwood` → 4 hits
- OverDrive author pass: 72/72 audiobooks inspected
- Onleihe: The Blind Assassin=0, Atwood The Blind Assassin=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Blind Assassin Atwood=22, The Blind Assassin=22
- Result: Exact, 'Blind Assassin Atwood' and Atwood's full 72-title audiobook list paged. No audiobook edition in VÖBB.

### 44 Independence Day — Richard Ford — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Independence Day` → 48 hits; `Independence Day Ford` → 1 hits
- OverDrive author pass: 8/8 audiobooks inspected
- Onleihe: Independence Day=1, Ford Independence Day=0 (candidates detail-checked; none English eAudio)
- Catalogue: Independence Day Ford=9, Independence Day=22
- Result: Exact, 'Independence Day Ford', 'Bascombe' and Ford's full 8-title audiobook pass. No audiobook (the 1996 film DVD is unrelated).

### 45 Extinction — Thomas Bernhard — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Extinction` → 81 hits; `Extinction Bernhard` → 0 hits
- OverDrive author pass: 1/1 audiobooks inspected
- Onleihe: Extinction=1, Bernhard Extinction=0 (candidates detail-checked; none English eAudio)
- Catalogue: Extinction Bernhard=12, Extinction=22
- Result: Exact, 'Extinction Bernhard', 'Auslöschung' and author pass (Bernhard 1/1 = unrelated Krasznahorkai). Extinction by other authors (Takano, Preston, Somer) excluded.

### 46 Winter's Bone — Daniel Woodrell — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `Winter's Bone` → 8 hits; `Winter's Bone Woodrell` → 0 hits
- OverDrive author pass: 0/0 audiobooks inspected
- Onleihe: Winter's Bone=0, Woodrell Winter's Bone=0 (candidates detail-checked; none English eAudio)
- Catalogue: Winter's Bone Woodrell=6, Winter's Bone=22
- Result: Exact, 'Winters Bone', 'Woodrell' and author pass (Woodrell 0/0). No audiobook.

### 47 The Child Garden — Geoff Ryman — **NOT_FOUND_AFTER_FULL_SEARCH**
- OverDrive audiobook+EN: `The Child Garden` → 15 hits; `The Child Garden Ryman` → 0 hits
- OverDrive author pass: 2/2 audiobooks inspected
- Onleihe: The Child Garden=3, Ryman The Child Garden=0 (candidates detail-checked; none English eAudio)
- Catalogue: The Child Garden Ryman=22, The Child Garden=22
- Result: Exact, 'Child Garden Ryman', 'Geoff Ryman' and author pass (Ryman 2/2 = anthologies Alien Sex, Welcome to Dystopia). No audiobook.

## Limitations
- OverDrive borrowing status is a point-in-time snapshot (2026-10-20); copies/holds change continuously.
- OverDrive's `edition` field is blank for The Unbearable Lightness of Being; Unabridged is taken from the catalogue E-Audio mirror (AK34972207).
- Onleihe's search is fuzzy and German-weighted; English eAudio was explicitly filtered by `Sprache: Englisch` + `eAudio Stream` on detail pages.
- Physical CDs/MP3-CDs are listed separately and never counted as digital availability.
- No access limitation prevented a search; no row uses UNVERIFIED_ACCESS_LIMITATION.
