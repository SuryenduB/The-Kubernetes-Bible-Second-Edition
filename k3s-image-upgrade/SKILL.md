---
name: k3s-image-upgrade
description: Bump pinned external images in the K3s homelab one app at a time — resolve the owning manifest, apply, gate on health, then commit and push that app alone. Use when refreshing image versions across the cluster or auditing which deployed images are behind upstream.
---

# k3s-image-upgrade

Move the cluster forward one app at a time, and never let two changes share a
commit.

**One app → apply → health gate → one commit → one push.** The gate sits
*before* the commit: a failed rollout leaves nothing to unwind, because nothing
was committed yet. A sweep that modernises 30 apps and breaks one is a bad
sweep — nobody can tell which of the 30 commits broke it.

Two rules carry the rest:

- **Only what this repo owns can be upgraded this way.** A workload with no
  manifest under `kubernetes-manifests/` cannot be version-controlled, so it is
  skipped and recorded, never edited in-cluster.
- **A version is a claim, not a guess.** Never infer the next release from a
  semver increment. Resolve it from the registry or the project's release page,
  and record where the answer came from.

## When to use

- Refreshing pinned external images across the cluster, app by app.
- Auditing which deployed images sit behind their upstream release.
- Recovering version drift after a manual `kubectl set image`.

## Not for

- Images built locally (`192.168.0.236:5000/*`) → `k3s-dind-build`.
- Disk reclamation → `k3s-storage-cleanup`. Cordon/uncordon → `k3s-rebalance`.
- `kubernetes-manifests/docker-compose.yaml` — a compose file, not applied to the
  cluster. A match there does not put an app in scope.

## Guardrails

| Invariant | Why |
| :-- | :-- |
| Working tree is clean before the sweep starts | Each app's commit must contain that app's image change and nothing else |
| One app in flight, always | Two rollouts at once make a failure unattributable |
| Apply from the working tree; commit only after the gate | A failed candidate never enters history, so rollback is a checkout, not a revert |
| The manifest is the source of truth; `kubectl set image` is never the change | In-cluster edits are silently undone by the next `apply -k` |
| `kubectl apply -f <file>` / `-k <dir>` for the app, never `-k ./kubernetes-manifests` mid-sweep | The root kustomization would apply every unrelated pending edit |
| `192.168.0.236:5000/*` is never bumped | Built by `k3s-dind-build`; there is no upstream to ask |
| `:latest` and untagged images are recorded, not edited | They float already — a restart re-pulls them; editing changes nothing |
| Operator-generated workloads are left alone | `tailscale/ts-*` StatefulSets follow the operator; editing the pod template starts a fight the operator wins |
| Rollback is a checkout plus `rollout undo` — never `git reset --hard` | Rewriting pushed history loses the record of what was tried |
| Push only when the owner authorised the sweep | A 30-commit push is an external, hard-to-undo act |
| `nuc`, `server-236`, `server-252` are never cordoned or drained | Three embedded-etcd members, one lineage (see `AGENTS.md`) |
| A major-version jump with a data component stops the sweep | Those are migrations wearing a version bump |

## Procedure

### 0. Preflight

```bash
git status --porcelain          # no tracked modifications (untracked scratch is fine)
kubectl get nodes               # every node Ready
kubectl get pods -A --field-selector=status.phase!=Running | grep -v Completed
```

**Done when** the tree has no tracked modifications and no pod was already
failing — a pre-existing failure must not be blamed on the sweep.

### 1. Inventory what is actually running

Read the cluster, not just the repo: a running image can drift from its manifest.

```bash
work=$(mktemp -d)
kubectl get deploy,sts,ds -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.template.spec.containers[*].image}{"\n"}{end}' \
  | awk -F'\t' '{n=split($3,a," "); for(i=1;i<=n;i++) print $1"\t"$2"\t"a[i]}' \
  > "$work/images.tsv"
cut -f3 "$work/images.tsv" | sort -u > "$work/images.txt"
```

Classify each image, and record the class in the report:

| Class | Test | Action |
| :-- | :-- | :-- |
| local build | contains `192.168.0.236:5000` | skip — `k3s-dind-build` owns it |
| floating | tag is `latest`, or no tag at all | record, don't edit |
| operator-owned | namespace `tailscale` (`ts-*` pods), Longhorn system Deployments | upgrade the operator, not the workload |
| out-of-tree | no manifest in this repo (Longhorn, ArgoCD, KubeVirt, Rancher core, `k8s-operator`) | skip, record why |
| candidate | pinned, in-repo, not operator-owned | continue |

Classify with a script, not shell globs: a tag test must strip the registry port
first (`192.168.0.236:5000/x:1` has a port *and* a tag), and "no tag" is a
separate case from `latest`. A one-pass `python3` classifier over
`kubectl ... -o jsonpath` avoids both traps and prints the class counts in one
run.

**Done when** every image in the inventory carries one of those classes and the
counts sum to the distinct-image total.

### 2. Find the one manifest that owns the app

Match the **exact image string** first; a bare repo name over-matches (it hits
docs, reports and similarly named images):

```bash
grep -rn "ghcr.io/immich-app/immich-server" kubernetes-manifests
grep -rn "immich.yaml" kubernetes-manifests/*/kustomization.yaml kubernetes-manifests/kustomization.yaml
```

The same image often appears more than once — Deployment, init container, Job,
and a second copy in another namespace. All references move together, or the app
runs two versions. A file can also name an image it does not run, such as a
mount helper or a documented upgrade target; confirm the hit is the pod template
that actually serves the app.

**Skip the app** when it is operator-owned, out-of-tree, or only referenced by a
floating tag. **Done when** the app has a manifest file, the exact lines to
change, and a proceed-or-skip decision with its reason.

### 3. Resolve the target version — from evidence

This Mac has `kubectl`, `jq` and `curl`. It has **no** `docker`, `crane`,
`skopeo`, `regctl`, `helm` or `yq`.

```bash
# Docker Hub
curl -s "https://hub.docker.com/v2/repositories/library/redis/tags?page_size=25" | jq -r '.results[].name'

# ghcr.io: anonymous token, then the tag list — ask for enough tags in one go
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:advplyr/audiobookshelf:pull" | jq -r .token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://ghcr.io/v2/advplyr/audiobookshelf/tags/list?n=1000" | jq -r '.tags[]' | sort -V | tail -5
```

**ghcr truncates the tag list at 100** and paginates through a `link:` header
(`...?last=<tag>&n=0`). A bare `/tags/list` call happily returns exactly 100 tags
and looks complete — for `audiobookshelf` that hides every release above 2.19.0,
including the 2.37.2 actually deployed. Always pass `?n=` large enough, and
sanity-check the highest tag against what the cluster is already running.

For anything with a store of data, prefer the release notes, and read the
changelog between the two versions for breaking changes and required migrations.

**Done when** the target tag is named, its source recorded, and the changelog
between the versions read.

### 4. Apps whose upgrade is a migration — stop the loop

These live in this repo but must not be swept:

| App | Manifest | Why it stops the loop |
| :-- | :-- | :-- |
| `immich` | `kubernetes-manifests/media/immich.yaml` | Migrations run at startup, and the `immich-db` image (`postgres:14-vectorchord0.4.3`) is pinned to the vector extension — both move in lockstep. Take a fresh dump via the `immich-db-backup` CronJob first. |
| `mariadb` / `mssql` | `linguacafe/`, `iiq-stateful.yaml` | A CU update on the same major is in scope; a major jump is a dump/restore, not a tag change. |

**Done when** the app is either handed to step 5 or parked with the migration
step that unblocks it.

### 5. The per-app loop

For one app at a time — `<ns>`, `<manifest>`, `<workload>` are that app's:

```bash
# 5.1 edit the manifest lines found in step 2
# 5.2 validate the change before the cluster sees it
kubectl apply -f <manifest> --dry-run=server

# 5.3 roll it out from the working tree (nothing committed yet)
kubectl apply -f <manifest>
kubectl -n <ns> rollout status deploy/<workload> --timeout=300s
```

**Health gate — all of these, not just the rollout result:**

```bash
kubectl -n <ns> get pods -l app=<workload>           # Ready, RESTARTS 0 since rollout
kubectl -n <ns> logs deploy/<workload> --since=5m | grep -iE 'error|fatal|panic|migration failed'
kubectl -n <ns> get events --sort-by=.lastTimestamp | tail -10
```

Plus one functional probe: `curl -s -o /dev/null -w '%{http_code}' http://<hostname>`
on the app's Tailscale hostname (the bare MagicDNS name configured on its
Service — see `k3s-tailscale-proxy`), expecting `200`.

- **Gate passes** → commit and push *this app only*, then move on.
- **Gate fails** → roll back (step 6) and stop the sweep.

```bash
git add <manifest>
git commit -m "fix(<ns>): bump <app> to <version>"
git push origin main
```

**Done when** the push landed and `git show --stat HEAD` lists only this app's
manifest.

### 6. Rollback one app

The candidate was never committed, so rollback is local and leaves no trace on
`origin`:

```bash
kubectl -n <ns> rollout undo deploy/<workload>
kubectl -n <ns> rollout status deploy/<workload> --timeout=300s
git restore <manifest>                            # discard the un-applied candidate
```

Verify the old tag is actually running again before reporting the app reverted —
`rollout undo` succeeds even when the old image no longer pulls.

If the app had already been pushed before a later problem surfaced, revert
forward with `git revert --no-edit <sha>`; never rewrite `main`.

### 7. Record

Append one row per app to `k3s-image-upgrade/upgrade-report.md`, creating it on
first use:

| App | From | To | Class or gate | Commit | Outcome |
| :-- | :-- | :-- | :-- | :-- | :-- |

`Outcome` is one of `upgraded`, `reverted`, or `skipped` — and a skip always
names its class (`floating`, `local build`, `operator-owned`, `out-of-tree`,
`migration required`). Write the release URL in the commit body.

**Done when** every image in the inventory has a row. The sweep's success metric
is *no unexplained image*, not *every image at latest*.

## Stop the sweep when

- Two apps in a row fail their gate.
- A rollout fails on a StatefulSet with a data volume.
- Rollout stalls on `ImagePullBackOff` — a registry or tag problem, not a
  version problem.
- Node readiness, etcd health or Longhorn volume robustness changes at all.

## Commit style

Lowercase conventional prefix, one app per commit:

```
fix(media): bump immich to v3.4.0
chore(monitoring): bump grafana to 12.1.0
fix(linguacafe): bump redis to 7.4-alpine
```
