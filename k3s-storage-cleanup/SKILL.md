---
name: k3s-storage-cleanup
description: Reclaim disk across the K3s homelab without deleting anything still needed — eligibility-checked Longhorn orphan and image cleanup, journald bounds, Docker cache — plus registry-recoverability proof, regression checks and non-additive measurement rules. Use when a node hits DiskPressure or sits above 80%, when orphan records or images have accumulated, or when writing/auditing a disk-reclaim report.
---

# k3s-storage-cleanup

Reclaim disk on a live cluster without deleting something that is still needed.
The whole skill exists to defend one sentence:

**Unreferenced is not eligible.**

"Nothing currently points at it" is the weakest possible reason to delete. A
rollback target, a scaled-to-zero workload's image, and an orphaned replica
directory all look unreferenced right up until someone needs them back. So every
deletion here must be **eligible by a stated rule, recoverable where the object
is recoverable, and revalidated immediately before it happens**.

Three more words carry the rest of the procedure:

- **Sweep** — one uniform measurement of all 10 nodes, same command, same unit.
  Every before/after comparison is sweep-vs-sweep.
- **Settle** — containerd's collector reclaims disk *after* `rmi` returns.
  Re-measure after it settles before concluding anything.
- **Regression** — a health signal that got worse during the run. A run that
  reclaims 700 GiB and degrades one volume is a failure, not a 99% success.

## When to use

- A node reports `DiskPressure`, sits above 80% used, or evicted pods.
- `Orphan` CRs have accumulated (count them — 312 was one real backlog).
- Images have piled up after repeated rollouts.
- Writing or auditing a reclaim report.

## Not for

- Longhorn replica/volume repair, `NotReady` nodes, NFS backupstore incidents →
  `qnap-nfs-longhorn-backup`, `iiq-restore`.
- Cordon/uncordon and rebalancing → `k3s-rebalance`.
- Unattended scheduled deletion. Planned cleanup is an explicit act; see
  [`reference/execution-contract.md`](reference/execution-contract.md).

## Guardrails

| Invariant | Why |
| :-- | :-- |
| Node identity, SSH user, and `neverCordon` flags come from `WindowsLab/homelab-nodes.json` | Single source of truth; usernames are case-sensitive (`suryendub` everywhere, **`SuryenduB` only on server-236**) |
| Privileged node commands go through `k3s-homelab-optimisation/scripts/remote-admin.sh` | sudo fetched in-memory from the SecretStore; output redacted |
| `/var/lib/longhorn` is read-only to you; replica data is removed **only** by deleting an eligible `Orphan` CR | Hand-deleting a replica is unrecoverable data loss |
| `/var/lib/docker` on **server-236** is the backing store of `192.168.0.236:5000` | Pruning it destroys the registry every custom image comes from |
| `nuc`, `server-236`, `server-252` are never cordoned or drained | The three embedded-etcd members, one lineage |
| Docker **volumes** are retained by default | "Anonymous" describes ownership, not disposability |
| Named volumes, etcd snapshots, `db-backup-*`, all Longhorn backups and VolumeSnapshots are retained | Recovery data, not cache |
| Workloads are not restarted and image references are not edited | Reclaim is node-local; pod churn is out of scope |
| One cleanup at a time per node | A manual run and the 6-hourly DaemonSet must not interleave |

**Blanket commands are out of bounds.** `crictl rmi --prune`,
`docker volume prune`, `docker image prune -a`, and
`kubectl delete orphan --all` each apply a policy ("nothing references it") that
this skill rejects. Delete named objects by ID, one at a time, with a logged
reason.

## Procedure

### 0. Preflight

Run from the repo root. Take the **before** snapshot: measurements *and* health.

```bash
python3 -c "import json;d=json.load(open('WindowsLab/homelab-nodes.json'));\
print([(n['name'],n['ip'],n['sshUser']) for n in d['nodes']])"
kubectl get nodes                                  # 10 Ready; server-252 SchedulingDisabled
bash k3s-storage-cleanup/scripts/sweep.sh > before.txt
kubectl get pods -A -o wide > before-pods.txt
kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns='N:.metadata.name,S:.status.state,R:.status.robustness' > before-volumes.txt
```

**Done when** `before.txt` has a row per expected node, `before-volumes.txt`
lists every volume, and no node is missing. An unmeasured or unrecorded node
invalidates every later comparison.

### 1. Triage — where the space actually went

| Signal | Culprit | Step |
| :-- | :-- | :-- |
| `CONTAINERD_MIB` large, `IMGS` high | images | 3 |
| `LONGHORN_MIB` large vs peers | orphaned replica data | 2 |
| `JOURNAL` large, `JCAP=none` | journald unbounded | 4 |
| `DOCKER_MIB` large | build cache / images | 5 |
| all small, `df` still high | not covered — investigate before deleting | — |

**Done when** each high-usage node has a named cause from the table.

### 2. Reclaim Longhorn orphans

An `Orphan` means **Longhorn no longer tracks that directory**. It does not mean
the data is unwanted, and deleting the resource can delete the directory.
Treat it as "possibly stale", never as "garbage".

**2a. Read the real field names.** They vary by Longhorn version. Inspect one
object before filtering three hundred:

```bash
kubectl -n longhorn-system get orphans.longhorn.io -o json | \
  python3 -c "import json,sys;print(json.dumps(json.load(sys.stdin)['items'][0],indent=1))"
```

**2b. Eligibility.** An orphan is eligible only when **all** of these hold:

| Condition | Check |
| :-- | :-- |
| Replica-data orphan | orphan type/`parameters` says replica data, not engine or volume metadata |
| Longhorn says it is cleanable | Require condition `DataCleanable` to be `True`, using the installed version's schema |
| No error | Require condition `Error` to be `False`, using the installed version's schema |
| No current reference | the **(node, disk, directory)** tuple is absent from every `replicas.longhorn.io` data path — compare the tuple, not the directory name alone |
| Old enough | `creationTimestamp` older than the retention floor (default 24 h) |
| Not recovery-protected | no `degraded`/`unknown`/`faulted` volume or replica on that node, no rebuild in flight, no backup/restore job running |
| Still true at delete time | revalidated immediately before deletion (2d) |

**2c. Print the decision table before deleting.** One row per orphan: name,
node, disk, directory, size, verdict, and — for retained ones — the reason.

**2d. Revalidate, then delete by name with a bounded wait.**

```bash
kubectl -n longhorn-system delete orphans.longhorn.io <name> --wait=true --timeout=120s
```

**2e. Verify no regression.** Replica count unchanged, and every volume's
`state`/`robustness` identical to `before-volumes.txt`.

**Done when** no *eligible* orphan remains and every retained orphan carries a
recorded reason. "No orphan remains" is not the goal — some may be legitimately
retained.

### 3. Reclaim container images

Order is the safety property: **recoverability first, deletion second.**

**3a. Prove recoverability before computing candidates.** For every image
referenced by a workload template:

```bash
python3 k3s-storage-cleanup/scripts/registry-recoverability.py \
  --registry 192.168.0.236:5000 \
  sailpoint-iiq:8.5 openlingo:v10-dynamic-models ai-language-learning:latest
```

This resolves the required platform manifest and HEADs the config and every
layer by digest. Anything that cannot be fully served is **protected** — fail
closed, never a candidate.

**3b. Build three sets and print them.**

| Set | Definition |
| :-- | :-- |
| **in-use** | image IDs referenced by any container on the node: `crictl ps -a -o json` |
| **protected** | every image named in *any* Pod template — Deployments, StatefulSets, DaemonSets, Jobs, CronJobs (including `replicas: 0`, suspended CronJobs and previous ReplicaSet revisions inside the rollback window); every image whose recoverability is unproven; every digest pinned in Git |
| **candidates** | all images − in-use − protected |

Protected is deliberately broader than in-use: a scaled-to-zero workload has no
container and still needs its image.

**3c. Delete by ID, one at a time, revalidating each time.**

```bash
crictl --timeout 5m rmi <image-id>
```

Re-read the in-use set immediately before each deletion; if the ID appeared
since the candidate list was built, skip it and record why. Log the reference,
digest, size and eligibility reason for every removal.

**3d. Settle, then re-verify.** A `du` that has not moved yet is not a failure —
containerd collects asynchronously. Confirm afterwards that no protected image
is missing and that a second pass deletes nothing.

**Done when** every candidate is accounted for (deleted, or retained with a
reason) and the protected set is intact. The image count is *not* a success
metric — it is a consequence.

### 4. Bound the journals

The cap is the durable fix; the vacuum is a one-off.

```bash
# Inspect the combined configuration, including drop-ins and precedence.
systemd-analyze cat-config systemd/journald.conf
# Then inspect journald startup messages and measured usage.
journalctl -u systemd-journald -b --no-pager
journalctl --disk-usage

# Only when no cap exists anywhere:
printf '[Journal]\nSystemMaxUse=500M\n' \
  > /etc/systemd/journald.conf.d/10-homelab-cap.conf
systemctl restart systemd-journald
journalctl --vacuum-size=200M
```

Two things `--vacuum-size` does **not** do: it bounds *archived* files, while
`--disk-usage` also counts the active journal, and it does not create a
diagnostic retention window — that is `MaxRetentionSec`. MaxRetentionSec sets
a maximum age. It does not guarantee that history remains available for that
duration. Size limits can remove older entries sooner. Report the measured
`--disk-usage` and never promise a history window from a size limit.

**Done when** the combined configuration, journald startup messages, and
`--disk-usage` are recorded on every node before and after the change.

### 5. Reclaim Docker cache

Docker runs on `nuc` and `kubernetes1` only; on `server-236` it backs the
registry and is out of scope.

```bash
docker system df -v
docker builder prune -a --force          # pure cache: regenerable, unconditional
```

`docker builder prune` deletes regenerable build cache and is unconditional.

Images follow the same rule as step 3 — compute in-use / protected / candidates,
then delete by ID:

```bash
docker images --format '{{.ID}}\t{{.Repository}}:{{.Tag}}\t{{.Size}}'
docker rmi <image-id>                    # one at a time, eligibility-checked
```

`docker image prune -a` is deliberately **not** used: like `crictl rmi --prune`
it deletes by "no container references it", the blanket policy rejected above.
Record each removed image's registry digest so it remains recoverable.

**Volumes are retained.** No `docker volume prune` in any form. A volume is
removed only through an explicit allowlist entry naming that volume, with owner
approval, one at a time:

```bash
# only for a volume listed in the disposable allowlist, never by pattern
docker volume rm <name>
```

**Done when** build cache is empty, `docker volume ls` is identical to the
pre-run listing, and every removed image has a recorded digest.

### 6. Verify

1. **Sweep and compare.** `bash k3s-storage-cleanup/scripts/sweep.sh > after.txt`
2. **Recoverability, end to end.** The registry proof from 3a, plus one pull on
   a node that does not cache the image:

   ```bash
   # as root on that node, using a fresh isolated image store; pulls without
   # starting a container
   crictl --timeout 10m pull 192.168.0.236:5000/<repo>:<tag>
   ```

   `crictl pull` returns the resolved image ID, which must equal the digest
   printed in 3a. Verify afterwards that the node's containerd content
   directory grew by roughly the manifest's total size — filesystem growth is
   a measurement, not verification evidence. The complete download into the
   fresh isolated image store is the evidence that all layers were fetched
   rather than reused from cache. Then `crictl --timeout 5m rmi`, **settle**,
   and confirm the size returned.

3. **No regression.** Compare against the preflight snapshots: node readiness,
   pod phase counts, every volume's `state`/`robustness`, etcd
   `endpoint health --cluster` (3/3), and restart counts of the workloads.
4. **Nothing rotated.** No node newly cordoned; no volume newly detached.

**Done when** eligible work is complete, protected objects are intact, and no
health signal is worse than its preflight value. Pre-existing exceptions stay
exceptions: server-236/server-252 Longhorn `ManagerPodMissing`, the detached
volume, the server-252 cordon.

### 7. Report

Read [`reference/measurement.md`](reference/measurement.md) first — it is what
keeps the arithmetic honest. One headline figure (filesystem delta),
directory-level reductions listed separately and never summed, and a **scoped**
conclusion: "eligible cleanup completed without observed service disruption,
these exceptions remain" is defensible; "fully healthy" is not.

**Done when** every table's rows sum to its stated total, every figure names its
unit and source, and the retained/protected/pre-existing lists are present.

### 8. Keep it from coming back

Recurrence prevention is deployed — `monitoring/node-disk-cleanup` (10-node
DaemonSet, 6-hourly, shared lock). Audit it rather than reinventing it:

```bash
kubectl -n monitoring get ds node-disk-cleanup          # 10/10 ready
kubectl -n monitoring logs -l app=node-disk-cleanup --tail=5
```

Unattended, it only does what needs no eligibility judgement: journald cap,
vacuum, and `kern.log` cleanup every cycle. It must not prune images, even
behind the 80% emergency gate; image cleanup remains subject to the same
recoverability and eligibility checks in this procedure. Planned cleanup runs
through this procedure.

**Done when** the DaemonSet is 10/10 and each pod logs its Tier 1 line.

## Rollback

| Change | Revert |
| :-- | :-- |
| `node-disk-cleanup` ConfigMap | `git checkout -- kubernetes-manifests/monitoring/node-disk-cleanup.yaml`, apply, rollout restart |
| journald cap drop-in | `rm /etc/systemd/journald.conf.d/10-homelab-cap.conf && systemctl restart systemd-journald` |
| Deletions in steps 2–5 | not reversible by design; each was eligibility-checked and logged, and images remain recoverable from the registry |

## Reference

- [`reference/measurement.md`](reference/measurement.md) — units, additive vs
  non-additive figures, the reconciliation pattern.
- [`reference/execution-contract.md`](reference/execution-contract.md) — the
  contract any automated implementation (audit/apply, lock, candidates,
  bounded waits, reports, tests) must satisfy.
- [`reference/troubleshooting.md`](reference/troubleshooting.md) — failure
  signatures and how each one lied.
- `docs/operations/disk-reclaim-2026-10-18.md` — worked example, including the
  six arithmetic corrections it took.
