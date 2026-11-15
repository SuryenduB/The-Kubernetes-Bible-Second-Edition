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
