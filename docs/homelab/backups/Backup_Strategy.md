# Backup Strategy — K3s Homelab

**Status: OPERATIONAL** (volume layer since 2026-09-06; control-plane layer pre-existing).
**Last validated against live state: 2026-09-06 ~13:00 UTC** — see §7 Validation record.
Credentials in runbook commands are intentionally redacted to vault/env refs.

This document consolidates and supersedes the backup information previously spread across
`docs/homelab/how-to-audit-homelab.md` (§ backup rotation),
`kubernetes-manifests/longhorn-backup/README.md`,
`docs/homelab/backups/longhorn-backup-status-2026-09-06.md`, and the triage notes in
`skills/qnap-nfs-longhorn-backup/SKILL.md` (kept as the deep-dive incident playbook).

The strategy has two independent halves. Either can restore without the other:

| Half | What it protects | Where copies live | Restore tool |
|---|---|---|---|
| Control-plane (§2) | K8s state (`state.db`), certs/config | QNAP `Public/backups/k3s/` (timestamped dirs) | `WindowsLab/Restore-K3sCluster.ps1` |
| Volume data (§3) | All Longhorn PVC contents (DBs, app data) | QNAP `longhorn` share (`backupstore/`) | Longhorn UI / `kubectl` (Backup CRs) |

---

## 1. Architecture

```text
nuc (control-plane)                          QNAP NAS (192.168.0.128)
┌─────────────────────────┐                  ┌──────────────────────────────────┐
│ cron 02:00 UTC          │   state.db +     │ Public/backups/k3s/YYYYMMDD-HHMMSS/
│ k3s-backup-to-nas.sh    │──tar.gz─────────▶│   k3s-state.db, k3s-config.tar.gz│
│ (lives on NUC, §2)      │                  │   retention: last 10 (§2)        │
└─────────────────────────┘                  └──────────────────────────────────┘
                                             ┌──────────────────────────────────┐
workers (Longhorn replicas)                  │ longhorn share (NFS)             │
┌─────────────────────────┐  backup-daily    │  backupstore/volumes/<vol>/      │
│ 13 volumes, 3-way repl. │──03:30 UTC──────▶│   12 volume dirs, ~1.8 GB        │
│ + 6h snapshots (local)  │  NFSv4.1         │   retention: 14 (per volume)     │
└─────────────────────────┘                  └──────────────────────────────────┘
```

Known design limits (accepted, not oversights):
- Backups are **crash-consistent**, not app-quiesced. DB WALs inside the volumes make restores recoverable; there are no logical dumps (`pg_dump`/`mysqldump`) and no point-in-time recovery.
- There is **no offsite copy**. NAS loss (fire/theft) takes both halves. Offsite (`rclone`/`restic` to B2/S3) is a future enhancement.
- NAS-hosted data (`*-nas-pvc` direct mounts, media libraries) is **not** Longhorn-backed-up — the NAS copy IS the data. Same single-copy exposure as above.

---

## 2. Control-plane backup (the brain)

- **What:** `/var/lib/rancher/k3s/server/db/state.db` (~205 MB, WAL-checkpointed) +
  `/etc/rancher/k3s/` as `k3s-config.tar.gz` (CA keys, certs, tokens, registries config).
- **How:** `k3s-backup-to-nas.sh` via system crontab on `nuc`, nightly 02:00 UTC.
  Stops K3s, runs `PRAGMA integrity_check` (aborts without overwriting on corruption), copies to NAS.
- **Retention:** rolling last 10 snapshots (prune policy per `how-to-audit-homelab.md`).
- **Restore:** `pwsh -File WindowsLab/Restore-K3sCluster.ps1 [-BackupTimestamp "…"] [-ListOnly] [-Force]`.
  5 phases: discover → validate filenames → stop K3s → restore config + db → start + `kubectl get nodes` check.
- **⚠️ Full-rebuild caveat:** on a re-imaged master, `/var/lib/rancher/k3s/server/tls` needs a separate
  manual restore (noted in the script footer). Verify `k3s-config.tar.gz` actually contains it —
  otherwise the ~10 min RTO claim does not hold. Untested restores are hopes; schedule a drill.
- **⚠️ Script location gap:** `k3s-backup-to-nas.sh` lives only on the NUC, not in this repo. Commit it.

## 3. Longhorn volume backup (the data)

### 3.1 Target

| Item | Live value (verified) |
|---|---|
| BackupTarget CR | `default` in `longhorn-system` |
| URL | `nfs://192.168.0.128:/longhorn` (NOT `/backups/longhorn` — that path in the old README was wrong) |
| NAS side | `/share/CACHEDEV1_DATA/longhorn`, export opts `rw, no_root_squash, insecure` (verified in `/var/lib/nfs/etab`) |
| Status | `available: true`, `lastSyncedAt` fresh (checked 12:52 UTC), poll 5m |
| Store size | ~1.8 GB, 12 volume dirs under `backupstore/volumes/` |

QNAP specifics that matter (learned the hard way, 2026-09-06):
- Longhorn negotiates **NFSv4.1**, not v3. Test that version explicitly.
- The QTS "Users and groups" permission screen is **irrelevant** — NFS is governed by the separate
  **NFS host access** screen. The row checkbox must be ticked or the rule is silently ignored; check `etab`, not the UI.
- QTS Web UI **Apply restarts nfsd** (observed repeatedly + 90 s grace). Do it in a maintenance window;
  expect one-time `input/output error` on live mounts until restart + client remount.
- NAS clock runs ~15 min slow — fix NTP before correlating logs.
- A root mount succeeding does NOT prove deep paths are readable — always re-test an actual `volume.cfg` path.

### 3.2 Recurring jobs (manifests: `kubernetes-manifests/longhorn-backup/`)

| Job | Task | Cron (UTC) | Retain | Concurrency | Group |
|---|---|---|---|---|---|
| `snapshot-frequent` | snapshot | `0 */6 * * *` | 12 | 1 | `default` |
| `backup-daily` | backup | `30 3 * * *` | 14 | 1 | `default` |
| `fs-trim-weekly` | filesystem-trim | `0 5 * * 0` (Sun 05:00) | — | 1 | `fs-trim` (opt-in per volume label) |

Mechanism: jobs in the **`default` group auto-schedule to every volume with no explicit job** —
all current and all future volumes, zero per-PVC wiring. (Explicit per-volume labels remove a volume
from default scheduling; use for exceptions only, e.g. lighter snapshot retain on churn-heavy DBs.)
`allow-recurring-job-while-volume-detached: true` is set, so detached volumes are still backed up.
Snapshots live on **worker NVMe, not the NAS** — watch disk headroom (retain 12 × 6 h on busy DBs).

### 3.3 Coverage (validated 2026-09-06 ~13:00 UTC)

First fleet backup triggered manually (`create job --from=cronjob/backup-daily`); concurrency=1 drains
sequentially (~15 min full fleet). State at validation: **13 Completed, 1 Pending, 1 just-started**
(see §7). Covered: mssql, ldap, mail, openlingo-db, audiobookshelf-config, calibre-web-config, mysql,
activemq, linguacafe-storage, iiq-nas, beszel-hub-data, uptime-kuma-data.

Explicitly NOT covered:
- `pvc-bace74a9` (linguacafe-mariadb, 5 Gi) — **faulted/detached**; needs recovery before it can join.
- `*-nas-pvc` direct NAS mounts (ollama-nas, webui-nas, media) — not Longhorn volumes by design.

### 3.4 Restore a PVC (drill procedure — UNTESTED, do it)

```bash
# 1. Pick a backup (small, low-risk first: beszel-hub-data)
kubectl -n longhorn-system get backups.longhorn.io
# 2. Longhorn UI → Backup → Restore to a NEW volume/PVC in a scratch namespace
# 3. Mount it, verify data, delete scratch resources
```

## 4. Monitoring the backups

- `Test-K3sClusterHealth.ps1` covers nodes/pods/PVCs/Longhorn robustness/app matrix (it does NOT yet
  check backup freshness — planned: fail if no `Completed` backup < 26 h old).
- Recommended Uptime-Kuma monitors: backup-job push (curl at end of nightly scripts), TCP `192.168.0.236:5000`
  (registry), HTTP on key app endpoints. Pod Running ≠ serving.

## 5. What to do when it breaks

- Symptom → fix index lives in `skills/qnap-nfs-longhorn-backup/SKILL.md` (nfsd half-dead recovery,
  missing admission webhook, orphaned Backup CRs, engine-level diagnostics). Start there, not here.
- Never edit the backup target in the Longhorn UI — Git is the source of truth; changing the target
  orphans all previous backups by design.

## 6. Open items (carried, still true at validation)

- [ ] Restore drill (§3.4) — the round-trip is unproven until this is done.
- [ ] Stuck `backup-b15856e29ef54a3f` (`Deleting` since 12:07 UTC) — clear or delete manually.
- [ ] Recover `linguacafe-mariadb` (faulted/detached) so it joins `backup-daily`.
- [ ] Fix NAS clock (~15 min slow) for log correlation and cert validation.
- [ ] Harden NFS exports: `longhorn` and `Public` are `*(rw,no_root_squash)` — restrict to node IPs `.19–.26`.
- [ ] Verify first scheduled `backup-daily` run (03:30 UTC) lands 12/12 next morning.
- [ ] Commit `k3s-backup-to-nas.sh` to this repo; reconcile retention docs (10 vs 30-day prune).
- [ ] Future: offsite copy (`rclone`/`restic`), logical DB dumps.

## 7. Validation record (2026-09-06 ~13:00 UTC)

| Claim (source) | Evidence | Verdict |
|---|---|---|
| Target `nfs://192.168.0.128:/longhorn`, available | BT CR: URL match, `available: true`, sync 12:52 UTC | ✅ PASS |
| Export `rw, no_root_squash` | `/var/lib/nfs/etab` shows both longhorn paths with `no_root_squash` | ✅ PASS |
| 3 RecurringJobs as specced | All present in `longhorn-system` | ✅ PASS |
| Detached volumes included | Setting `allow-recurring-job-while-volume-detached=true` | ✅ PASS |
| 1.8 GB, 12/12 volume dirs | `du` + `ls` on NAS | ✅ PASS |
| 13 Completed / draining queue | Backup CR states at 12:56–12:57 UTC | ✅ PASS |
| mariadb excluded (faulted) | Volume still `faulted/detached`; absent from store | ✅ PASS (correct exclusion) |
| Old README path `/backups/longhorn` | Live system uses `/longhorn`; README wrong | ❌ SUPERSEDED by this doc |
| Status-doc cron `0 5 * * * 0` | Manifest has `0 5 * * 0`; doc table has a 6-field typo | ❌ DOC TYPO (fixed here) |
| Stuck `Deleting` backup clears itself | Still `Deleting` at validation | ⚠️ OPEN (manual clear needed) |
| NAS clock ~14 min slow | 12:41 UTC on NAS vs 12:56 UTC local (~15 min) | ⚠️ OPEN |
| Exports restricted to node IPs | etab still `*`-wide | ⚠️ OPEN |
| Restore drill done | No evidence (no scratch ns checked) | ⚠️ OPEN |
| Control-plane 02:00 cadence | Latest snapshot dir `20260906-121355` present; folder TZ vs cron TZ ambiguous | ⚠️ UNVERIFIED (confirm naming TZ) |
