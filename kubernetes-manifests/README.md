# Kubernetes Manifests for Multi-Node K3s Cluster

This directory contains Kubernetes manifests for a 9–11-node K3s homelab cluster (control-plane `nuc` + workers; see `../WindowsLab/homelab-nodes.json` for the node source of truth). All manifests are organized per application/namespace and aggregated via `kustomization.yaml`.

## Directory Structure

```
kubernetes-manifests/
├── kustomization.yaml              # Top-level Kustomization — aggregates all apps
├── ai-language-learning.yaml        # ai-language-learning ns (backend, postgres, schema ConfigMap)
├── iiq-stateful.yaml               # iiqstack ns (IIQ, LDAP, ActiveMQ, MSSQL, MySQL, Mailpit, etc.)
├── iiq-networkpolicy.yaml          # iiqstack network policies (default-deny + allow-internal)
├── iiq-serviceaccount.yaml         # iiqstack ServiceAccount
├── iiq misc/                       # iiqstack extras: init job, iiq Deployment/Service, HA ref, recovery README
├── base/
│   └── ollama-deployment.yaml      # ai ns (Ollama, Open WebUI, PVCs, ingress)
├── linguacafe/                     # linguacafe ns (webapp, MariaDB, Redis, netpols)
├── media/                          # media ns (books, photos, file sharing, DB explorer)
│   ├── kustomization.yaml
│   ├── audiobookshelf.yaml
│   ├── calibre-web-with-importer.yaml
│   ├── chaptarr.yaml                 # Audiobook/eBook manager (Readarr fork)
│   ├── bookorbit.yaml              # + bookorbit-db StatefulSet (pgvector Postgres)
│   ├── bookhoarder.yaml
│   ├── booklogr.yaml
│   ├── librislog.yaml
│   ├── openlingo.yaml              # openlingo ns: app, db, netpols, PDB
│   ├── immich.yaml                 # Photos: server, ML, Valkey, pgvector Postgres
│   ├── immich-pdb.yaml
│   ├── immich-db-backup.yaml       # nightly pg_dump to NAS + restore check
│   ├── flick.yaml                  # File sharing: Go API, web, Caddy, Postgres
│   └── pgweb.yaml                  # PostgreSQL explorer (no default DB)
├── homepage/
│   └── homepage.yaml               # homepage ns (gethomepage dashboard + ConfigMap + Tailscale svc)
├── cloudflare/                     # cloudflare ns (Cloudflare Tunnels, standalone apply)
│   ├── README.md                   # public-exposure guide: gate, edge-rot failure mode, no-domain constraints
│   ├── cloudflared.yaml            # LIVE: ns + RBAC + Homepage Quick Tunnel (hardened)
│   ├── quick-tunnel-audiobookshelf.yaml  # LIVE: ABS Quick Tunnel -> nginx gate
│   ├── abs-gate.py                 # gate source: login form + HMAC session cookies
│   ├── render-abs-auth-proxy.py    # renders the manifest from source; --check fails if stale (CI)
│   ├── abs-auth-proxy.tmpl         # manifest skeleton with a gate-code placeholder
│   ├── abs-auth-proxy.yaml         # LIVE: GENERATED from the two files above - do not hand-edit
│   └── permanent-tunnel-homepage.yaml  # standby: named tunnel, needs token + a domain
├── monitoring/                     # monitoring ns (observability + notifications)
│   ├── kustomization.yaml
│   ├── beszel-hub.yaml
│   ├── beszel-agent.yaml
│   ├── uptime-kuma.yaml (+ monitors, sync)
│   ├── kuvasz.yaml / lantern.yaml / pooml.yaml / omnisight.yaml
│   ├── dozzle.yaml / logchef.yaml / trove.yaml
│   ├── lan-sheriff.yaml / languard.yaml / homelab-monitor.yaml
│   └── gotify.yaml / apprise.yaml  # push notifications + relay gateway
├── dashboard/                      # dashboard ns (Homarr, Cairn)
├── server-management/              # server-management ns (HomeLab Manger, RemotePower)
├── longhorn-backup/                # longhorn-system platform config
│   ├── kustomization.yaml
│   ├── 01-backup-target-settings.yaml
│   ├── 02-recurring-jobs.yaml      # snapshot-frequent (retain 4) + backup-daily
│   ├── 03-filesystem-trim-optional.yaml
│   ├── 04-node-failure-resilience.yaml
│   ├── 05-storage-reserve.yaml     # disk reserve 20%
│   └── 06-storageclass-r1.yaml     # single-replica class for lightweight data
├── tailscale-proxyclass.yaml       # Platform: Tailscale ProxyClass CRD
├── registry-fixer.yaml              # Platform: DaemonSet that fixes /etc/containers/registries.conf
├── mssql-fixer.yaml                # Operational: MSSQL permission fixer Job
├── mssql-wipe.yaml                 # Operational: MSSQL data wipe Job
├── keycloak.yaml                   # Future: Keycloak deployment (not yet deployed)
├── keycloak-ingress.yaml           # Future: Keycloak ingress
├── namespace-keycloak.yaml         # Future: Keycloak namespace
└── docker-compose.yaml             # Reference: original docker-compose for IIQ stack
```

## Applications (Live on Cluster)

| # | Namespace | App | Manifest |
|---|-----------|-----|----------|
| 1 | `ai` | Ollama + Open WebUI | `base/ollama-deployment.yaml` |
| 2 | `ai-language-learning` | AI Language Tutor (custom backend + Postgres) | `ai-language-learning.yaml` |
| 3 | `openlingo` | OpenLingo (Next.js language platform + Postgres) | `media/openlingo.yaml` |
| 4 | `linguacafe` | LinguaCafe (reading app + MariaDB + Redis) | `linguacafe/` |
| 5 | `iiqstack` | SailPoint IdentityIQ + LDAP + ActiveMQ + MSSQL + MySQL + Mailpit | `iiq-stateful.yaml` (+ `iiq misc/` for init job & recovery docs) |
| 6 | `media` | AudioBookshelf (also public via Cloudflare Quick Tunnel), Calibre-Web, Chaptarr, BookOrbit, BookHoarder, Booklogr, LibrisLog, OpenLingo, Immich, Flick, pgweb | `media/` + `cloudflare/quick-tunnel-audiobookshelf.yaml` |
| 7 | `homepage` | gethomepage dashboard (public via Cloudflare Quick Tunnel) | `homepage/homepage.yaml` + `cloudflare/cloudflared.yaml` |
| 8 | `monitoring` | Beszel, Uptime Kuma, Kuvasz, Lantern, PooML, OmniSight, Dozzle, Logchef, Trove, LAN Sheriff, LanGuard, Homelab Monitor, Gotify, Apprise | `monitoring/` |
| 9 | `dashboard` | Homarr, Cairn | `dashboard/` |
| 10 | `server-management` | HomeLab Manger, RemotePower | `server-management/` |

## Deployment

```bash
# Apply everything at once
kubectl apply -k ./kubernetes-manifests

# Or apply individual apps
kubectl apply -f kubernetes-manifests/iiq-stateful.yaml
kubectl apply -k ./kubernetes-manifests/media
kubectl apply -f kubernetes-manifests/base/ollama-deployment.yaml
```

## Tailscale Access

Web services are exposed on the Tailnet via the Tailscale Kubernetes Operator. Each Service that should be reachable gets these annotations:

```yaml
annotations:
  tailscale.com/expose: "true"
  tailscale.com/proxy-class: "tailscale-proxy"
  tailscale.com/hostname: "my-app"
```

## Public Access (Cloudflare Tunnels -> Homepage + Audiobookshelf)

Homepage and Audiobookshelf are published via Cloudflare **Quick Tunnels** (no
token, ephemeral `*.trycloudflare.com` URLs). Read `cloudflare/README.md` before
changing anything here — it documents the session-cookie gate in front of
Audiobookshelf, the silent edge-route failure mode, and why CF Access and named
tunnels are both unavailable without owning a domain.

Audiobookshelf is **gated**; Homepage is not (a dashboard holds no library data).
Both URLs are ephemeral and can rot — never record one in a document. Get the
current pair on demand:

```bash
pwsh -File ./WindowsLab/Get-CloudflareTunnelUrls.ps1 -Verify   # exits 1 if one is dead
```

```bash
# Deploy
kubectl apply -f cloudflare/cloudflared.yaml                  # Homepage
kubectl apply -f cloudflare/abs-auth-proxy.yaml               # ABS gate (generated; see below)
kubectl apply -f cloudflare/quick-tunnel-audiobookshelf.yaml  # ABS Quick Tunnel -> the gate

# Regenerate the ABS gate manifest after editing its source
cd cloudflare && python3 render-abs-auth-proxy.py && kubectl apply -f abs-auth-proxy.yaml

# Permanent named tunnel (needs token AND a domain you own; standby manifest)
kubectl apply -f cloudflare/permanent-tunnel-homepage.yaml
```

`abs-auth-proxy.yaml` is **generated**. `abs-gate.py` is the application source
and `abs-auth-proxy.tmpl` the skeleton; run `python3 render-abs-auth-proxy.py`
after editing either. `--check` exits non-zero when the committed manifest is
stale, which is the CI hook. The rendered Deployment carries a `gate-sha256` pod
annotation so a code change actually rolls the pods — ConfigMap updates alone do
not.

The `cloudflare/` manifests are intentionally NOT part of the top-level `kustomization.yaml` — the Quick Tunnel is ephemeral and the permanent manifest ships with a placeholder token that sleeps until a real token is set.

## Storage

- **Longhorn** — default dynamic provisioning for stateful workloads (Postgres, MariaDB, MSSQL, etc.)
- **Longhorn `longhorn-r1`** — single-replica class for lightweight, rebuildable data (see `longhorn-backup/06-storageclass-r1.yaml`); default disks reserve 20% (`05-storage-reserve.yaml`)
- **NFS** (`storageClassName: nfs-nas`) — Synology NAS at `192.168.0.128` for large media libraries (audiobooks, e-books, Ollama models)
- **Static PVs** — NFS-backed PersistentVolumes with explicit `claimRef` bindings for Audiobookshelf and Calibre

## Configuration

- Secrets containing plaintext credentials are checked into the repo (homelab context).
- Replace `REPLACE_ME` placeholders with real values before deploying.
- Ensure PersistentVolumeClaims are properly configured for stateful services.
