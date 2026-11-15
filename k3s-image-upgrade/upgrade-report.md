# k3s-image-upgrade — report

## 2026-11-15 — dry run (steps 0–2 only, no images changed)

Preflight: `git status` had 0 tracked modifications; 8 of 10 nodes Ready
(`kubernetes8-debian`, `server-236` still absent from L2); 0 non-running pods.

Inventory: 61 distinct images across Deployments, StatefulSets and DaemonSets.

| Class | Count | Action |
| :-- | --: | :-- |
| local build (`192.168.0.236:5000`) | 1 | skip — `k3s-dind-build` |
| floating (`latest` / untagged) | 12 | record only |
| operator-owned (`tailscale/*`) | 2 | upgrade the operator |
| out-of-tree (no manifest here) | 19 | skip — Longhorn ×9, Rancher core ×5, CNPG, Dex, redis (argocd), nfs-subdir provisioner |
| **candidates** | **27** | step 3 onwards |

### Candidates

| App | Image | Manifest |
| :-- | :-- | :-- |
| audiobookshelf | `ghcr.io/advplyr/audiobookshelf:2.37.1` | `media/audiobookshelf.yaml` |
| calibre-web | `ghcr.io/linuxserver/calibre-web:0.6.27-ls404` | `media/calibre-web-with-importer.yaml` |
| chaptarr | `chaptarr/chaptarr:0.9.965` | `media/chaptarr.yaml` |
| cloudflared | `cloudflare/cloudflared:2026.10.0` | `cloudflare/quick-tunnel-audiobookshelf.yaml` |
| caddy (flick) | `caddy:2-alpine` | `media/flick.yaml` |
| flick-api | `dellixou/flick-api:v0.2.10` | `media/flick.yaml` |
| flick-web | `dellixou/flick-web:v0.2.10` | `media/flick.yaml` |
| postgres (flick) | `postgres:16-alpine` | `media/flick.yaml` |
| immich-server | `ghcr.io/immich-app/immich-server:v3.3.1` | `media/immich.yaml` — **migration, step 4** |
| immich-ml | `ghcr.io/immich-app/immich-machine-learning:v3.3.1` | `media/immich.yaml` — **migration, step 4** |
| immich-db | `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0` | `media/immich.yaml` — **migration, step 4** |
| valkey | `valkey/valkey:9` | `media/immich.yaml` |
| reactive-resume | `ghcr.io/reactive-resume/reactive-resume:v5.3.1` | `media/reactive-resume.yaml` |
| gotify | `gotify/server:3.1.1` | `monitoring/gotify.yaml` |
| uptime-kuma | `louislam/uptime-kuma:2.5.5` | `monitoring/uptime-kuma.yaml` |
| dozzle | `amir20/dozzle:v11.3.0` | `monitoring/dozzle.yaml` |
| busybox | `docker.io/library/busybox:1.36` | `monitoring/node-disk-cleanup.yaml`, `registry-fixer.yaml` |
| nginx (auth proxy) | `docker.io/nginxinc/nginx-unprivileged:1.27-alpine` | `cloudflare/kuma-auth-proxy.yaml` |
| python (auth proxy) | `docker.io/library/python:3.12-alpine` | `cloudflare/kuma-auth-proxy.yaml` |
| remotepower | `ghcr.io/tyxak/remotepower:7.0.3` | `server-management/remotepower.yaml` |
| activemq | `apache/activemq-artemis:2.31.2-alpine` | `iiq-stateful.yaml` |
| mssql | `mcr.microsoft.com/mssql/server:2019-CU28-ubuntu-20.04` | `iiq-stateful.yaml` — **major = migration** |
| openldap | `osixia/openldap:1.5.0` | `docker-compose.yaml` only — **out of scope** |
| mariadb | `mariadb:10.11` | `linguacafe/03-mariadb.yaml` — **major = migration** |
| redis (linguacafe) | `redis:7.2-alpine` | `linguacafe/05-redis.yaml` |
| longhorn-manager (helper) | `docker.io/longhornio/longhorn-manager:v1.12.1` | `longhorn-backup/07-nfs40-premount.yaml` — reference only, not a servable workload |

### Corrections this dry run forced on the skill

- `docker-compose.yaml` matches are not cluster workloads; excluded from scope.
- Shell tag detection misclassified every pinned image as floating — the registry
  port in `192.168.0.236:5000/x:1` breaks naive `:` splitting. Step 1 now
  prescribes a script-based classifier.
- Some files name an image they do not run (mount helper, upgrade note); the
  owning pod template must be confirmed before editing.

No commits, no rollouts, no image changes were made.

## 2026-11-15 — live sweep 1 (3 upgrades, 1 skip)

Preflight: 0 tracked modifications, 8/10 nodes Ready, 0 non-running pods.
Each app: edit manifest → `--dry-run=server` → apply → `rollout status` → health
gate → commit → push. One app in flight at a time.

| App | From | To | Gate | Commit | Outcome |
| :-- | :-- | :-- | :-- | :-- | :-- |
| dozzle | `v11.3.0` | `v11.4.3` | Ready 1/1, 0 restarts, PVC `pvc-8ed467c0` still Bound, `http://dozzle` 200 | `0bb8d25` | upgraded |
| uptime-kuma | `2.5.5` | `2.5.11` | Ready 1/1, 0 restarts, PVC `pvc-4a422cda` still Bound, `http://uptime-kuma` 302 (login), logs clean | `6d1ebff` | upgraded |
| audiobookshelf | `2.37.1` | `2.37.2` | Ready 1/1, 0 restarts, both PVCs Bound, `http://audiobookshelf` 200, "No migrations to run" | `5e716b3` | upgraded |
| gotify | `3.1.1` | `3.1.1` | — | — | skipped — already current on Docker Hub |

### Findings from the live run

- **ghcr truncates `/tags/list` at 100.** The bare call returned 100 tags ending
  at `2.19.0`, hiding the `2.37.2` actually deployed. `?n=1000` returns all 135.
  Step 3 now documents this.
- **Dozzle logs a non-fatal RBAC warning** after the bump: kubelet answers 403 on
  `nodes/stats` for 8 nodes, so container sizes are unavailable. Its ClusterRole
  grants `nodes` but not `nodes/stats`. Serving is unaffected (`200`, pods
  readable); worth a separate manifest fix, not part of an image bump.
- **`kubectl apply` on a file containing a PVC prints a `volumeName` diff** even
  when the PVC is untouched (`pvc-8ed467c0` → `""`). The binding survives (the
  API keeps it), but read that diff rather than assuming a silent no-op.
- **Tailscale hostnames are the bare MagicDNS names**: `http://dozzle`,
  `http://uptime-kuma`, `http://audiobookshelf`. `http://kuma` resolves to
  nothing — the probe must use the `tailscale.com/hostname` annotation.

No rollbacks were needed. Cluster stayed at 8/10 Ready throughout (the two
absent nodes are unchanged from before the sweep).

## 2026-11-15 — live sweep 2 (3 upgrades, 2 skips)

| App | From | To | Gate | Commit | Outcome |
| :-- | :-- | :-- | :-- | :-- | :-- |
| chaptarr | `0.9.965` | `0.9.1000` | Ready 1/1, 0 restarts, `http://chaptarr` 200 | `7372bde` | upgraded |
| calibre-web | `0.6.27-ls404` | `0.6.27-ls410` | Ready 2/2 (both containers), 0 restarts, endpoints populated, in-cluster 200 | `b028e93` | upgraded |
| redis (linguacafe) | `7.2-alpine` | `7.4-alpine` | Ready, 0 restarts, `redis_version` from INFO, Linguacafe login 200 | `ecdabad` | upgraded |
| gotify | `3.1.1` | `3.1.1` | — | — | skipped — already newest on Docker Hub |
| reactive-resume | `v5.3.1` | `v6.0.7` | — | — | **skipped — major jump with Postgres migrations** |

### Findings

- **The gate failed twice on calibre-web, and both times the app was healthy.**
  First it grepped for `1/1` on a two-container pod (`calibre-web` +
  `calibre-importer`), so it saw "no ready pod" and rolled back a good rollout.
  Then an in-cluster probe pod returned no parseable output and failed again.
  Step 5 now records both traps; the working gate uses the pod's `Ready`
  condition (which implies the manifest's `readinessProbe` GET `:8083/` passed).
- **`calibre-web`'s tailnet node is dead independently of the image.** It answers
  `tailscale ping` but has neither 80 nor 443 open, so no hostname probe can
  work. Pre-existing: its proxy pod is 28 days old.
- **`reactive-resume` is a migration, not a bump**: `v5.3.1` → `v6.0.7` carries
  Postgres schema changes. Added to the step 4 table rather than swept.
- **redis stops at 7.4.** `7.2-alpine` → `7.4-alpine` is the last 7.x minor;
  `8.10-alpine` is a major for a service holding session and queue state.

Both gate failures were reverted cleanly (`rollout undo` + `git restore`), so no
broken commit reached `origin` — the gate-before-commit ordering did its job.
