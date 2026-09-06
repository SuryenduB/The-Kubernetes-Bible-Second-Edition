---
name: gdrive-ebook-organize
description: File loose GDrive ebooks (epub/pdf) into topic folders under My Ebook Library using keyword rules, with dry-run plan, idempotent moves, and resume via plan.json.
---

# gdrive-ebook-organize

## When to use
- User asks to organise/organize books in GDrive by topic, file newly downloaded ebooks, or tidy an ebook library.

## Prerequisites
- `gws` on PATH (`export PATH="$HOME/.npm-global/bin:$PATH"`), authed with drive scope: `gws auth login -s drive`
- Existing library layout (defaults = this homelab's `My Ebook Library`):
  - `CYBER = 1WyNmzFzriT0mcEuY_BkT0DoVsg79Jpj-` (Cybersecurity & Microsoft 365, incl. AI/coding books)
  - `GERMAN = 1TixzFaypotPYmPbnFzPkJ5GGVxs2lvtf` (German Learning)
  - `K8S = 12H6xX5Mfo8xlSO8wgVUiVRTtGrWCMQRb` (Kubernetes & Infrastructure, incl. DevOps)
  - `LIT = 1Ygh_Y7bALZeDm_5GAeb6CZvhYZ621bml` (Literature, History & Society, incl. fiction/history/biography)
  - `PERS = 1UNBQGqflB4RBfnR9GUqyTdUaezvZq_Fo` (Personal & Contracts)
- Override folder IDs via `--folder cyber|k8s|lit|pers|german <id>` or env `GDRIVE_LIB_{CYBER,K8S,LIT,PERS,GERMAN}`.

## Workflow

### 1. Find loose books (not in any topic folder)
```bash
python3 <skill-dir>/scripts/organize.py --scan --out-dir ~/.gdrive-organize
cat ~/.gdrive-organize/plan.txt
```

### 2. Review plan, adjust rules if needed
`plan.txt` lists each loose file → proposed topic + matched keyword. Ambiguous cases to confirm with user:
- Files inside other non-topic folders (e.g. `Phone book collection`) — ask before moving.
- Shared files you don't own (`owners[].me == false`) — Drive rejects `addParents`; left in place, reported as `unmovable`.
- Files with no parents (orphans) — same, reported as `unmovable`.

### 3. Dry-run, then move (idempotent — reruns skip already-filed)
```bash
python3 <skill-dir>/scripts/organize.py --dry-run --out-dir ~/.gdrive-organize
python3 <skill-dir>/scripts/organize.py --apply --out-dir ~/.gdrive-organize
```
Moves use `gws drive files update --params '{"fileId":..,"addParents":..,"removeParents":..}'`.
Each move commits to `plan.json` immediately — Ctrl+C and resume by re-running `--apply`.

## Topic rules (organize.py RULES, keyword → folder, first match wins)
- PERS: contract, driving license, employment, hello-fresh, photo, deployment, getting started, antrag
- GERMAN: german, andr(e|é) klein, ferien, karneval, ahoi, palermo, walzer, zürich/zurich, dresden, stuttgart, sylt
- K8S: kubernetes, cka, terraform, ansible, vmware, vsphere, veeam, powershell, active directory, devops, bitbucket, github, linux command, azure, cloud resume, zabbix, intune (cookbook stays in CYBER if already filed — only loose files are touched)
- CYBER: copilot, defender, entra, sc-100, sc-200, sentinel, kql, xdr, siem, zero trust, okta, identity, codex cli, claude code, vibe engineering, bitwarden/cnapp/dspm, infinity machine → LIT (biography exception), purview
- LIT (default for fiction/history/biography, incl. Bengali titles): dune, november 1918, history, biography, novel, ruskin bond, hitchhiker, judt, kiyosaki, and any loose file matching none of the above → ask, default LIT only if fiction/history-like, else leave unmoved and report.
