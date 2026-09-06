# K3S Cluster ↔ Repo YAML Drift Report

Generated: 2026-06-30. Compares live K3s cluster (kubeconfig `default`, server `https://192.168.0.21:6443`, 9 nodes, k3s v1.34.6) against `kubernetes-manifests/`.

## Methodology
- Live manifests dumped per namespace to `/tmp/cluster_live` and normalized (cluster-injected fields stripped).
- Container images compared across all repo vs live workloads.
- Secrets/ConfigMaps/PVCs/Services cross-checked.

---

## A. Confirmed drift requiring file edits

| # | Namespace | Repo file | Issue | Live truth |
|---|-----------|-----------|-------|------------|
| 1 | openlingo | `media/openlingo.yaml` | Stale image tag | `openlingo:v10-dynamic-models` (repo has `v9-parser-fix`) |
| 2 | openlingo | `media/openlingo.yaml` | Secret missing key | live `openlingo-secrets` has `EXA_API_KEY` (not in repo) |
| 3 | ai-language-learning | `ai-language-learning.yaml` | Missing ConfigMap | deploy references `ai-lang-schema` ConfigMap but it is never **defined** in repo (exists live) |
| 4 | ai (ollama) | `live-ollama.yaml` | Stale + wrong encoding | UTF-16 raw dump; live deploy has 2 volumes (`ollama-pvc` + `ollama-nas-pvc`), node affinity to k5/k6, resources 4 CPU/8Gi |
| 5 | media | `media/kustomization.yaml` | References stale file | lists `calibre-web.yaml` but live deploy is the **with-importer** variant (`calibre-web`+`calibre-importer` sidecar, `init-library`) |
| 6 | homepage | (none) | **Entire app missing** | deploy `homepage` + service + `homepage-config` ConfigMap exist live, no repo file |

## B. Structural mess — duplicate/stale files

The repo accumulated overlapping generations of manifests. Only the most recent per app reflects live state:

### iiqstack (canonical = `iiq-stateful.yaml`)
`iiq-stateful.yaml` matches live (iiq `sailpoint-iiq:8.5` w/ `wait-and-prep-nas`, replicas:2; statefulsets for ldap/activemq/db/db-mysql/mail; counter/ssh/phpldapadmin as deploy; iiq-init Job). **Stale duplicates:**
- `base/` directory (Deployment-style, images like `sailpoint-docker:latest`, `traefik:3.2.0`, `mssql:2019-latest`) — superseded
- `iiq-deployment.yaml` (top-level) — superseded
- `iiq-mssql-test.yaml` — experiment
- `live-iiq.yaml`, `live-db.yaml` — stale partial dumps

### media audiobookshelf
`media/audiobookshelf.yaml` matches live (`:2.35.1`). OK.
`k3s-manifest.yaml` (top-level) has stale `audiobookshelf:latest` — superseded.

### openlingo (canonical = `media/openlingo.yaml`)
`freelingo/` directory is an unrelated/abandoned draft (uses `ghcr.io/artcc/freelingo-*` images, not deployed). Stale.

## C. Live-only objects the repo should capture

- `default/mysql-init-script` ConfigMap (referenced by db-mysql? verify) — 91d old
- `homepage/homepage-config` ConfigMap — part of missing homepage app (#6)
- Static PersistentVolumes for media: `audiobookshelf-books-pv`, `calibre-import-pv`, `calibre-library-pv` (500Gi RWX, Retain) — needed for calibre/audiobookshelf to bind

## D. Verified in-sync (no change needed)

- `linguacafe/*` — all 4 images match live; `linguacafe-patch` ConfigMap defined in `05-linguacafe-config.yaml`
- `media/audiobookshelf.yaml` — image matches
- `monitoring/*` (beszel hub+agent) — matches live
- `iiq-stateful.yaml` — matches live iiqstack

## E. Out of scope (platform/system namespaces — not user-deployed apps)
`kube-system`, `argocd`, `longhorn-system`, `cnpg-system`, `tailscale` — managed by their own operators/installers. The `registry-fixer.yaml` and `tailscale-proxyclass.yaml` in repo are platform config, left as-is.
