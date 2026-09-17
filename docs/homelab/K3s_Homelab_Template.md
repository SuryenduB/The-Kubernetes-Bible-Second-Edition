# 🏠 K3s Homelab - Complete Kubernetes Environment

**Last Updated**: 2026-09-17 | **Scope**: Application inventory and MagicDNS refreshed; other audit snapshots retain their original dates | **Version**: K3s v1.34.6+k3s1

---

## 📋 Table of Contents

1. [Operational Guides](#operational-guides)
2. [Cluster Overview](#cluster-overview)
3. [Application Access & URLs](#application-access--urls)
4. [System Infrastructure](#system-infrastructure-audit-snapshot)
5. [Kubernetes Cluster Health](#kubernetes-cluster-health)
6. [Observability & Monitoring](#observability--monitoring)
7. [Storage Architecture](#storage-architecture)
8. [Governance & Security](#governance--security)
9. [Local Docker Registry](#local-docker-registry)
10. [Audit & Compliance Reference](#audit--compliance-reference)
11. [Troubleshooting](#troubleshooting)
12. [Documentation References](#documentation-references)

---

## 🚀 Operational Guides

For executing cluster tasks, refer to the following goal-oriented **How-to Guides**:
* 🔌 [How to Manage Cluster Power](how-to-manage-homelab-power.md): Steps to safely power on, shut down, and manage SecretStore credentials.
* 🛡️ [How to Audit and Recover Cluster](how-to-audit-homelab.md): Steps to trigger audits, check certificates, inspect the local registry, manage backups, and restore Tailscale VPN access.

---

## 🗺️ Cluster Overview

### Architecture Diagram
![Homelab Architecture](homelab_architecture.png)

### Cluster Configuration
- **Kubernetes Version**: K3s v1.34.5+k3s1 (control plane: nuc) / v1.34.6+k3s1 (workers)
- **Nodes**: 9 total (1 control-plane + 8 workers)
- **Status**: ✅ All Ready (Verified 2026-05-10)
- **Network**: Flat LAN (192.168.0.0/24)
- **Storage**: Longhorn (Production) + QNAP NAS (Legacy/Backup)
- **CNI**: Flannel (default K3s)
- **Ingress**: Traefik (automatic with K3s)

---

## 🌐 Application Access & URLs

### Web Applications (Tailscale MagicDNS)

Inventory refreshed on **2026-09-17** from live workloads, Service ports, and the Tailscale operator's recorded device FQDNs. Hostnames below are registered names, not end-to-end reachability tests. Access requires a connected Tailscale client and applicable tailnet permissions.

| MagicDNS setting | Verified value |
|------------------|----------------|
| Tailnet DNS domain | `tail35421d.ts.net` |

#### AI & Language Learning

| Application | Namespace | MagicDNS access | Purpose |
|-------------|-----------|-----------------|---------|
| Ollama | `ai` | Internal only; no dedicated Tailscale proxy found | Local AI model serving |
| Open WebUI | `ai` | <http://openwebui.tail35421d.ts.net:8080> | AI chat interface |
| AI Language Tutor | `ai-language-learning` | <http://lang-tutor.tail35421d.ts.net> | Custom language-learning backend |
| OpenLingo | `openlingo` | <http://openlingo.tail35421d.ts.net> | Language-learning platform |
| LinguaCafe | `linguacafe` | <http://linguacafe.tail35421d.ts.net> | Language learning through reading |

#### Books & Media

| Application | Namespace | MagicDNS access |
|-------------|-----------|-----------------|
| Audiobookshelf | `media` | <http://audiobookshelf.tail35421d.ts.net> |
| Calibre-Web | `media` | <http://calibre-web.tail35421d.ts.net:8083> |
| BookHoarder | `media` | <http://bookhoarder.tail35421d.ts.net> |
| Booklogr | `media` | <http://booklogr.tail35421d.ts.net> |
| BookOrbit | `media` | <http://bookorbit.tail35421d.ts.net> |
| LibrisLog | `media` | <http://librislog.tail35421d.ts.net> |

#### Dashboards & Server Management

| Application | Namespace | MagicDNS access |
|-------------|-----------|-----------------|
| Homepage | `homepage` | <http://homepage-homepage.tail35421d.ts.net> |
| Homarr | `dashboard` | <http://homarr.tail35421d.ts.net> |
| Cairn | `dashboard` | <http://cairn.tail35421d.ts.net> |
| Homelab Manager | `server-management` | <http://homelab-manger.tail35421d.ts.net> |
| RemotePower | `server-management` | <http://remotepower.tail35421d.ts.net> |

The spelling `homelab-manger` matches the deployed Service and registered hostname.

#### Monitoring & Observability

| Application | Namespace | MagicDNS access |
|-------------|-----------|-----------------|
| Beszel Hub | `monitoring` | <http://beszel.tail35421d.ts.net> |
| Dozzle | `monitoring` | <http://dozzle.tail35421d.ts.net> |
| Gotify | `monitoring` | <http://gotify.tail35421d.ts.net> |
| Homelab Monitor | `monitoring` | <http://homelab-monitor.tail35421d.ts.net> |
| Kuvasz | `monitoring` | <http://kuvasz.tail35421d.ts.net> |
| LAN Sheriff | `monitoring` | <http://lan-sheriff.tail35421d.ts.net> |
| LanGuard | `monitoring` | <http://languard.tail35421d.ts.net> |
| Lantern | `monitoring` | <http://lantern.tail35421d.ts.net> |
| LogChef | `monitoring` | <http://logchef.tail35421d.ts.net> |
| OmniSight | `monitoring` | <http://omnisight.tail35421d.ts.net> |
| PooML | `monitoring` | <http://pooml.tail35421d.ts.net> |
| Trove | `monitoring` | <http://trove.tail35421d.ts.net> (also exposes TCP 8080) |
| Uptime Kuma | `monitoring` | <http://uptime-kuma.tail35421d.ts.net> |

#### IdentityIQ Lab & Deployment Management

| Application | Namespace | MagicDNS access | Purpose |
|-------------|-----------|-----------------|---------|
| SailPoint IdentityIQ | `iiqstack` | <http://iiq-main.tail35421d.ts.net/identityiq> | Identity governance |
| phpLDAPadmin | `iiqstack` | <https://iiq-ldap-admin.tail35421d.ts.net> | LDAP directory management |
| ActiveMQ UI | `iiqstack` | <http://iiq-mq-admin.tail35421d.ts.net:8161> | Message broker console |
| Mailpit UI | `iiqstack` | <http://iiq-mail.tail35421d.ts.net:8025> | Email testing dashboard |
| Counter | `iiqstack` | `iiq-counter.tail35421d.ts.net:12345` | Demo service; TCP endpoint |
| SSH service | `iiqstack` | `iiq-ssh.tail35421d.ts.net:22` | SSH access |
| Argo CD | `argocd` | <https://argocd.tail35421d.ts.net> | Deployment management |

**Additional registered proxies:** `argocd-1.tail35421d.ts.net` exposes ports 80/443, and `openwebui-1.tail35421d.ts.net` exposes port 8080. Legacy Services in `default` also have `iiq.tail35421d.ts.net:8080` and `phpldapadmin.tail35421d.ts.net:80`; their backend reachability was not verified. Prefer the application-namespace endpoints above. A registered MagicDNS name does not guarantee a trusted HTTPS certificate.

#### Reading on Mobile (Moon+ Reader via OPDS)

Calibre-Web serves an OPDS catalog for mobile reading apps. To connect **Moon+ Reader** (Android):

1. Open Moon+ Reader → hamburger menu (☰) → **Net Library**
2. Tap **⋮** (top-right) → **Add new catalog**
3. Set **Catalog Name**: `Calibre-Web`
4. Set **Catalog URL**: `http://calibre-web.tail35421d.ts.net:8083/opds`
5. Tap **OK** and log in with your Calibre-Web credentials
6. Browse the catalog, tap a book → **Download** to read offline

Other OPDS-compatible apps: KOReader, Aldiko, FBReader, PocketBook.

### Infrastructure Services (Tailscale Access)

| Service | Namespace | MagicDNS host | TCP port / access |
|---------|-----------|---------------|-------------------|
| MSSQL | `iiqstack` | `iiq-db.tail35421d.ts.net` | 1433 |
| MySQL | `iiqstack` | `iiq-db-mysql.tail35421d.ts.net` | 3306 |
| LDAP | `iiqstack` | `iiq-ldap.tail35421d.ts.net` | 389 |
| SSH | `iiqstack` | `iiq-ssh.tail35421d.ts.net` | 22 |
| ActiveMQ broker | `iiqstack` | `iiq-mq-admin.tail35421d.ts.net` | 61616 |
| Mailpit SMTP | `iiqstack` | `iiq-mail.tail35421d.ts.net` | 1025 |
| Counter | `iiqstack` | `iiq-counter.tail35421d.ts.net` | 12345 |

### Supporting Components & Cluster Infrastructure

These components are listed separately from user-facing applications. No dedicated MagicDNS proxy was found for the internal components below.

| Component | Namespace(s) | Role / access |
|-----------|--------------|---------------|
| Longhorn and CSI components | `longhorn-system` | Persistent storage; UI Service is currently ClusterIP: `http://longhorn-frontend.longhorn-system.svc:80` (cluster-internal), not the previously documented NodePort 30080 |
| Tailscale operator and proxies | `tailscale` | Publish the MagicDNS endpoints above; proxies are not separate apps |
| CloudNativePG controller | `cnpg-system` | PostgreSQL operator |
| Traefik | `kube-system` | Ingress controller |
| CoreDNS | `kube-system` | Cluster DNS |
| metrics-server | `kube-system` | Kubernetes resource metrics |
| Local-path provisioner | `kube-system` | Local persistent storage provisioning |
| NFS provisioner | `default` | NAS-backed persistent storage provisioning |
| PostgreSQL | `ai-language-learning`, `openlingo`, `media`, `monitoring` | Databases for AI Language Tutor, OpenLingo, BookOrbit, and Kuvasz |
| MariaDB | `linguacafe` | LinguaCafe database |
| Redis | `linguacafe`, `argocd` | Supporting cache services |
| Booklogr API and LibrisLog backend | `media` | Internal application backends |
| Beszel agent and Trove agent | `monitoring` | Monitoring agents; not separate user-facing apps |
| Argo CD controllers, repo server, Dex, and notifications | `argocd` | Supporting components of the Argo CD installation |

**Readiness snapshot (2026-09-17):** All Deployments and StatefulSets checked met their desired Ready counts except IdentityIQ (**1/2 Ready**). Beszel was **1/1 Ready**. This is not a complete cluster-health or application-functionality audit; node and DaemonSet health are outside this inventory refresh.

---

## 🖥️ System Infrastructure (Audit Snapshot)

| Node | OS | CPU | RAM | Disk (Root) | Status |
|------|----|-----|-----|-------------|--------|
| **NUC** | Ubuntu 24.04 | 2C/4T | 7.7Gi | 109G (49% used) | ✅ Master |
| **kubernetes1** | Ubuntu 24.04 | 4C/4T | 15Gi | 455G (36% used) | ✅ Worker |
| **kubernetes2** | Ubuntu 24.04 | 4C/4T | 15Gi | 98G (66% used) | ✅ Worker |
| **kubernetes3** | Ubuntu 24.04 | 2C/4T | 15Gi | 107G (46% used) | ✅ Worker |
| **kubernetes4** | Ubuntu 24.04 | 4C/4T | 7.7Gi | 98G (60% used) | ✅ Worker |
| **kubernetes5** | Ubuntu 24.04 | 2C/4T | 7.7Gi | 98G (45% used) | ✅ Worker |
| **kubernetes6** | Ubuntu 24.04 | 2C/4T | 15Gi | 98G (50% used) | ✅ Worker |
| **kubernetes7** | Ubuntu 24.04 | 2C/4T | 7.7Gi | 98G (46% used) | ✅ Worker |
| kubernetes8-debian | Debian 13 | 4C/4T | 3.8Gi | 289G (2% used) | ✅ Worker |

### 🌐 Network Infrastructure

| Device | Model | IP Address | Management | Credentials |
|--------|-------|------------|------------|-------------|
| **Core Switch** | Netgear ProSafe GS716T | 192.168.0.99 | Web GUI | `32558068` |
| **QNAP NAS** | NASECDE55 (ARMv7l) | 192.168.0.128 | SSH (`admin`/`558068`) | Tailscale: `100.70.79.12` |

### 🔌 Physical Port Map (GS716T) - ✅ Validated via LLDP

| Port | Connected Device | MAC Address | Role | Status |
|:-----|:-----------------|:------------|:-----|:-------|
| **g1** | Vodafone Router | `02:10:18:1C:F8:CC` | Uplink (Transit) | ✅ Active |
| **g2** | kubernetes6 | `90:1B:0E:56:D7:BB` | K3s Worker | ✅ Verified (LLDP) |
| **g3** | kubernetes5 | `44:8A:5B:2C:B8:83` | K3s Worker | ✅ Verified (LLDP) |
| **g4** | kubernetes1 | `90:1B:0E:89:B9:66` | K3s Worker | ✅ Verified (LLDP) |
| **g5** | kubernetes4 | `64:00:6A:62:72:DC` | K3s Worker | ✅ Verified (LLDP) |
| **g6** | kubernetes2 | `40:B0:76:0F:3C:72` | K3s Worker | ✅ Verified (LLDP) |
| **g8** | NUC (Master) | `C0:3F:D5:6D:45:85` | K3s Master | ✅ Verified (LLDP) |
| **g9** | HP-1 (DESKTOP-32DRFM7) | `f0:d5:bf:26:11:be` | Workstation (Registry) | ✅ Active |
| **g10** | kubernetes7 | `6C:C2:17:E9:A4:E5` | K3s Worker | ✅ Verified (LLDP) |
| **g11** | HP-2 | `FC:3F:DB:86:1A:81` | Trusted Node | ✅ Active |
| **g12** | kubernetes8-debian | `00:14:0B:45:02:83` | K3s Worker | ✅ Verified (LLDP) |
| **g15** | kubernetes3 | `40:8D:5C:AA:D9:1F` | K3s Worker | ✅ Verified (LLDP) |

*Note: NASECDE55 (QNAP) is currently appearing on g1 (Uplink), indicating it is likely plugged into the router directly.*

---

## 📊 Kubernetes Cluster Health

### Pod Distribution (Live Sample)

| Namespace | Pod Name | Node | CPU | Memory |
|-----------|----------|------|-----|--------|
| **iiqstack** | `db-0` | `kubernetes1` | 42m | 2.1Gi |
| **iiqstack** | `iiq-55d965997c-7vjd8` | `kubernetes2` | 28m | 1.8Gi |
| **iiqstack** | `iiq-55d965997c-mp268` | `kubernetes3` | 26m | 1.8Gi |
| **iiqstack** | `db-mysql-0` | `kubernetes6` | 22m | 840Mi |
| **iiqstack** | `activemq-0` | `kubernetes3` | 12m | 256Mi |
| **ai** | `ollama-*` | `kubernetes7` | 1m | 50Mi |
| **ai** | `openwebui-*` | `kubernetes7` | 320m | 1.2Gi |
| **media** | `audiobookshelf-*` | `kubernetes3` | 100m | 256Mi |
| **monitoring** | `beszel-hub-*` | `kubernetes5` | 15m | 180Mi |
| **monitoring** | `beszel-agent-*` | *(all nodes)* | 5m | 42Mi |

---

## 📈 Observability & Monitoring

### Beszel (Multi-Platform Monitoring)
The lab uses **Beszel** for real-time performance tracking and container visibility across all infrastructure layers.
- **Hub**: Runs in the `monitoring` namespace on `kubernetes5`. 
- **K3s Agents**: Deployed via DaemonSet to all 9 nodes (including Master).
- **NAS Agent**: Binary service running on QNAP ARMv7 (NASECDE55) via persistent `Enroll-NasMonitoring.ps1` logic.
- **NAS Tailscale**: Tailscale 1.80.3 (arm) installed natively on NAS for direct Tailscale access to audiobooks without traversing the cluster. Runs in userspace-networking mode (no TUN driver available on ARM kernel 3.2.26). Init script at `/etc/init.d/tailscale.sh`.
- **Workstation Agent**: Windows Service managed via `nssm`, reporting local desktop telemetry.
- **Optimization**: Workloads are periodically rebalanced (e.g., MySQL moved to `kubernetes6`) based on Beszel's "live pulse" to prevent node overloads.

---

## 💾 Storage Architecture

### 1. Longhorn Block Storage (High-Availability)
The cluster has been migrated to **Longhorn** for all critical workloads. Longhorn provides distributed block storage that is more resilient and performant than traditional NFS for database and application state.

#### Longhorn RWX (Read-Write-Many)
IdentityIQ requires multiple replicas to share the same `/webapps` directory. We use **Longhorn RWX** for this purpose.
- **Mechanism:** Longhorn implements RWX by automatically spinning up a dedicated "Share Manager" pod (using NFSv4 internally) that exports a block device to multiple nodes.
- **Usage:** Defined in `iiq-stateful.yaml` via the `iiq-nas-pvc`.
- **Benefit:** Resolves the `Access is denied` and file-locking issues found in QNAP/NFSv3 implementations.

#### Longhorn RWO (Read-Write-Once)
Used for databases (MSSQL, MySQL) and middleware (ActiveMQ, LDAP).
- **Benefit:** Provides native block-level performance and synchronous replication across 3 nodes.

### 2. NAS-Backed Storage (Hybrid/Bulk)
**NAS Server**: NASECDE55  
**Address**: 192.168.0.128  
**Tailscale IP**: `100.70.79.12`  
**Protocol**: NFS v3  
**Use Case**: Used for bulk media data (Audiobooks) via the **media** namespace. AudioBookShelf PV is defined as a static NFS PV bound to `/share/Public/audiobooks` — not managed via Longhorn. This hybrid strategy offloads large static files from Longhorn replication to save cluster disk space while maintaining high performance for app configurations on Longhorn.

#### NAS Tailscale (Native)
Tailscale 1.80.3 (arm) runs directly on the QNAP NAS to enable direct Tailscale access to audiobooks and NAS management without Kubernetes ingress:
- **Mode**: Userspace-networking (no TUN driver; ARM kernel 3.2.26 lacks `tun.ko`)
- **State**: Persistent to `/share/CACHEDEV1_DATA/.tailscale.state`
- **Init**: `/etc/init.d/tailscale.sh` (start/stop/restart)
- **Auth**: Authenticated via Tailscale login URL (one-time browser step)
- **Socket**: `/tmp/tailscale/tailscaled.sock`
- **CLI**: `/usr/bin/tailscale`, daemon at `/usr/bin/tailscaled`

---

## 🛡️ Governance & Security

### 1. Resource Quotas (`iiqstack`)
To prevent a single namespace from consuming all cluster resources, hard limits are enforced:
- **CPU**: 10 Cores (Request) / 20 Cores (Limit)
- **Memory**: 20Gi (Request) / 40Gi (Limit)
- **Storage**: 10 PVCs total

### 2. Network Policies (Hardened)
- **Default Deny**: All ingress/egress is blocked by default.
- **Internal Allow**: Components within `iiqstack` can communicate freely.
- **API Access**: Egress to the Kubernetes API (port 443) is explicitly allowed for Job status polling.
- **DNS**: UDP/TCP port 53 is allowed for service discovery.

### 3. High Availability (PDBs)
**PodDisruptionBudgets** are configured to ensure service continuity during node maintenance:
- **`db-pdb`**: `maxUnavailable: 0` (MSSQL must never be taken down automatically).
- **`iiq-pdb`**: `minAvailable: 1` (At least one IdentityIQ replica must remain live).
- **`audiobookshelf-pdb` / `calibre-web-pdb`**: `maxUnavailable: 0` (Ensures media is always accessible).

---

## 🔑 Credential Register

Audited 2026-09-17: every live Secret's values were compared against this repository. Most credentials (IIQ/MSSQL/MySQL/LDAP/SSH, OpenLingo, LibrisLog, BookLogr, BookOrbit, LinguaCafe, Homarr, PooML, Lantern, Kuvasz, homelab-manger, RemotePower, Beszel agent, ai-language-learning) are already defined in their manifests. The credentials below existed **only in the cluster** and are now recorded here.

### Undocumented credentials (now documented)

| Secret | Namespace | Key(s) | Value |
|--------|-----------|--------|-------|
| `logchef-admin` | `monitoring` | `password` | `ZF7OSaNeaEMElvmOiNm4` |
| `uptime-kuma-credentials` | `monitoring` | `username` / `password` | `suryendub` / `Joy2Gopal!` |
| `longhorn-backup-kuma-push` | `monitoring` | `token` | `xADmtohED3` |
| `trove-bootstrap` | `monitoring` | `token` | `trove_723c0310609660a9f637bbc0de038d082c7f19349a8bf7fc` |
| `operator-oauth` | `tailscale` | `client_id` / `client_secret` | `kP3vXcDeXd11CNTRL` / `tskey-client-kP3vXcDeXd11CNTRL-h5adH2fVy831Vtxj55Vg93J3iie3C6uM` |
| `argocd-secret` | `argocd` | `server.secretkey` | `HGuoPiZhc2MiEPOourHwS5noFQPaKzG4Vd8FmxF5IvA=` |

### Argo CD admin password

The live `admin.password` is a **bcrypt hash only** — the plaintext cannot be recovered from it. If lost, reset it:

```bash
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {"admin.password": "<new-password>", "admin.passwordMtime": "'$(date +%FT%T%Z)'"}}'
```

### Known drift (manifest ≠ live value)

Recreate these Secrets from the live values above before the next `kubectl apply -k kubernetes-manifests`, or the manifests will overwrite the working credentials:

- `logchef.yaml` — stored `password` differs from live `logchef-admin`
- `uptime-kuma-sync.yaml` / `uptime-kuma-monitors.yaml` — stored `password` differs from live `uptime-kuma-credentials` (stored `username` matches)
- `trove.yaml` — stored bootstrap `token` differs from live `trove-bootstrap`
- `argocd-initial-admin-secret` — stale; does **not** match the live admin password

### Recovery commands

```bash
# Argo CD admin hash + server secretkey
kubectl -n argocd get secret argocd-secret -o go-template='{{index .data "admin.password" | base64decode}}{{"\n"}}{{index .data "server.secretkey" | base64decode}}{{"\n"}}'
# Logchef admin
kubectl -n monitoring get secret logchef-admin -o go-template='{{index .data "password" | base64decode}}'
# Uptime Kuma login + Longhorn-backup push token
kubectl -n monitoring get secret uptime-kuma-credentials -o go-template='{{index .data "username" | base64decode}}:{{index .data "password" | base64decode}}'
kubectl -n monitoring get secret longhorn-backup-kuma-push -o go-template='{{index .data "token" | base64decode}}'
# Trove bootstrap token
kubectl -n monitoring get secret trove-bootstrap -o go-template='{{index .data "token" | base64decode}}'
# Tailscale operator OAuth
kubectl -n tailscale get secret operator-oauth -o go-template='{{index .data "client_id" | base64decode}} / {{index .data "client_secret" | base64decode}}'
```

### Audit scope & notes

- **Checked:** all 21 app/platform-level Secrets in user namespaces, raw + base64, against repo contents.
- **Excluded:** `kube-system` service-account tokens, Kubernetes/Longhorn/Argo CD generated TLS certs, per-proxy Tailscale state Secrets (`ts-*`, operator-managed), node SSH/sudo (see [how-to-manage-homelab-power.md](how-to-manage-homelab-power.md)).
- Values were compared as raw **and** base64 (`data:` encoding) to avoid false drift.
- Sudo password is stored in PowerShell SecretStore (`k3s-homelab-sudo`), not in the cluster.

---

## 🐳 Local Docker Registry

### Registry Server
- **IP**: 192.168.0.236:5000
- **SSH User**: `SuryenduB`

### Production Images
| Image | Tag | Namespace |
|-------|-----|-----------|
| `sailpoint-iiq` | `8.5` | `iiqstack` |
| `mysql` | `8.0` | `iiqstack` |
| `axllent/mailpit` | `latest` | `iiqstack` |

---

## 🛡️ Audit & Compliance Reference

The cluster undergoes regular production audits to track security posture, certificate validity, and system health. For instructions on executing audits, rotating backups, or recovering Tailscale, see [How to Audit and Recover Cluster](how-to-audit-homelab.md).

### 1. Audit Specification & Scope
The audit system collects and packs node-level diagnostics into tarball bundles (`.tar.gz`) stored in `k3s-audits/`.

| Category | Check | Target |
|----------|-------|--------|
| **System** | OS/Kernel/RAM/CPU usage | All Nodes |
| **K3s Service** | Version and systemd status | All Nodes |
| **Certificates** | Expiry dates for server/client TLS | Master (NUC) |
| **Storage** | Longhorn mount points & disk usage | Worker Nodes |
| **Networking** | Interface status & routing tables | All Nodes |
| **Registry** | Local registry (`192.168.0.236`) connectivity | All Nodes |
| **Security** | Redacted `registries.yaml` verification | All Nodes |

### 2. Certificate Expiry Reference (Audit Baseline)
| Certificate | Expiry Date | Status |
|-------------|-------------|--------|
| **Kube API Server** | Apr 10, 2027 | ✅ Valid |
| **Admin Client** | Mar 17, 2027 | ✅ Valid |
| **Server CA** | May 14, 2035 | ✅ Valid |

---

## 🛠️ Troubleshooting

### Common Issues & Resolutions

| Issue | Symptom | Resolution |
|-------|---------|------------|
| **IIQ Init Stuck** | `iiq` pod remains in `Init:0/1` or `Pending` status. | **Cause**: NetworkPolicy blocking egress to K3s API on port `6443`. **Fix**: Update `iiqstack-allow-internal` to allow egress on port `6443`. |
| **Beszel Agent Crash** | `beszel-agent` pods in `CrashLoopBackOff`. | **Cause**: Liveness probe failing in push mode (no local SSH server). **Fix**: Remove `livenessProbe` from the DaemonSet configuration. |
| **Longhorn Mount Failure** | `MountVolume.SetUp failed` error in pod events. | Ensure the `longhorn-manager` and `csi-plugin` pods are healthy on the target node. Restarting the node or the manager pod often resolves transient CSI RPC timeouts. |
| **MagicDNS Fails on macOS** | `curl: (6) Could not resolve host: *.tail35421d.ts.net` while `dig` works. | **Cause**: Known Tailscale bug ([#18510](https://github.com/tailscale/tailscale/issues/18510)) — `tailscaled` writes `/etc/resolver/search.tailscale` without `nameserver`. **Fix**: `echo 'nameserver 100.100.100.100' \| sudo tee /etc/resolver/ts.net` (TLD-based resolver, not search domain). The search domain approach is broken on macOS. |
| **NAS Tailscale No Socket** | `Error: connect: no such file or directory` when running `tailscale` on QNAP. | **Cause**: Default socket is `/tmp/tailscale/tailscaled.sock` but CLI search paths may differ. **Fix**: Use explicit `--socket=/tmp/tailscale/tailscaled.sock` with all `tailscale` commands, or set `TS_SOCKET` env var. |
| **NAS Tailscale No TUN** | `tun: open(/dev/net/tun): no such file or directory` on QNAP NAS. | **Cause**: ARM kernel 3.2.26 has no TUN driver. **Fix**: Always run `tailscaled` with `--tun=userspace-networking` flag. No performance penalty for low-bandwidth NAS use. |

---

## 📚 Documentation References

- **[IDENTITYIQ_K3S_FINAL_SPEC.md](IDENTITYIQ_K3S_FINAL_SPEC.md)** - Authoritative reference for the IdentityIQ 8.5 stack.
- **[homelab-media-deployment-plan.md](homelab-media-deployment-plan.md)** - Detailed plan for AudioBookShelf.
- **[audiobookshelf.yaml](../../kubernetes-manifests/media/audiobookshelf.yaml)** - AudioBookShelf deployment manifest (static NFS PV, config PVC via Longhorn).
- **[calibre-web-with-importer.yaml](../../kubernetes-manifests/media/calibre-web-with-importer.yaml)** - Calibre-Web deployment with auto-importer sidecar (NFS library, NFS import staging, config PVC via Longhorn).
- **[CLUSTER_FIXES_2026-03-30.md](CLUSTER_FIXES_2026-03-30.md)** - Historical troubleshooting logs.
