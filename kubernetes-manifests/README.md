# Kubernetes Manifests for Multi-Node K3s Cluster

This directory contains Kubernetes manifests for a 9-node K3s homelab cluster (1 control-plane `nuc` + 8 workers). All manifests are organized per application/namespace and aggregated via `kustomization.yaml`.

## Directory Structure

```
kubernetes-manifests/
├── kustomization.yaml              # Top-level Kustomization — aggregates all apps
├── ai-language-learning.yaml        # ai-language-learning ns (backend, postgres, schema ConfigMap)
├── iiq-stateful.yaml               # iiqstack ns (IIQ, LDAP, ActiveMQ, MSSQL, MySQL, Mailpit, etc.)
├── iiq-networkpolicy.yaml          # iiqstack network policies (default-deny + allow-internal)
├── iiq-serviceaccount.yaml         # iiqstack ServiceAccount
├── base/
│   └── ollama-deployment.yaml      # ai ns (Ollama, Open WebUI, PVCs, ingress)
├── linguacafe/                     # linguacafe ns (webapp, MariaDB, Redis, netpols)
├── media/                          # media ns (books, photos, file sharing, DB explorer)
│   ├── kustomization.yaml
│   ├── audiobookshelf.yaml
│   ├── calibre-web-with-importer.yaml
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
│   └── homepage.yaml               # homepage ns (gethomepage dashboard + ConfigMap)
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
| 5 | `iiqstack` | SailPoint IdentityIQ + LDAP + ActiveMQ + MSSQL + MySQL + Mailpit | `iiq-stateful.yaml` |
| 6 | `media` | AudioBookshelf, Calibre-Web, BookOrbit, BookHoarder, Booklogr, LibrisLog, OpenLingo, Immich, Flick, pgweb | `media/` |
| 7 | `homepage` | gethomepage dashboard | `homepage/homepage.yaml` |
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

## Storage

- **Longhorn** — default dynamic provisioning for stateful workloads (Postgres, MariaDB, MSSQL, etc.)
- **Longhorn `longhorn-r1`** — single-replica class for lightweight, rebuildable data (see `longhorn-backup/06-storageclass-r1.yaml`); default disks reserve 20% (`05-storage-reserve.yaml`)
- **NFS** (`storageClassName: nfs-nas`) — Synology NAS at `192.168.0.128` for large media libraries (audiobooks, e-books, Ollama models)
- **Static PVs** — NFS-backed PersistentVolumes with explicit `claimRef` bindings for Audiobookshelf and Calibre

## Configuration

- Secrets containing plaintext credentials are checked into the repo (homelab context).
- Replace `REPLACE_ME` placeholders with real values before deploying.
- Ensure PersistentVolumeClaims are properly configured for stateful services.
