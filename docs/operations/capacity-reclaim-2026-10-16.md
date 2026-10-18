# Capacity reclaim — 2026-10-16 (k2/k5 root LVs, node junk, snapshot audit)

> Removes the capacity pressure flagged by the 2026-09-17 incident without new
> hardware. Session window ~20:39–21:05 UTC. All changes are additive (no data
> removed) except node-level caches already covered by the `node-disk-cleanup`
> DaemonSet's safety rules, and one dangling 2026-09-06 snapshot CR.
>
> **Secrets note:** no password is recorded here. Remote privileged steps used
> `sudo -S` with the homelab credential (`WindowsLab/cred.xml` / SecretStore
> `k3s-homelab-sudo`), same pattern as `Run-K3sAudit.ps1`.

---

## 1. k2/k5 root LV extension — the "disk full" was the LV, not the disk

Both nodes are LVM-on-root (`ubuntu-vg/ubuntu-lv`) with ~828 GiB unallocated in
the VG. The root LV (and with it `/var/lib/longhorn`) was pinned at 100 GiB.

| Node | Disk | Before | After |
|---|---|---|---|
| kubernetes2 | `nvme0n1` 931.5G | LV 100G; `/` 62 % (58G/98G); VG free 828.46G; Longhorn disk avail 40.3 GiB | LV 200G; `/` 31 % (58G/197G); VG free 728.46G; Longhorn disk avail **138.3 GiB** |
| kubernetes5 | `sda` 931.5G (WD Blue) | LV 100G; `/` 74 % (69G/98G); VG free 828.46G; Longhorn disk avail 29.7 GiB | LV 200G; `/` 37 % (68G/197G); VG free 728.46G; Longhorn disk avail **128.1 GiB** |

Method (per node): `kubectl cordon` → online `lvextend -r` → verify → `kubectl uncordon`.

```bash
kubectl cordon kubernetes2
ssh suryendub@192.168.0.20 "echo <sudo-pass> | sudo -S -p '' lvextend -r -L 200G /dev/ubuntu-vg/ubuntu-lv"
df -h / && sudo lvs && sudo vgs
kubectl uncordon kubernetes2
# identical on kubernetes5 (suryendub@192.168.0.24)
```

Notes:

- A drain was **not** required: `lvextend -r` is an online ext4 resize and purely
  additive, so no pod was evicted and no pod restarted (verified: restart counts
  unchanged on both nodes; `kubernetes2`/`kubernetes5` back to `Ready`).
- Remaining VG space is left unallocated, per the guidance in
  `kubernetes-manifests/longhorn-backup/grow-existing-root-lv.sh`.
- Longhorn picked up the new space automatically (disk status above re-read
  after the change); no replica/scheduling action was needed.

## 2. Node junk cleanup (reclaims on nuc/k3/k6 + apt everywhere)

| Node | Action | Result |
|---|---|---|
| nuc | removed 11 disabled snap revisions + cleared `/var/lib/snapd/cache` + `snap set system refresh.retain=2` | `/var/lib/snapd` 5.0G → 3.4G (remainder = active GNOME/firefox/mesa snaps + OS seed payload) |
| nuc | `journald` `SystemMaxUse=500M` + journald restart | `/var/log` 2.4G → 760M |
| k3 | removed 4 disabled snap revisions + cleared snap cache + `refresh.retain=2` | `/var/lib/snapd` 672M → 334M |
| k6 | `journald` `SystemMaxUse=500M` + restart + `journalctl --vacuum-size=500M` | `/var/log` 777M → 551M (journal 721M → 495.7M) |
| nuc, k1, k2, k3, k4, k5, k6 | `apt-get clean` + `/var/lib/apt/lists` trim | ~300–430 MB per node |

Notes:

- Only **disabled** snap revisions were removed, never the active revision (same
  rule as the `node-disk-cleanup` ConfigMap). `refresh.retain=2` stops rebuild of
  the same backlog.
- apt package lists were removed rather than refreshed; the next `apt update`
  re-fetches them. No `autoremove` was run.
- k7/k8 were SSH-unreachable and were not touched; server-236/252 (NotReady
  control planes) were out of scope. The `node-disk-cleanup` DaemonSet keeps its
  6-hourly >80 % job on all reachable nodes.

## 3. Longhorn snapshot audit (verify retain 12 → 4 is holding)

`snapshot-frequent` is unchanged and healthy: cron `0 */6 * * *`, retain 4,
group `default`. All volumes are in the default group (the churny volumes —
immich-library, iiq/mssql — have no explicit job selector), so nothing
re-accumulates outside the 4-snapshot window.

Actual counts per volume (CRs incl. backup markers; `kubectl -n longhorn-system
get snapshots.longhorn.io`):

- Max any volume: **6** (incl. the manual `pre-iiq-repair-20261016` and backup
  markers). Scheduled-only counts are ≤ 5, with the rare extra being a
  `markRemoved` transition object pending purge.
- Churny volumes checked: `immich-library-pvc` 3 + 1 backup; `mssql` 4 + 1
  manual + 1 backup; `mysql`/`activemq`/`ldap`/`mail`/`iiq` 4 + 1 backup each.
- Cluster total: 181 CRs across 41 volumes (2026-09-17: ~300 across 40).
- **No volume is over ~10 snapshots → no schedule needs thinning.**

One dangling September CR was removed: `gate-bac-2b99c8f4-…` for
`pvc-bc188937-a56f-4d1a-82c5-116a60845931` — the *old* `beszel-hub-data` volume
that was replaced during the 2026-09-06 recovery. The volume and its child
snapshot no longer exist locally; its 7 completed backups live on the QNAP
backupstore and are unaffected.

Audit commands:

```bash
kubectl -n longhorn-system get recurringjobs
kubectl -n longhorn-system get snapshots.longhorn.io --no-headers | awk '{print $2}' | sort | uniq -c | sort -rn | head
```

## 4. Follow-ups (not done in this session)

- **k3 root is the next-closest pressure point** — 107G root at 77 % used and
  `ubuntu-vg` fully allocated (376M free), so it cannot be extended without
  deleting data or adding storage.
- **k4 has 136.5G unallocated VG space** behind a 100G root LV — the same
  one-command treatment as k2/k5 applies if it ever needs it.
- Longhorn disk availability is now tightest on k3 (~30 GiB) and k4 (~36 GiB);
  k2/k5 are at 138/128 GiB after this session.
- k8-debian and k7 remain NotReady; k8 holds one stopped `immich-library`
  replica (volume still has 3 healthy replicas).
