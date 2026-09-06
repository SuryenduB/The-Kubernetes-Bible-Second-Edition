---
name: qnap-nfs-longhorn-backup
description: Set up, validate, and troubleshoot Longhorn backups to a QNAP QTS NFS share — export verification, root-write gate test, NFSv4.1 negotiation quirks, nfsd half-dead recovery, and webhook/admission EOF triage.
---

# qnap-nfs-longhorn-backup

## When to use
- Setting up or re-validating Longhorn NFS backups against the QNAP QTS NAS (192.168.0.128, share `/longhorn`).
- Longhorn backups fail with `input/output error`, `EOF`/`error reading from server`, or Backups stuck at `State: ""` with `Progress: 0`.
- Suspicion that the QTS NFS service is flapping or half-dead after a Web UI settings change.

## Environment
- NAS: `admin@192.168.0.128` (pass `558068` via `sshpass`), QTS, NFS export `/longhorn` → `/share/CACHEDEV1_DATA/longhorn`.
- Cluster: k3s, nodes `kubernetes1..8` + `nuc` (control-plane). Longhorn v1.8.1 in `longhorn-system`.
- Backup manifests: `<repo>/kubernetes-manifests/longhorn-backup/` (BackupTarget, 3 RecurringJobs).

## Validation sequence (run in this order)

### 1. Verify the export is actually live (etab is the only truth)
QTS Web UI "Apply" is NOT confirmation. The row checkbox next to a host rule must be ticked in the NFS host-access dialog or the rule is silently ignored.
```bash
sshpass -p '558068' ssh -o StrictHostKeyChecking=no admin@192.168.0.128 \
  "cat /var/lib/nfs/etab | grep longhorn"
# Must contain: rw, no_root_squash, insecure
```

### 2. Root-write gate test (proves NO_ROOT_SQUASH end-to-end)
Privileged busybox pod, nodeName pinned; mounts `192.168.0.128:/longhorn`, writes a file, `chown`s it to `1000:1000`. Success = `CHOWN_OK=1` AND NAS-side `ls -ln` shows uid 1000 (a chown by root succeeding is only possible with real `no_root_squash`). Delete the test file after.

### 3. NFS version matrix — CRITICAL: Longhorn negotiates NFSv4.1, not v3
Always test from a privileged pod on the SAME node that fails:
```bash
for v in 4.2 4.1 4 3; do
  mount -t nfs -o vers=$v 192.168.0.128:/longhorn /mnt/t$v 2>/tmp/err \
    && echo "vers=$v OK" || echo "vers=$v FAIL: $(cat /tmp/err)"
done
```
- `vers=4.2` → `Protocol not supported` on QTS is normal (v4.1 is what Longhorn gets).
- `Connection refused` for a version that worked minutes ago = nfsd flapping (see triage).

### 4. Trigger + time a real backup via the RecurringJob engine (NOT hand-made Backup CRs)
```bash
kubectl -n longhorn-system create job --from=cronjob/backup-daily gate-manual-backup-N
kubectl -n longhorn-system get backups.longhorn.io -o \
  custom-columns='NAME:.metadata.name,STATE:.status.state,SIZE:.status.size,PROGRESS:.status.progress'
```

## Failure triage (the 2026-09-06 incident playbook)

### Symptom A: backups Error with `input/output error` on `/var/lib/longhorn-backupstore-mounts/...`
and/or sync-agent `panic: nil pointer` in `backupstore.CreateDeltaBlockBackup`, rpc `Unavailable ... EOF`.
→ QTS nfsd restarted while Longhorn held stale mounts/state.

**Check NAS dmesg** (the smoking gun):
```bash
sshpass -p '558068' ssh admin@192.168.0.128 \
  "dmesg | grep -E 'grace period|export cache' | tail -8"
# repeated "last server has exited, flushing export cache" + "starting 90-second grace period" = flapping
```
**Fix — full NFS service restart on the NAS, then wait out the 90s grace:**
```bash
sshpass -p '558068' ssh admin@192.168.0.128 "/etc/init.d/nfs restart"
# /etc/init.d/nfs.sh does NOT exist; the "forcelookupsubtreecheck: Permission denied" warning is benign.
```
A root mount health-check passing does NOT mean deep paths are readable — Longhorn's `EnsureMountPoint` only reads the mount root. Always re-test the actual `volume.cfg` path after any nfsd restart.

### Symptom B: creating ANY `Backup` CR via kubectl fails with webhook `EOF`,
while RecurringJob/Snapshot/Engine creates succeed, and NO longhorn-manager logs the request.
→ `longhorn-admission-webhook` deployment missing but its webhook configs (failurePolicy=Fail) remain.
```bash
kubectl -n longhorn-system get deploy | grep webhook   # empty = missing
kubectl delete validatingwebhookconfiguration longhorn-webhook-validator
kubectl delete mutatingwebhookconfiguration longhorn-webhook-mutator
# managers recreate them (can take minutes; verify AGE resets)
```



### Symptom C: manual Backup CR stuck at `State: ""` / snapshot deleted underneath it
`auto-cleanup-recurring-job-backup-snapshot=true` (default) removes recurring-job snapshots right after processing — hand-made Backup CRs referencing older snapshots get orphaned. Don't fight it: use the RecurringJob path above. Also, `kubectl apply` of a full-mode Backup can EOF at the admission webhook while `kubectl create` with 5–8 retries eventually passes — retry before assuming an outage.

### Diagnostics that actually answer questions
```bash
# Engine-level backup status + snapshot chain (removed/usercreated flags):
kubectl -n longhorn-system get engines.longhorn.io <vol>-e-0 -o json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d['status'].get('backupStatus'), d['status']['snapshots'])"

# Replica/sync-agent panics (engine instances log through the node's manager):
kubectl -n longhorn-system logs longhorn-manager-<node-pod> --since=10m | grep -B2 -A15 panic

# Backup CR owner (empty State = wrong owner / never picked up): check status.ownerId
```

## Gotchas
- **QTS Web UI "Apply" on NFS settings restarts nfsd** (observed 4x + grace periods). Do it in a maintenance window; expect one-time EIO for live backupstore mounts until service restart + client remount.
- **NAS clock skew** was ~14 min slow — check `date` on NAS vs `date -u` locally before correlating logs; fix NTP on the QTS.
- QTS may expose `/share/NFSv=4/longhorn` (v4 pseudo-root) AND `/share/CACHEDEV1_DATA/longhorn` — both valid, same fsid.
- `rpcinfo -t 127.0.0.1 100003 4` on QTS can read DOWN even when v4.1 client mounts work — don't trust it; test real mounts from a client node.
- Reading a file from the NAS itself (`cat volume.cfg`) can succeed while NFS clients get EIO — server-local access is not a health check.
- Hardening TODO: `Public` share exports `*(rw,no_root_squash)` and `longhorn` is `*`-wide; restrict to node IPs 192.168.0.19–.26 when convenient.

## Success criteria
- `backuptargets.longhorn.io default` → `available: true`, `lastSyncedAt` fresh.
- ≥1 `backups.longhorn.io` with `STATE=Completed`, `PROGRESS=100`.
- Volume dirs appearing under `/share/CACHEDEV1_DATA/longhorn/backupstore/volumes/` on the NAS.
