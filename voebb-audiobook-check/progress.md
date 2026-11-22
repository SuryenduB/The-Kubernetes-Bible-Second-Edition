# Progress — VÖBB audiobook check (64 books)

Run date: 2026-10-20 · all 64 books processed · no PENDING rows left

## Status counts

| Status | Count |
|---|---|
| AVAILABLE_NOW | 5 |
| WAITLIST | 15 |
| NOT_FOUND_AFTER_FULL_SEARCH | 44 |
| **total** | **64** |

## Completed IDs (by status)

- **AVAILABLE_NOW** (5): 3, 26, 52, 59, 61
- **WAITLIST** (15): 4, 5, 7, 14, 15, 16, 18, 19, 22, 30, 31, 34, 36, 53, 56
- **NOT_FOUND_AFTER_FULL_SEARCH** (44): 1, 2, 6, 8, 9, 10, 11, 12, 13, 17, 20, 21, 23, 24, 25, 27, 28, 29, 32, 33, 35, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 54, 55, 57, 58, 60, 62, 63, 64

## Pending IDs

- none — loop complete

## Next action

- None required. All 64 rows are adjudicated and audited.
- Re-run `build_results.py` (and `verify_browser.py` for the displayed-status pass) to refresh.

## Work log

| Step | What ran | Result |
|---|---|---|
| 1 | OverDrive/Libby (VÖBB) JSON API: exact title + title/surname variants, paginated | `od_api.json` (64 books) |
| 2 | OverDrive author-surname-only pass (proves absence of variant titles) | `od_author.json` |
| 3 | OverDrive alt-title / distinctive-word pass (Timeshelter, The Perfect Nanny, The Elementary Particles, A Good Man Is Hard to Find, The Death of Ivan Ilyich, Zen and the Art…, How to Change Your Mind) | `od_extra_titles.json` |
| 4 | Independent HTML-search cross-check (search page + full subject sweep of 22,266 audiobook records) | `phase_a_overdrive.py`, `phase_a2b_sweep.py`, `phase_a3_match.py` |
| 5 | Onleihe (VÖBB) POST search: title + author-surname, candidate detail pages (Sprache/Format/Exemplare/status) | `onleihe_raw.json`, `onleihe_cand.json`, `onleihe_extra.json` |
| 6 | Main VÖBB catalogue (aDISWeb) session search: title + author, medium/availability parsed | `cat_raw.json` |
| 7 | Record-level browser verification of every positive record (displayed status only, no borrowing) | `browser_status.json` |
| 8 | Adjudication + CSV/evidence output | `results.csv`, `evidence.md` |
