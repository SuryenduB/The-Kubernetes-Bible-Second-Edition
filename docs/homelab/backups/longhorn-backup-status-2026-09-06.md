# Longhorn → QNAP NFS Backup — Status 2026-09-06

**Status: OPERATIONAL** — first-ever successful backups landed on the NAS today after the NFS pipeline was repaired.

## Target configuration

| Item | Value |
|---|---|
| BackupTarget | `nfs://192.168.0.128:/longhorn` (name `default`) |
| NAS export | `/share/CACHEDEV1_DATA/longhorn` (+ NFSv4 pseudo-root), `rw, no_root_squash, insecure` |
| Target status | `available: true`, poll interval 5m |
| NAS capacity | `/share/CACHEDEV1_DATA`: 423 GB total, 83.6 GB used (20%), 339 GB free |
| Backupstore size | 1.8 GB, 12/12 volume dirs present |

## Recurring jobs (applied from `kubernetes-manifests/longhorn-backup/`)

| Job | Task | Cron | Retain | Concurrency | Group |
|---|---|---|---|---|---|
| `backup-daily` | backup | `30 3 * * *` | 14 | 1 | default |
| `snapshot-frequent` | snapshot | `0 */6 * * *` | 12 | 1 | default |
| `fs-trim-weekly` | filesystem-trim | `0 5 * * * 0` | — | 1 | fs-trim |

`allow-recurring-job-while-volume-detached: true` is set, so detached volumes are still backed up.

## Backup coverage (as of 2026-09-06 12:50 UTC)

Triggered manually via `kubectl -n longhorn-system create job --from=cronjob/backup-daily gate-manual-backup-5`
(concurrency=1 → volumes drain sequentially; full fleet ≈ 15 min).

| Volume (PVC) | Workload (ns) | Size | Last backup | State |
|---|---|---|---|---|
| pvc-14185485 (mssql) | iiqstack | 10 Gi | backup-40aa349cd5e347c7 · 12:45:48 | Completed 100% |
| pvc-309f5f37 (ldap) | iiqstack | 2 Gi | backup-d7004863e435441a | Completed 100% |
| pvc-3fc59c8f (mail) | iiqstack | 1 Gi | queued | Pending |
| pvc-5d174f8e (openlingo-db) | openlingo | 5 Gi | queued | Pending |
| pvc-6a2968b1 (audiobookshelf-config) | media | 2 Gi | backup-fd4ecdee50e243aa | Completed 100% |
| pvc-710a38ae (calibre-web-config) | media | 1 Gi | queued | Pending |
| pvc-7af65d29 (mysql) | iiqstack | 10 Gi | backup-019ad62eb05d42a4 · 12:47:15 | Completed 100% (866 MiB) |
| pvc-8dfcb65e (activemq) | iiqstack | 5 Gi | queued | Pending |
| pvc-9b89f2df (linguacafe-storage) | linguacafe | 20 Gi | backup-663db487c6ca4b0d · 12:46:50 | Completed 100% (1.14 GiB) |
| pvc-af6bb19d (iiq-nas) | iiqstack | 10 Gi | queued | Pending |
| pvc-bc188937 (beszel-hub-data) | monitoring | 1 Gi | queued | Pending |
| pvc-c42102f2 (uptime-kuma-data) | monitoring | 2 Gi | backup-917c03282db74bf2 · 12:45:02 | Completed 100% (118 MiB) |

**NOT backed up:** `pvc-bace74a9` (linguacafe-mariadb, 5 Gi) — volume is **faulted/detached**; needs separate
recovery before it can participate in backups. `*-nas-pvc` volumes (ollama-nas, webui-nas, iiq-nas PVs, media
NFS PVs) are direct NAS mounts, not Longhorn volumes — the NAS copy IS their data.

## What was fixed today (full playbook: `skills/qnap-nfs-longhorn-backup/SKILL.md`)

1. QTS NFS export for `/longhorn` applied via Web UI (NFS host access, rw, NO_ROOT_SQUASH).
2. **QTS nfsd was half-dead** after the Web UI Apply (4 restarts + grace periods; clients got
   `input/output error` on backupstore paths, sync-agent panics). Fixed with `/etc/init.d/nfs restart`
   on the NAS → backups immediately succeeded. Longhorn uses **NFSv4.1** (not v3).
3. Removed stale `longhorn-webhook-{mutator,validator}` configs whose admission-webhook deployment
   was missing (caused `EOF` on all manual Backup CR creates). Managers regenerated them.
4. Root-write gate test passed (privileged pod wrote + chowned as root through the NFS mount).

## Open items

- [ ] Let `gate-manual-backup-5` finish the 5 queued volumes, then confirm 12/12 `Completed`.
- [ ] Stuck `backup-b15856e29ef54a3f` (Deleting) — from the failed pre-fix run; will clear or delete manually.
- [ ] Recover `linguacafe-mariadb` faulted volume (restorable from replicas or rebuild), then it joins backup-daily.
- [ ] Fix NAS clock (≈14 min slow) — breaks log correlation and cert validation.
- [ ] Harden NFS exports: restrict `longhorn` and `Public` (currently `*(rw,no_root_squash)`) to node IPs 192.168.0.19–.26.
- [ ] Restore drill: restore `beszel-hub-data` from backup-917c03282db74bf2 into a scratch PVC to prove the round-trip.
- [ ] First scheduled `backup-daily` run tonight 03:30 — verify 12/12 next morning.
