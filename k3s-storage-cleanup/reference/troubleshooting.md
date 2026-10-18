# Troubleshooting

Failure signatures from real runs, in the order they are likely to bite.

## A removal "succeeded" but the image count did not move

```
rpc error: code = DeadlineExceeded desc = context deadline exceeded
```

crictl's default client deadline is 2 s. Removing a large image (or a batch of
them) aborts mid-flight, and because the command exits non-zero a surrounding
`|| log ...` hides it — the count looks pruned but only a fraction is gone.

**Fix:** raise the deadline for the removal itself and delete by ID so each
removal is attributable: `crictl --timeout 5m rmi <image-id>`. Re-running is
safe and idempotent. The DaemonSet keeps `--timeout 10m rmi --prune` for its
**emergency** path only (above 80%) — see `SKILL.md` step 8. Planned pruning is
per-ID and eligibility-checked.

## Space did not come back after `rmi`

containerd has not garbage-collected yet. `crictl images` (fast, metadata) drops
the reference immediately; `du` (blocks) follows when GC runs.

**Check:** compare `du -sk` of
`.../io.containerd.snapshotter.v1.overlayfs` and
`.../io.containerd.content.v1.content` separately — images retained by a running
container keep their snapshot but not their content blob, so one drops and the
other does not.

**Action:** wait, re-sweep (**settle**). Do not re-run the prune repeatedly; the
second run legitimately deletes nothing.

## `crictl: command not found`, or it cannot find the runtime

On these nodes `/usr/local/bin/crictl` is a symlink to the k3s multicall binary
and `/etc/crictl.yaml` is often absent — that is fine, crictl's default endpoint
list includes `/run/k3s/containerd/containerd.sock`.

It must run as **root** (the socket is `root:root 0660`). Use
`remote-admin.sh`, or the cleanup DaemonSet's `nsenter` path.

## journald cap is set but the journal grows anyway

Look in both places, and remember precedence:

```bash
grep -rnsE '^\s*SystemMaxUse' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/
systemctl show systemd-journald -p SystemMaxUse
```

A drop-in (`journald.conf.d/*.conf`) overrides `journald.conf`. A cap that is
commented out in `journald.conf` (`#SystemMaxUse=`) counts as *absent* — the
distribution default (10% of the filesystem) is in force. After writing a cap,
`systemctl restart systemd-journald`; without the restart the old value stays
loaded.

## The ConfigMap is updated but nodes still run the old script

The DaemonSet loop is `run once, sleep 21600`. A ConfigMap edit reaches the
mounted file within ~a minute but the running loop has already read it.

**Fix:** `kubectl -n monitoring rollout restart ds/node-disk-cleanup`. Restarting
this pod is safe — it is maintenance tooling, not a workload.

## SSH to 192.168.0.252 fails with `Permission denied (publickey,password)`

Not a username problem. `suryendub` is correct there; the Mac→HP-1 path is
filtered at the host level, so ICMP and TCP both time out or bounce while the
node is perfectly healthy.

**Action:** measure and administer in-cluster (`scripts/sweep.sh`, or the
cleanup pod's `nsenter`). Never infer a host is powered off from a TCP timeout
on this LAN — check ARP or the router's device list.

Related trap: `.236` is `server-236`, a Hyper-V guest on HP-1. It disappears
when HP-1 is off. `.103` is HP-1 itself.

## SSH username rejected

Case matters. `suryendub` on every Ubuntu worker, `nuc`, `server-252`;
**`SuryenduB` only on `server-236`** (whose hostname is
`install-Virtual-Machine` — that is also why naive hostname matching fails).

## Deleting an orphan dropped the replica count

You filtered on the wrong field. Longhorn's `Orphan` object carries
`spec.parameters.dataName` / `nodeID` and `status.{ownerID,dataCleanable,error}`;
the live set comes from `replicas.longhorn.io`. Confirm field names on one
object before filtering 300.

**Action:** stop deleting, re-read the replica count, check every volume's
`robustness`, and only then continue. If a volume is degraded, switch to
`qnap-nfs-longhorn-backup` before touching anything else.

## Longhorn node shows `Ready=False` with `ManagerPodMissing`

Pre-existing on `server-236` and `server-252` (missing `cryptsetup` /
`nfs-common`, multipathd). It is **not** caused by a disk reclaim and it does
not clear by pruning. Report it as a pre-existing exception; do not try to fix
it inside a reclaim run.

## `kubectl apply -k kubernetes-manifests/monitoring` fails on a missing env file

The monitoring kustomization includes a `secretGenerator` reading the
gitignored `uptime-kuma-credentials.env`. For a single-file change, apply the
file directly:

```bash
kubectl apply --dry-run=server -f kubernetes-manifests/monitoring/node-disk-cleanup.yaml
kubectl apply -f kubernetes-manifests/monitoring/node-disk-cleanup.yaml
```

## A pull test left the node bigger

The pushed image stays cached after the test pod is deleted. Remove it
(`crictl --timeout 5m rmi <ref>`), wait for GC, re-measure. If the node was
already caching that image for a live workload, leave it — it is in use.

## `imagePullPolicy: Always` did not prove the image is downloadable

A successful pull with `Always` does **not** prove a cold download: the runtime
resolves the tag through the registry but may reuse layers already in the
containerd content store. It proves the *reference* resolves, not that every
blob is fetchable — which is exactly how a missing manifest slips through.

**Fix:** prove completeness at the registry
(`registry-recoverability.py`: required platform manifest, config, HEAD every
layer by digest), then do one cache-free pull with the primitive that does not
start a container:

```bash
crictl --timeout 10m pull 192.168.0.236:5000/<repo>:<tag>
```

The returned image ID must equal the digest the script printed. Confirm the
node's `.../io.containerd.content.v1.content` grew by roughly the manifest's
total size — that is the evidence layers were fetched rather than reused. Then
`crictl --timeout 5m rmi`, settle, re-measure. Never start the application just
to test retrieval.

## Rollback of a deployment suddenly needs a pull

The eligible-image path protects images named in *any* Pod template and the
previous revision(s) inside the rollback window (`-RollbackRevisions`, default
1). Undo inside that window is cache-free. Undo *beyond* it re-pulls —
expected, and recoverable provided the registry can serve the image, which
step 6 proves. If a rollback target is not in the registry that is a
missing-manifest incident, not a reason to re-enable blanket pruning.

## A manual run and the 6-hourly DaemonSet collided

Both take `/run/lock/k3s-disk-cleanup.lock`. The loser logs
`another cleanup holds ... skipping this cycle` and exits 0 — no deletion, no
error. If maintenance is skipped on *every* cycle for one node, check
`[ -w /run/lock ]` there; absent a usable lock the script deliberately runs
unlocked rather than skipping forever, so a permanently-held lock means a
stuck manual run.

## An orphan is not proof its volume is gone

`Orphan` means Longhorn no longer *tracks* the directory — not that the data is
unwanted. Deleting the CR can delete the directory. Before deleting, every
clause of `SKILL.md` step 2b must hold: replica-data type,
`status.dataCleanable: true`, empty `status.error`, no `(node, disk,
directory)` tuple match against any live `replicas.longhorn.io`, age past the
floor, and no recovery-protection (degraded/faulted volume or replica, rebuild
in flight, backup/restore in progress). Revalidate immediately before the
delete. The completion target is "no **eligible** orphan remains" — retained
orphans are a legitimate outcome, each with a recorded reason.
