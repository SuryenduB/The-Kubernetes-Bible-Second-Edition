# Evidence — VÖBB English audiobook check (64 books)

Checked 2026-10-20. All three VÖBB services were reached through the official VÖBB
digital-services page (www.voebb.de → "Die Digitalen Angebote des VÖBB"):

- **OverDrive / Libby (VÖBB)**: https://voebb.overdrive.com — public search JSON `https://thunder.api.overdrive.com/v2/libraries/voebb/media?query=…&mediaType=audiobook&language=en`, cross-checked with the HTML search page `https://voebb.overdrive.com/search?query=…`.
- **Onleihe (VÖBB)**: https://voebb.onleihe.de/berlin/frontend/ — POST search `search,0-0-0-0-0-0-0-0-0-0-0.html` (`pText`, `cmdId=703`, `sK=1000`), detail pages `mediaInfo,…`.
- **Main catalogue (aDISWeb OPAC)**: https://www.voebb.de — session POST `/aDISWeb/<session>/app` (`THEMA2_1`, `THEMA1_1`, `SUCBER_1`, `$Autosuggest`, `$$GFBO_1=Suchen`).

No login, no borrowing, no holds, no purchases; all requests were anonymous read-only searches.

## Search coverage per book (all three sources)

| # | Book | OverDrive queries | OverDrive author pass | Onleihe | Catalogue |
|---|---|---|---|---|---|
| 1 | The Complete Plays | The Complete Plays; The Complete Plays Orton (+Orton plays; Loot Orton; What the Butler Saw) | yes | yes | The Complete Plays Orton; The Complete Plays |
| 2 | Things Fall Apart | Things Fall Apart; Things Fall Apart Achebe (+Achebe; Things Fall Apart Achebe) | yes | yes | Things Fall Apart Achebe; Things Fall Apart |
| 3 | Uncle Tom's Cabin | Uncle Tom's Cabin; Uncle Tom's Cabin Stowe (+Uncle Tom cabin; Stowe) | yes | yes | Uncle Tom's Cabin Stowe; Uncle Tom's Cabin |
| 4 | Gilead | Gilead; Gilead Robinson | yes | yes | Gilead Robinson; Gilead |
| 5 | White Teeth | White Teeth; White Teeth Smith | yes | yes | White Teeth Smith; White Teeth |
| 6 | Time Shelter | Time Shelter; Time Shelter Gospodinov; Timeshelter (+Gospodinov; Time Shelter novel) | yes | yes | Time Shelter Gospodinov; Time Shelter |
| 7 | Do Androids Dream of Electric Sheep? | Do Androids Dream of Electric Sheep?; Do Androids Dream of Electric Sheep? Dick | yes | yes | Do Androids Dream of Electric Sheep? Dick; Do Androids Dream of Electric Sheep? |
| 8 | The Man in the High Castle | The Man in the High Castle; The Man in the High Castle Dick (+Man in the High Castle; High Castle Dick) | yes | yes | The Man in the High Castle Dick; The Man in the High Castle |
| 9 | No Country for Old Men | No Country for Old Men; No Country for Old Men McCarthy (+No Country; McCarthy No Country) | yes | yes | No Country for Old Men McCarthy; No Country for Old Men |
| 10 | Midnight's Children | Midnight's Children; Midnight's Children Rushdie (+Midnight's Children; Midnights Children Rushdie) | yes | yes | Midnight's Children Rushdie; Midnight's Children |
| 11 | Waiting for the Barbarians | Waiting for the Barbarians; Waiting for the Barbarians Coetzee (+Barbarians Coetzee; Coetzee) | yes | yes | Waiting for the Barbarians Coetzee; Waiting for the Barbarians |
| 12 | Charlotte's Web | Charlotte's Web; Charlotte's Web White (+Charlotte Web; White Charlotte) | yes | yes | Charlotte's Web White; Charlotte's Web |
| 13 | Plainsong | Plainsong; Plainsong Haruf (+Haruf; Plainsong Haruf) | yes | yes | Plainsong Haruf; Plainsong |
| 14 | The Stand | The Stand; The Stand King | yes | yes | The Stand King; The Stand |
| 15 | How to Change Your Mind: The New Science of Psychedelics | How to Change Your Mind; How to Change Your Mind Pollan | yes | yes | How to Change Your Mind Pollan; How to Change Your Mind |
| 16 | The Bell Jar | The Bell Jar; The Bell Jar Plath | yes | yes | The Bell Jar Plath; The Bell Jar |
| 17 | The Amazing Adventures of Kavalier & Clay | The Amazing Adventures of Kavalier & Clay; The Amazing Adventures of Kavalier & Clay Chabon (+Kavalier Clay; Chabon) | yes | yes | The Amazing Adventures of Kavalier & Clay Chabon; The Amazing Adventures of Kavalier & Clay |
| 18 | The Shining | The Shining; The Shining King | yes | yes | The Shining King; The Shining |
| 19 | Middlesex | Middlesex; Middlesex Eugenides | yes | yes | Middlesex Eugenides; Middlesex |
| 20 | Austerlitz | Austerlitz; Austerlitz Sebald (+Sebald; Austerlitz Sebald) | yes | yes | Austerlitz Sebald; Austerlitz |
| 21 | Zen and the Art of Motorcycle Maintenance: An Inquiry into Values | Zen and the Art of Motorcycle Maintenance; Zen and the Art of Motorcycle Maintenance Pirsig (+Pirsig; Motorcycle Maintenance) | yes | yes | Zen and the Art of Motorcycle Maintenance Pirsig; Zen and the Art of Motorcycle Maintenance |
| 22 | The Unbearable Lightness of Being | The Unbearable Lightness of Being; The Unbearable Lightness of Being Kundera | yes | yes | The Unbearable Lightness of Being Kundera; The Unbearable Lightness of Being |
| 23 | A Confederacy of Dunces | A Confederacy of Dunces; A Confederacy of Dunces Toole (+Dunces; Toole) | yes | yes | A Confederacy of Dunces Toole; A Confederacy of Dunces |
| 24 | The Human Stain | The Human Stain; The Human Stain Roth (+Human Stain; Roth Human Stain) | yes | yes | The Human Stain Roth; The Human Stain |
| 25 | The Whites | The Whites; The Whites Price (+The Whites Price; Price Whites) | yes | yes | The Whites Price; The Whites |
| 26 | Great Expectations | Great Expectations; Great Expectations Dickens | yes | yes | Great Expectations Dickens; Great Expectations |
| 27 | Lullaby | Lullaby; Lullaby Slimani; The Perfect Nanny (+Slimani; Perfect Nanny) | yes | yes | Lullaby Slimani; Lullaby |
| 28 | Spring | Spring; Spring Smith (+Ali Smith Spring; Smith Spring novel) | yes | yes | Spring Smith; Spring |
| 29 | Fear and Loathing in Las Vegas | Fear and Loathing in Las Vegas; Fear and Loathing in Las Vegas Thompson (+Fear Loathing; Thompson Las Vegas) | yes | yes | Fear and Loathing in Las Vegas Thompson; Fear and Loathing in Las Vegas |
| 30 | Atonement | Atonement; Atonement McEwan | yes | yes | Atonement McEwan; Atonement |
| 31 | We Need to Talk About Kevin | We Need to Talk About Kevin; We Need to Talk About Kevin Shriver | yes | yes | We Need to Talk About Kevin Shriver; We Need to Talk About Kevin |
| 32 | A Good Man Is Hard to Find and Other Stories | A Good Man Is Hard to Find and Other Stories; A Good Man Is Hard to Find and Other Stories O'Connor; A Good Man Is Hard to Find (+Good Man Hard Find; O Connor stories) | yes | yes | A Good Man Is Hard to Find and Other Stories O'Connor; A Good Man Is Hard to Find and Other Stories |
| 33 | Amsterdam | Amsterdam; Amsterdam McEwan (+Amsterdam McEwan; McEwan Amsterdam) | yes | yes | Amsterdam McEwan; Amsterdam |
| 34 | American Pastoral | American Pastoral; American Pastoral Roth | yes | yes | American Pastoral Roth; American Pastoral |
| 35 | Knots & Crosses | Knots & Crosses; Knots & Crosses Rankin (+Rankin Knots; Inspector Rebus) | yes | yes | Knots & Crosses Rankin; Knots & Crosses |
| 36 | The Color Purple | The Color Purple; The Color Purple Walker | yes | yes | The Color Purple Walker; The Color Purple |
| 37 | The House of the Spirits | The House of the Spirits; The House of the Spirits Allende (+House Spirits; Allende) | yes | yes | The House of the Spirits Allende; The House of the Spirits |
| 38 | The Joke | The Joke; The Joke Kundera (+Kundera Joke; The Joke Kundera) | yes | yes | The Joke Kundera; The Joke |
| 39 | Vernon Subutex 1 | Vernon Subutex 1; Vernon Subutex 1 Despentes (+Despentes; Vernon Subutex) | yes | yes | Vernon Subutex 1 Despentes; Vernon Subutex 1 |
| 40 | The Poisonwood Bible | The Poisonwood Bible; The Poisonwood Bible Kingsolver (+Poisonwood; Kingsolver) | yes | yes | The Poisonwood Bible Kingsolver; The Poisonwood Bible |
| 41 | Atomised | Atomised; Atomised Houellebecq; The Elementary Particles (+Houellebecq; Elementary Particles) | yes | yes | Atomised Houellebecq; Atomised |
| 42 | Independence Day | Independence Day; Independence Day Ford (+Independence Day Ford; Ford Independence) | yes | yes | Independence Day Ford; Independence Day |
| 43 | The Glass Hotel | The Glass Hotel; The Glass Hotel Mandel (+Glass Hotel; Mandel) | yes | yes | The Glass Hotel Mandel; The Glass Hotel |
| 44 | The Death of Ivan Ilyich and Other Stories | The Death of Ivan Ilyich and Other Stories; The Death of Ivan Ilyich and Other Stories Tolstoy; The Death of Ivan Ilyich | yes | yes | The Death of Ivan Ilyich and Other Stories Tolstoy; The Death of Ivan Ilyich and Other Stories |
| 45 | The Waiter | The Waiter; The Waiter Faldbakken (+Faldbakken; The Waiter novel) | yes | yes | The Waiter Faldbakken; The Waiter |
| 46 | The History Boys | The History Boys; The History Boys Bennett (+History Boys; Bennett History Boys) | yes | yes | The History Boys Bennett; The History Boys |
| 47 | The Woman Who Walked Into Doors | The Woman Who Walked Into Doors; The Woman Who Walked Into Doors Doyle (+Roddy Doyle; Paula Spencer; Woman Doors) | yes | yes | The Woman Who Walked Into Doors Doyle; The Woman Who Walked Into Doors |
| 48 | The Living Sea of Waking Dreams | The Living Sea of Waking Dreams; The Living Sea of Waking Dreams Flanagan (+Flanagan; Living Sea) | yes | yes | The Living Sea of Waking Dreams Flanagan; The Living Sea of Waking Dreams |
| 49 | The Watcher in the Shadows | The Watcher in the Shadows; The Watcher in the Shadows Zafón (+Zafon; Watcher Shadows) | yes | yes | The Watcher in the Shadows Zafón; The Watcher in the Shadows |
| 50 | Everything Is Illuminated | Everything Is Illuminated; Everything Is Illuminated Foer (+Illuminated; Foer) | yes | yes | Everything Is Illuminated Foer; Everything Is Illuminated |
| 51 | The Corrections | The Corrections; The Corrections Franzen (+Corrections; Franzen Corrections) | yes | yes | The Corrections Franzen; The Corrections |
| 52 | The Narrow Road to the Deep North | The Narrow Road to the Deep North; The Narrow Road to the Deep North Flanagan | yes | yes | The Narrow Road to the Deep North Flanagan; The Narrow Road to the Deep North |
| 53 | Station Eleven | Station Eleven; Station Eleven Mandel | yes | yes | Station Eleven Mandel; Station Eleven |
| 54 | The Little Goblin Girl | The Little Goblin Girl; The Little Goblin Girl Hymen (+Goblin Girl; Hymen) | yes | yes | The Little Goblin Girl Hymen; The Little Goblin Girl |
| 55 | The Luminaries | The Luminaries; The Luminaries Catton | yes | yes | The Luminaries Catton; The Luminaries |
| 56 | Empire of the Sun | Empire of the Sun; Empire of the Sun Ballard | yes | yes | Empire of the Sun Ballard; Empire of the Sun |
| 57 | Notes from Underground | Notes from Underground; Notes from Underground Dostoevsky (+Dostoevsky; Notes Underground) | yes | yes | Notes from Underground Dostoevsky; Notes from Underground |
| 58 | Celestial Bodies | Celestial Bodies; Celestial Bodies Alharthi (+Alharthi; Celestial Bodies) | yes | yes | Celestial Bodies Alharthi; Celestial Bodies |
| 59 | Freedom | Freedom; Freedom Franzen | yes | yes | Freedom Franzen; Freedom |
| 60 | The Blind Assassin | The Blind Assassin; The Blind Assassin Atwood (+Blind Assassin; Atwood) | yes | yes | The Blind Assassin Atwood; The Blind Assassin |
| 61 | Wolf Hall | Wolf Hall; Wolf Hall Mantel | yes | yes | Wolf Hall Mantel; Wolf Hall |
| 62 | The Sea | The Sea; The Sea Banville | yes | yes | The Sea Banville; The Sea |
| 63 | The Sense of an Ending | The Sense of an Ending; The Sense of an Ending Barnes (+Sense of an Ending; Barnes) | yes | yes | The Sense of an Ending Barnes; The Sense of an Ending |
| 64 | The Dying Animal | The Dying Animal; The Dying Animal Roth (+Dying Animal; Roth Dying) | yes | yes | The Dying Animal Roth; The Dying Animal |

## Verified records (positive results only)

| # | Book | Platform | Title on record | Edition | Runtime | Narrator | Language | Format | Copies/holds | Displayed status | Evidence link |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | Uncle Tom's Cabin | Onleihe (VÖBB) | Uncle Tom's cabin | — | ['1076'] | — | Englisch | eAudio Stream | 1/1 / 0 holds | Jetzt ausleihen; Verfügbar | https://voebb.onleihe.de/berlin/frontend/mediaInfo,0-0-363593406-200-0-0-0-0-0-0-0.html |
| 4 | Gilead | OverDrive/Libby (VÖBB) | Gilead | Unabridged | 08:55:02 | Tim Jerome | en | OverDrive Listen audiobook, MP3 audiobook | 0/2 / 4 holds | 0 of 2 copies available; Wait time: About 5 weeks; Place a hold | https://voebb.overdrive.com/media/335520 |
| 5 | White Teeth | OverDrive/Libby (VÖBB) | White Teeth | Unabridged | 18:38:28 | Pippa Bennett-Warner, Ray Panthaki, Lenny Henry, Sagar Arya | en | OverDrive Listen audiobook, MP3 audiobook | 0/2 / 2 holds | 0 of 2 copies available; Wait time: About 3 weeks; Place a hold | https://voebb.overdrive.com/media/3886722 |
| 7 | Do Androids Dream of Electric Sheep? | OverDrive/Libby (VÖBB) | Do Androids Dream of Electric Sheep? | Unabridged | 09:12:32 | Scott Brick | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 3 holds | Wait time: About 8 weeks; Place a hold | https://voebb.overdrive.com/media/123544 |
| 14 | The Stand | OverDrive/Libby (VÖBB) | The Stand | Unabridged | 47:47:51 | Grover Gardner | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 4 holds | Wait time: About 10 weeks; Place a hold | https://voebb.overdrive.com/media/589885 |
| 15 | How to Change Your Mind: The New Science of Psychedelics | OverDrive/Libby (VÖBB) | How to Change Your Mind | Unabridged | 13:35:45 | Michael Pollan | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 1 holds | Wait time: About 4 weeks; Place a hold | https://voebb.overdrive.com/media/3619131 |
| 15 | How to Change Your Mind: The New Science of Psychedelics | OverDrive/Libby (VÖBB) | How to Change Your Mind | Unabridged | 13:41:01 | Michael Pollan | en | OverDrive Listen audiobook, MP3 audiobook | 0/3 / 0 holds | 0 of 3 copies available; Wait time: Available soon; Place a hold | https://voebb.overdrive.com/media/3946564 |
| 16 | The Bell Jar | OverDrive/Libby (VÖBB) | The Bell Jar | Unabridged | 07:25:05 | Maggie Gyllenhaal | en | OverDrive Listen audiobook, MP3 audiobook | 0/4 / 6 holds | 0 of 4 copies available; Wait time: About 4 weeks; Place a hold | https://voebb.overdrive.com/media/4554951 |
| 18 | The Shining | OverDrive/Libby (VÖBB) | The Shining | Unabridged | 15:50:30 | Campbell Scott | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 4 holds | Wait time: About 10 weeks; Place a hold | https://voebb.overdrive.com/media/858758 |
| 19 | Middlesex | OverDrive/Libby (VÖBB) | Middlesex | Unabridged | 21:21:21 | Kristoffer Tabori | en | OverDrive Listen audiobook, MP3 audiobook | 0/3 / 0 holds | 0 of 3 copies available; Wait time: Available soon; Place a hold | https://voebb.overdrive.com/media/86990 |
| 22 | The Unbearable Lightness of Being | OverDrive/Libby (VÖBB) | The Unbearable Lightness of Being | edition not stated in record | 09:36:55 | Richmond Hoxie | en | OverDrive Listen audiobook, MP3 audiobook | 0/2 / 0 holds | 0 of 2 copies available; Wait time: Available soon; Place a hold | https://voebb.overdrive.com/media/3995095 |
| 26 | Great Expectations | OverDrive/Libby (VÖBB) | Great Expectations | Unabridged | 18:32:28 | Simon Prebble | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 0 holds | Wait time: About 2 weeks; Place a hold | https://voebb.overdrive.com/media/66481 |
| 26 | Great Expectations | Onleihe (VÖBB) | Great expectations | — | ['1203'] | — | Englisch | eAudio Stream | 1/1 / 0 holds | Jetzt ausleihen; Verfügbar | https://voebb.onleihe.de/berlin/frontend/mediaInfo,0-0-363593207-200-0-0-0-0-0-0-0.html |
| 30 | Atonement | OverDrive/Libby (VÖBB) | Atonement | Abridged | 06:03:02 | Josephine Bailey | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 0 holds | Wait time: About 2 weeks; Place a hold | https://voebb.overdrive.com/media/122671 |
| 30 | Atonement | OverDrive/Libby (VÖBB) | Atonement | Unabridged | 12:26:31 | Carole Boyd | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 0 holds | Wait time: About 2 weeks; Place a hold | https://voebb.overdrive.com/media/3171769 |
| 31 | We Need to Talk About Kevin | OverDrive/Libby (VÖBB) | We Need to Talk About Kevin | Unabridged | 16:09:57 | Coleen Marlo | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 1 holds | Wait time: About 4 weeks; Place a hold | https://voebb.overdrive.com/media/681057 |
| 34 | American Pastoral | OverDrive/Libby (VÖBB) | American Pastoral | Unabridged | 15:31:10 | Ron Silver | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 2 holds | Wait time: About 6 weeks; Place a hold | https://voebb.overdrive.com/media/122669 |
| 36 | The Color Purple | OverDrive/Libby (VÖBB) | The Color Purple | Unabridged | 07:56:57 | Alice Walker | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 1 holds | Wait time: About 4 weeks; Place a hold | https://voebb.overdrive.com/media/9920633 |
| 52 | The Narrow Road to the Deep North | OverDrive/Libby (VÖBB) | The Narrow Road to the Deep North | Unabridged | 14:59:47 | David Linski | en | OverDrive Listen audiobook, MP3 audiobook | 1/2 / 0 holds | 1 of 2 copies available; Borrow | https://voebb.overdrive.com/media/1817988 |
| 53 | Station Eleven | OverDrive/Libby (VÖBB) | Station Eleven | Unabridged | 10:41:02 | Kirsten Potter | en | OverDrive Listen audiobook, MP3 audiobook | 0/2 / 6 holds | 0 of 2 copies available; Wait time: About 7 weeks; Place a hold | https://voebb.overdrive.com/media/1499830 |
| 56 | Empire of the Sun | OverDrive/Libby (VÖBB) | Empire of the Sun | Abridged | 03:08:15 | Jeremy Irons | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 2 holds | Wait time: About 6 weeks; Place a hold | https://voebb.overdrive.com/media/143657 |
| 59 | Freedom | OverDrive/Libby (VÖBB) | Freedom | Unabridged | 24:09:28 | David Ledoux | en | OverDrive Listen audiobook, MP3 audiobook | 1/2 / 0 holds | 1 of 2 copies available; Borrow | https://voebb.overdrive.com/media/389422 |
| 61 | Wolf Hall | OverDrive/Libby (VÖBB) | Wolf Hall | Abridged | 07:11:43 | Dan Stevens | en | OverDrive Listen audiobook, MP3 audiobook | 1/3 / 0 holds | 1 of 3 copies available; Borrow | https://voebb.overdrive.com/media/1004466 |
| 61 | Wolf Hall | OverDrive/Libby (VÖBB) | Wolf Hall | Unabridged | 24:17:31 | Simon Slater | en | OverDrive Listen audiobook, MP3 audiobook | 0/1 / 1 holds | Wait time: About 4 weeks; Place a hold | https://voebb.overdrive.com/media/3836264 |

## Other-language audiobooks and physical CDs (recorded separately)

| # | Book | Other-language / physical audio holdings |
|---|---|---|
| 1 | The Complete Plays | — |
| 2 | Things Fall Apart | — |
| 3 | Uncle Tom's Cabin | Other-language eAudio (Onleihe): Onkel Toms Hütte (German-language edition, language not shown on list card) | physical CD: Onkel Toms Hütte : [Hörbuch] ; [CD] — Harriet Beecher-Stowe. Gelesen von Bodo Primus. - Ueberreuter (Verfügbar) | physical CD: Onkel Toms Hütte : [Hörbuch] ; [CD] — Harriet Beecher Stowe. Gesamtleitung: Jürgen Nola, Markus Steffen, Marco Nola. B (Verfügbar) | physical CD: Onkel Toms Hütte = [Uncle Tom's cabin — Harriet Beecher Stowe. Gesprochen von Brigitte Trübenbach. - Hörmedia-Audioverl. (Verfügbar) |
| 4 | Gilead | physical CD: Gilead : [Hörbuch] — Marilynne Robinson ; Otto Mellies liest ; aus dem amerikanischen Englisch von Ud (Verfügbar) |
| 5 | White Teeth | — |
| 6 | Time Shelter | — |
| 7 | Do Androids Dream of Electric Sheep? | physical CD: Blade Runner : träumen Androiden ; Hörspiel ; [Hörbuch] ; [C — Philip K. Dick. Hörspielbearb. und Regie: Marina Dietz. Mit Udo Wachtveitl ; Sop (Verfügbar) |
| 8 | The Man in the High Castle | Other-language eAudio (OverDrive): The Man in the High Castle--Das Orakel vom Berge [de], argon, 0/2 copies | physical CD: The man in the high castle : [Hörbuch] ; [CD] — Philip K. Dick. Read by Tom Weiner. - Unabridged. - Blackstone Audio (Verfügbar) |
| 9 | No Country for Old Men | physical CD: Kein Land für alte Männer : [Hörbuch] ; [CD] — Christian Brückner liest Cormac McCarthy. Regie: Waltraut Brückner. Dt. von Niko (Verfügbar) | physical CD: No country for old men : [Hörbuch] ; [CD] — Cormac McCarthy [Textverf.] ; Tom Stechschulte [Sprecher/in]. - Unabridged. - Re (Verfügbar) |
| 10 | Midnight's Children | — |
| 11 | Waiting for the Barbarians | — |
| 12 | Charlotte's Web | physical CD: Wilbur und Charlotte : Kinderhörspiel ; [CD] ; [Hörbuch] — Elwyn Brooks White. Sprecher: Hermann Beyer ; Sophie Rois ; Jens Wawrczeck ... H (Verfügbar) | physical CD: Charlotte's Web : [Hörbuch] ; [CD] — Elwyn B. White, read by the author. - Unabridged. - Listening Library (Zurzeit nicht verfügbar) |
| 13 | Plainsong | Other-language eAudio (Onleihe): Das Band, das uns hält (German-language edition, language not shown on list card) |
| 14 | The Stand | Other-language eAudio (OverDrive): The Stand--Das letzte Gefecht [de], Lübbe Audio, 0/2 copies |
| 15 | How to Change Your Mind: The New Science of Psychedelics | — |
| 16 | The Bell Jar | — |
| 17 | The Amazing Adventures of Kavalier & Clay | — |
| 18 | The Shining | physical CD: The shining — Stephen King ; read by Campbell Scott ; prducer and director: Kelly Gildea. - Un (Verfügbar) |
| 19 | Middlesex | physical CD: Middlesex : [Hörbuch] ; [CD] — Jeffrey Eugenides. Gelesen von Ulrich Matthes. Aus dem Amerik. von Eike Schönfel (Verfügbar) |
| 20 | Austerlitz | Other-language eAudio (OverDrive): Austerlitz [de], der Hörverlag, 0/1 copies | physical CD: Austerlitz : [Hörbuch] — W. G. Sebald. - Vollständige Lesung/O-Ton. - Der Hörverlag (Verfügbar) | physical CD: Austerlitz : [Hörbuch] ; [CD] — W. G. Sebald. Hörspielbearb. und Regie: Stefan Kanis. Mit Ulrich Matthes ; Ernst (Verfügbar) |
| 21 | Zen and the Art of Motorcycle Maintenance: An Inquiry into Values | — |
| 22 | The Unbearable Lightness of Being | — |
| 23 | A Confederacy of Dunces | — |
| 24 | The Human Stain | physical CD: Der menschliche Makel : [Hörbuch] ; [CD] — Philip Roth. Bearb.: Valerie Stiegele. Regie: Norbert Schaeffer. Sprecher: Jürge (Verfügbar) |
| 25 | The Whites | physical CD: Die Unantastbaren : [Hörbuch] — Richard Price. Lesung mit Oliver Rohrbeck und David Nathan. Bearbeitung: Marie K (Verfügbar) |
| 26 | Great Expectations | physical CD: Great expectations : [Hörbuch] ; [CD] — Charles Dickens. Narrated by Martin Jarvis. - Unabridged. - BBC Audiobooks Ameri (Verfügbar) |
| 27 | Lullaby | — |
| 28 | Spring | — |
| 29 | Fear and Loathing in Las Vegas | physical CD: Fear and loathing in Las Vegas : [Hörbuch] — Hunter S. Thompson. Mit Martin Semmelrogge ; Günther Amendt ; Smudo... Lesefassu (Verfügbar) |
| 30 | Atonement | Other-language eAudio (Onleihe): Abbitte (German-language edition, language not shown on list card) | physical CD: Abbitte : [Hörbuch] — Ian McEwan. Sprecherin: Barbara Auer. Aus dem Engl. von Bernhard Robben. - Gekür (Verfügbar) | physical CD: Abbitte : Roman ; [Hörbuch] ; [CD] — Ian McEwan. Gelesen von Barbara Auer. Aus dem Engl. von Bernhard Robben. - Gekür (Verfügbar) | physical CD: Atonement : [Hörbuch] ; [CD] — Ian McEwan. Read by Carole Boyd. - Complete & unabridged. - AudioGo (Verfügbar) | physical CD: Atonement : [Hörbuch] ; [CD] — Ian McEwan. Read by Isla Blair. - Abridged. - HarperCollins (Verfügbar) |
| 31 | We Need to Talk About Kevin | — |
| 32 | A Good Man Is Hard to Find and Other Stories | — |
| 33 | Amsterdam | — |
| 34 | American Pastoral | — |
| 35 | Knots & Crosses | — |
| 36 | The Color Purple | — |
| 37 | The House of the Spirits | — |
| 38 | The Joke | — |
| 39 | Vernon Subutex 1 | Other-language eAudio (OverDrive): Das Leben des Vernon Subutex 1 [de], Der Audio Verlag, 0/1 copies | Other-language eAudio (Onleihe): Das Leben des Vernon Subutex (German-language edition, language not shown on list card) | Other-language eAudio (Onleihe): Das Leben des Vernon Subutex 2 (German-language edition, language not shown on list card) | physical CD: Vernon Subutex 1 : [Hörbuch] — Virginie Despentes. Lu par Jacques Frantz. - Audiolib (Verfügbar) |
| 40 | The Poisonwood Bible | — |
| 41 | Atomised | — |
| 42 | Independence Day | — |
| 43 | The Glass Hotel | physical CD: The glass hotel : a novel — Emily St. John Mandel ; Dylan Moore. - Random House (Zurzeit nicht verfügbar) |
| 44 | The Death of Ivan Ilyich and Other Stories | — |
| 45 | The Waiter | — |
| 46 | The History Boys | — |
| 47 | The Woman Who Walked Into Doors | — |
| 48 | The Living Sea of Waking Dreams | — |
| 49 | The Watcher in the Shadows | — |
| 50 | Everything Is Illuminated | physical CD: Alles ist erleuchtet : [Hörbuch] ; [CD] — Jonathan Safran Foer. Gelesen von Boris Aljinovic und Florian Lukas. - Universal (Verfügbar) |
| 51 | The Corrections | physical CD: Die Korrekturen : [Hörbuch] — Jonathan Franzen. Gelesen von Ulrich Pleitgen. Regie: Margrit Osterwold. - Gekür (Verfügbar) | physical CD: Ulrich Pleitgen liest "Die Korrekturen" — Jonathan Franzen. Regie: Margrit Osterwold. Aus dem Amerikan. von Bettina Abarba (Verfügbar) |
| 52 | The Narrow Road to the Deep North | physical CD: The narrow road to the deep north : a novel ; [Hörbuch] ; [M — Richard Flanagan. Read by David Atlas. - unabridged. - Blackstone Audio (Verfügbar) | physical CD: The narrow road to the deep north : a novel ;  [Hörbuch] ; [ — Richard Flanagan. Read by David Atlas. - Unabridged. - Blackstone Audio (Verfügbar) |
| 53 | Station Eleven | physical CD: Station eleven : a novel ; [Hörbuch] ; [CD] — Emily St. John Mandel. Read by Kirsten Potter. - Unabridged. - Random House Audi (Verfügbar) | physical CD: Das Licht der letzten Tage : Roman ; [Hörbuch] ; [CD] — Emily St.John Mandel ; Stephanie Keller ; Deutsch von Wibke Kuhn. - gekürzte Les (Verfügbar) |
| 54 | The Little Goblin Girl | — |
| 55 | The Luminaries | Other-language eAudio (Onleihe): Der Wald (German-language edition, language not shown on list card) |
| 56 | Empire of the Sun | — |
| 57 | Notes from Underground | — |
| 58 | Celestial Bodies | — |
| 59 | Freedom | physical CD: Freedom : [Hörbuch] ; [CD] — Jonathan Franzen. Read by David Ledoux. - Unabridged. - Harper Collins (Verfügbar) | physical CD: Freiheit : [Hörbuch] ; [CD] — Jonathan Franzen. Gelesen von Ulrich Matthes. Regie: Ralph Schäfer. Prod.: rbb . (Verfügbar) |
| 60 | The Blind Assassin | — |
| 61 | Wolf Hall | physical CD: Wölfe : [Hörbuch] ; [CD] — Hilary Mantel. Sprecher: Frank Stöckle. - Gekürzte Lesung. - Audiobuch (Verfügbar) | physical CD: Wolf hall : a novel ; [Hörbuch] ; [CD] — Hilary Mantel. Read by Simon Slater. - unabridged. - Macmillan Audio (Verfügbar) |
| 62 | The Sea | physical CD: Die See : [Hörbuch] ; [CD] — John Banville. Sprecher: Burghart Klaußner. Regie: Felix Partenzi. - Ungekürzte  (Verfügbar) |
| 63 | The Sense of an Ending | physical CD: Vom Ende einer Geschichte : [Hörbuch] ; [CD] — Julian Barnes. Manfred Zapatka liest. Regie: Ralf Ebel. Aus dem Engl. von Gertra (Verfügbar) | physical CD: The sense of an ending : [Hörbuch] ; [CD] — Julian Barnes. Narrated by Richard Morant. - Unabridged. - AudioGo (Verfügbar) |
| 64 | The Dying Animal | physical CD: Das sterbende Tier : [Hörbuch] — Philip Roth. Gelesen von Max Volkert Martens. Aus dem Amerik. von Dirk van Gunst (Verfügbar) |

## Web-search fallback (step E of the protocol)

Queries run against the indexed VÖBB collection (plus `site:voebb.overdrive.com "<title>" "<surname>"` variants):

| Query | Outcome |
|---|---|
| `site:voebb.overdrive.com "Things Fall Apart" audiobook` | only "When Things Fall Apart" (Pema Chödrön) — a different work; no Achebe audiobook |
| `site:voebb.overdrive.com "Midnight's Children" Rushdie audiobook` | only Salman Rushdie's "Knife" — not the requested novel |
| `site:voebb.overdrive.com "The Corrections" "Franzen" audiobook` | no results |
| `site:voebb.overdrive.com "The Blind Assassin" "Atwood" audiobook` | no results |
| `site:voebb.overdrive.com "A Confederacy of Dunces" audiobook` | no results |
| `site:voebb.overdrive.com "The Poisonwood Bible" audiobook` | no results |
| `site:voebb.overdrive.com "Zen and the Art of Motorcycle Maintenance" audiobook` | no results |
| `site:voebb.overdrive.com "Austerlitz" Sebald audiobook` | no results |
| `site:voebb.overdrive.com "The Phoenix Project" audiobook (control, unrelated list)` | surfaced only "AI For Good" (Josh Tyrangiel) — an unrelated VÖBB record, no new target titles |

## Method notes and special matching rules applied

- **The Complete Plays** (01): only other authors' "Complete plays" and a Shakespeare CD set were found; individual Orton plays would have been partial matches only — none exists, so the row is NOT_FOUND.
- **The Stand** (14): the VÖBB English record is the complete & uncut edition (Unabridged, 47:47:51, Grover Gardner). No English abridged or dramatised audiobook is held; a German eAudio of the same novel ("Das letzte Gefecht") is held and listed separately.
- **Vernon Subutex 1** (39): volume 1 verified for the French physical CD ("Vernon Subutex 1", Audiolib) and for the German eAudio "Das Leben des Vernon Subutex 1" (Der Audio Verlag). No English edition in any source.
- **Lullaby** (27): also searched as "The Perfect Nanny" (same novel) — no English audiobook; the only Slimani audiobook held is "Adele".
- **Atomised** (41): also searched as "The Elementary Particles" (same novel) — no English audiobook; the only Houellebecq English audiobook held is "Serotonin".
- **Time Shelter** (06): also searched as "Timeshelter" — no English audiobook; eBook only.
- **The Bell Jar** (16): source-photo caveat preserved — the title was partly obscured in the photo, the title was identified as *The Bell Jar* by Sylvia Plath and confirmed on the record.
- **A Good Man Is Hard to Find and Other Stories** (32): neither the collection nor the individual story exists as an audiobook in VÖBB; no other contents list was substituted.
- **The Death of Ivan Ilyich and Other Stories** (44): only the single novella "The Death of Ivan Ilyich" (Naxos, 2:51:09) is held (0/1, 2 holds) — a partial match, not the requested collection, so the row is NOT_FOUND.
- Same-title strangers were rejected by author check: "The Luminaries" (Susan Dennard ≠ Eleanor Catton), "Freedom" (Angela Merkel ≠ Jonathan Franzen), "The Sea" (Jack London / Katee Robert ≠ John Banville), "The Shining Girls" (Lauren Beukes ≠ Stephen King), "The Stand-Up Groomsman" (Jackie Lau ≠ Stephen King).

## Limitations

- Borrowing status is the public, signed-out view. A VÖBB card holder sees the same copy counts; holds already placed by the user are not visible anonymously.
- OverDrive's keyword search is fuzzy; to rule titles out reliably every book was also matched against a complete sweep of the VÖBB OverDrive audiobook catalogue (22,266 records across all 195 subjects, 7,509 of them English).
- The main catalogue (aDISWeb) search is title/author based; its "E-Audio" rows mirror the OverDrive collection, and "CD" rows are physical media — they are listed in the separate column, never counted as digital availability.
- Edition flags come from the record itself; where a record states no edition (e.g. 22 The Unbearable Lightness of Being) this is noted instead of guessing.
