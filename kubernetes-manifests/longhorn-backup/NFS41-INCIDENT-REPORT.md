# Longhorn → QNAP NFS Backup Fix (NFSv4.1 breakage)

Date: 2026-09-22. Scope of the original incident: Longhorn `backup-daily` had produced
no successful backup since 2026-09-20. This document is the incident write-up plus the
**durable, git-managed fix** (`07-nfs40-premount.yaml`).

## Symptom

Longhorn → QNAP NFS backups (`nfs://192.168.0.128:/longhorn`) were failing:
BackupTarget showed unavailable/stale, and new Backup CRs went to Error with
`EIO/error reading from server: EOF`. CronJob `backup-daily` (Longhorn-managed, owner =
RecurringJob `backup-daily`) hadn't produced a successful backup since 2026-09-20.

## Root cause (two layers)

### 1. The NAS does not support NFSv4.1 (observed as "broken server-side")

After deep probing (NFS matrix on the cluster):

- NFSv4.1 → `OPEN`/`cat` returned EIO (getattr sometimes worked; reads failed)
- NFSv4.0 → fully working
- NFSv3 (`nolock`) → fully working

NAS `nfs` restart (last resort) did **not** fix 4.1. Stale empty
`/var/lib/nfs/v4recovery/*` dirs + persistent `err -17 (EEXIST)` on recovery-record
writes pointed at server-side 4.1 state corruption. QTS still advertised +4.1 as
supported.

**Post-incident conclusion (2026-09-22):** this is not repairable state corruption —
owner investigation confirmed the **very old NAS does not actually support
NFSv4.1**. QTS advertises +4.1 and a 4.1 mount can even be established, but reads
die with EIO, and there is **no firmware, repair, or server-side NFS-version pin**
on this model. See the post-incident update at the end of this report.

### 2. Longhorn hardcodes NFSv4.1

Longhorn mounts the backupstore with fixed options: `nfsvers=4.1, actimeo=1, soft,
timeo=300, retrans=2`. There is **no Longhorn Setting to override the NFS version**
(verified on the live cluster, Longhorn v1.12.1). So every mount path that used
Longhorn's default options hit the broken 4.1 path.

## The fix (workaround that made backups work)

Pre-mount the backupstore as NFSv4.0 before Longhorn mounts it as 4.1. If the mount
already exists, Longhorn reuses it instead of mounting 4.1 itself.

On every relevant pod:

```sh
M=/var/lib/longhorn-backupstore-mounts/192_168_0_128/longhorn
mkdir -p "$M"
mount -t nfs4 -o vers=4.0,sec=sys,soft,timeo=300,retrans=2 \
  192.168.0.128:/longhorn "$M"
```

Applied in two places:

| Where | Why |
|---|---|
| All 9 longhorn-manager pods | BackupTarget status/listing, inspect-volume, target sync |
| All 18 instance-manager pods | Actual backup data path — engines/replicas run **inside** the instance-manager mount namespace and mount NFS themselves; host mounts don't propagate into IM pods |

Three IMs that still had a broken leftover 4.1 mount were fixed with
`umount` → remount as 4.0.

## Verification (DoD)

- BackupTarget `default`: `available: true`, fresh `lastSyncedAt`
- `volume.cfg` readable through the 4.0 mount (real data lives under
  `<export>/backupstore/volumes/…`)
- 23 new Backup CRs **Completed** starting 17:36Z (gate job `gate-manual-backup-2`
  ran sequential backups ~10s each); CronJob eligible: `suspend=false`, `30 3 * * *`
- Probe pods cleaned up

## What was deliberately NOT done

- Never changed the BackupTarget URL (would orphan existing backups)
- Never edited config via the Longhorn UI (git is source of truth)
- No git config change was needed — BackupTarget re-apply from git was identical
- Left two early Error backups in place (scope was Failed Jobs, which were deleted)

## Known limitation → durable fix in git

The 4.0 pre-mounts live in **pod mount namespaces**. If longhorn-manager or
instance-manager restarts, Longhorn remounts 4.1 and backups break again until the
pre-mount is reapplied. That was the known non-durable state after the incident.

**Now fixed:** `07-nfs40-premount.yaml` (in this directory) deploys the
`nfs40-premount` DaemonSet in `longhorn-system`:

- Runs on exactly the nodes that run longhorn-manager (scheduling parity: no
  tolerations/nodeSelector), `hostPID: true`, `privileged: true`.
- Every 30s each node scans `/proc` for Longhorn targets — `longhorn-manager`,
  `instance-manager` (reached via `/tini -- instance-manager …`), and engine
  replica/controller processes (`engine-binaries` cmdlines) — and dedupes by mount
  namespace.
- Inside each target's mount+network namespace (`nsenter -m -n` so NFS sockets live
  in the namespace that owns the mount) it:
  1. mounts `192.168.0.128:/longhorn` as **vers=4.0** if absent,
  2. health-probes by reading a sentinel file `<export>/.nfs40-probe` (a broken 4.1
     mount fails the read/write with EIO),
  3. recovers with `umount -l` + remount as 4.0 when the probe fails.
- Image: `longhornio/longhorn-manager:v1.12.1` — already cached on every target node
  and proven to ship `nsenter/mount/mountpoint/umount`. **Bump the tag with Longhorn
  upgrades.**

### Live re-verification (2026-09-22, post-incident)

- `kubernetes1` host has **no** backupstore mount (empty dir only) — the working
  fix state is *in-pod* mounts; LM pod mount shows `vers=4.0` with
  `clientaddr=<pod IP>`.
- IM/LM images confirmed to contain `/usr/bin/{nsenter,mountpoint,mount,umount}`.
- Backupstore root is writable (`no_root_squash`), so the sentinel probe works.
- Longhorn is running **v1.12.1** (the v1.8.1 references in older notes are stale).

### Apply & verify

```sh
kubectl apply -k kubernetes-manifests/longhorn-backup        # or just -f 07-…
kubectl -n longhorn-system rollout status ds/nfs40-premount
kubectl -n longhorn-system logs -l app=nfs40-premount | grep nfs40-premount | tail

# Functional check (the restart failure mode, simulated):
IM=$(kubectl -n longhorn-system get pod -o name --field-selector spec.nodeName=kubernetes2 | grep instance-manager | head -1)
kubectl -n longhorn-system exec "${IM#pod/}" -- umount /var/lib/longhorn-backupstore-mounts/192_168_0_128/longhorn
sleep 40
kubectl -n longhorn-system exec "${IM#pod/}" -- mountpoint /var/lib/longhorn-backupstore-mounts/192_168_0_128/longhorn
# -> "/… is a mountpoint" within one scan interval; logs show "mounted nfs4.0 pid=…"
```

### Remaining limitation (accepted)

- **There is no NAS-side fix.** The very old NAS does not support NFSv4.1 — no
  firmware, repair, or config path (see the post-incident update below) — so the
  DaemonSet is not a stopgap: it **is** the permanent fix for this cluster. The only
  true cure is replacing the NAS with one that properly supports NFSv4.1 (or exposes
  a server-side NFS-version pin to 4.0). If the DaemonSet itself is deleted while
  pod namespaces churn, backups break again — same as pre-fix behavior.
- Sentinel file `<export>/.nfs40-probe` is created at the backupstore root; it is
  harmless and can be deleted (it is recreated on the next scan).

## Post-incident update (2026-09-22): the NAS does not support NFSv4.1

The original working assumption — that the QNAP's NFSv4.1 breakage was repairable
server-side — was wrong. A painstaking investigation confirmed the very old NAS
**does not support NFSv4.1**:

- QTS still *advertises* `+4.1`, and a `vers=4.1` mount can even be established,
  but every subsequent read fails with `EIO` (consistent with the incident matrix
  above).
- No firmware update, service repair, or configuration option on this model makes
  4.1 usable — and there is no server-side way to pin the NFS version to 4.0.

Consequences:

- The "repair the NAS" permanent-fix option is off the table. Do not spend more
  time on `v4recovery` cleanup, nfsd restarts, or QTS re-firmware for 4.1 — they
  cannot help.
- `07-nfs40-premount.yaml` (`nfs40-premount` DaemonSet) is the **permanent**
  solution for this cluster's lifetime, not a workaround awaiting a NAS fix.
- The only true cure is **replacing the NAS** with one whose NFS server properly
  supports 4.1 (or that exposes a server-side NFS-version pin to 4.0).
- Operational rules stand: never edit `backup-target` via the Longhorn UI, and
  bump the DaemonSet image tag on Longhorn upgrades.

