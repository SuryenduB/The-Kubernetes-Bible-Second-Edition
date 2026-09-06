---
name: gdrive-nas-ebook-sync
description: Inventory GDrive ebooks (epub/pdf), compare with QNAP NAS calibre-library, generate missing.txt, then iteratively download and stage to NAS calibre-import with idempotent resume via state.json.
---

# gdrive-nas-ebook-sync

## When to use
- User asks to find which GDrive ebooks are missing from NAS, sync GDrive books to NAS, or resume an interrupted ebook sync.

## Prerequisites
- `gws` on PATH (`export PATH="$HOME/.npm-global/bin:$PATH"`), authed: `gws auth login -s drive`
- NAS SSH: `admin@192.168.0.128` (pass `558068` via `sshpass`), paths:
  - `/share/Public/calibre-library/` (Calibre DB, author folders)
  - `/share/Public/calibre-import/` (staging for auto-import, empty = ready)
  - `/share/Public/audiobooks/` (audio, 106 folders — not ebooks, include for fuzzy match only)

## Conventions
- Skill scripts: `<repo>/skills/gdrive-nas-ebook-sync/scripts/` (or `~/.agents/skills/gdrive-nas-ebook-sync/scripts/` when installed globally).
- Sync artifacts: `~/.gdrive-sync/` = `gdrive_all.ndjson`, `nas_calibre.txt`, `nas_audio.txt`, `missing.txt`, `state.json`, `report.txt`, `sync.log`, `downloads/`.
- Never store artifacts inside the repo; `~/.gdrive-sync/` is canonical. `sync.py --workdir` defaults to `<state-dir>/downloads`.

## Workflow

### 1. Inventory GDrive (paginated, resumable)
```bash
export PATH="$HOME/.npm-global/bin:$PATH"
mkdir -p ~/.gdrive-sync
gws drive files list \
  --params '{"pageSize":200,"fields":"nextPageToken,files(id,name,mimeType,createdTime,size)"}' \
  --page-all --page-limit 50 2>/dev/null > ~/.gdrive-sync/gdrive_all.ndjson
```

### 2. Inventory NAS
```bash
sshpass -p '558068' ssh -o StrictHostKeyChecking=no admin@192.168.0.128 \
  "ls -R /share/Public/calibre-library 2>&1" > ~/.gdrive-sync/nas_calibre.txt
sshpass -p '558068' ssh -o StrictHostKeyChecking=no admin@192.168.0.128 \
  "ls -1 /share/Public/audiobooks 2>&1" > ~/.gdrive-sync/nas_audio.txt
```

### 3. Compare (generates missing.txt + state.json, merges existing state)
```bash
python3 <skill-dir>/scripts/compare.py \
  --gdrive ~/.gdrive-sync/gdrive_all.ndjson \
  --nas-calibre ~/.gdrive-sync/nas_calibre.txt \
  --nas-audio ~/.gdrive-sync/nas_audio.txt \
  --out-dir ~/.gdrive-sync
# outputs: missing.txt, state.json, report.txt
cat ~/.gdrive-sync/report.txt
```

### 4. Iterative sync (idempotent — safe to re-run, Ctrl+C and resume)
```bash
# dry-run first
python3 <skill-dir>/scripts/sync.py --state ~/.gdrive-sync/state.json --dry-run
# one batch of 10 (each file commits state before next, crash-safe)
python3 <skill-dir>/scripts/sync.py --state ~/.gdrive-sync/state.json --limit 10
# loop until NO_PENDING, logging progress (keep stdout visible via tee):
while python3 <skill-dir>/scripts/sync.py \
  --state ~/.gdrive-sync/state.json --limit 10 2>&1 | tee -a ~/.gdrive-sync/sync.log | grep -q DONE_BATCH; do sleep 2; done
```

State file `~/.gdrive-sync/state.json` per file-id: `pending|downloaded|uploaded|verified|failed|skipped`.
Reruns skip `uploaded`/`verified`. Delete a key or set to `pending` to retry. Never re-downloads completed ids.

## Matching rules (compare.py)
Normalize: lowercase, strip `z-library.sk/1lib.sk/z-lib.sk` suffixes, strip `(1)`, strip `.epub/.pdf`, non-alnum → space.
Match if token-overlap ≥0.6 (stop-words removed) OR difflib ratio >0.75 against NAS calibre filenames + audio folder names.
