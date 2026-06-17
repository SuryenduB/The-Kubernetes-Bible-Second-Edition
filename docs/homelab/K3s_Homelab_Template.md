# 🏠 K3s Homelab - Complete Kubernetes Environment

**Last Updated**: 2026-06-17 | **Status**: ✅ Production Ready | **Version**: K3s v1.34.6+k3s1

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

All services are accessible via Tailscale MagicDNS at `*.tail35421d.ts.net`.

| Application | MagicDNS URL | Internal LAN URL | Description |
|-------------|-------------|------------------|-------------|
| **IdentityIQ** | [http://iiq.tail35421d.ts.net:8080/identityiq](http://iiq.tail35421d.ts.net:8080/identityiq) | http://192.168.0.21/identityiq | SailPoint Identity Governance |
| **AudioBookShelf**| [http://audiobookshelf.tail35421d.ts.net](http://audiobookshelf.tail35421d.ts.net) | http://audiobookshelf.media.svc | Media Server (Audiobooks/Podcasts) |
| **Calibre-Web** | [http://calibre-web.tail35421d.ts.net:8083](http://calibre-web.tail35421d.ts.net:8083) | http://calibre-web.media.svc:8083 | Ebook Management |
| **OpenWebUI** | [http://openwebui.tail35421d.ts.net:8080](http://openwebui.tail35421d.ts.net:8080) | http://openwebui.local | AI Chat Interface |
| **phpLDAPadmin** | [http://phpldapadmin.tail35421d.ts.net](http://phpldapadmin.tail35421d.ts.net) | http://192.168.0.21:30081 | LDAP Directory Manager |
| **ActiveMQ UI** | [http://iiq-mq-admin.tail35421d.ts.net:8161](http://iiq-mq-admin.tail35421d.ts.net:8161) | http://192.168.0.21:30082 | Middleware Console |
| **Mailpit UI** | [http://iiq-mail.tail35421d.ts.net:8025](http://iiq-mail.tail35421d.ts.net:8025) | http://192.168.0.21:30083 | Email Testing Dashboard |
| **ArgoCD** | [https://argocd.tail35421d.ts.net](https://argocd.tail35421d.ts.net) | https://argocd.example.com | GitOps CD Platform |
| **Beszel Hub** | [http://beszel.tail35421d.ts.net](http://beszel.tail35421d.ts.net) | http://beszel-hub.monitoring.svc | Lightweight Cluster Monitoring |
| **Homepage** | [http://homepage-homepage.tail35421d.ts.net](http://homepage-homepage.tail35421d.ts.net) | http://homepage.homepage.svc | Homelab Dashboard |
| **Longhorn UI** | [http://nuc:30080](http://nuc:30080) | http://192.168.0.21:30080 | Storage Management |
| **AI-Language-Learning**| [http://lang-tutor.tail35421d.ts.net](http://lang-tutor.tail35421d.ts.net) | http://ai-lang-backend.ai-language-learning.svc | Custom AI Language Tutor |
| **OpenLingo** | [http://openlingo.tail35421d.ts.net](http://openlingo.tail35421d.ts.net) | http://openlingo.openlingo.svc | Structured Language Platform |
| **LinguaCafe** | [http://linguacafe.tail35421d.ts.net](http://linguacafe.tail35421d.ts.net) | http://linguacafe.linguacafe.svc | Self-hosted Language Reading App |

### Infrastructure Services (Tailscale Access)

| Service | Tailscale Host | Port | Type |
|---------|----------------|------|------|
| **MSSQL** | `iiq-db` | 1433 | Primary DB |
| **MySQL** | `iiq-db-mysql` | 3306 | Plugin DB |
| **LDAP** | `iiq-ldap` | 389 | Directory |
| **SSH Jump** | `iiq-ssh` | 22 | Terminal Access |
| **Beszel Agent**| N/A (Internal) | 45876 | Node Monitoring (DaemonSet) |
| **Counter** | `iiq-counter` | 12345 | Demo Service |

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
| **media** | `calibre-web-*` | `kubernetes4` | 100m | 256Mi |
| **monitoring** | `beszel-hub-*` | `kubernetes5` | 15m | 180Mi |
| **monitoring** | `beszel-agent-*` | *(all nodes)* | 5m | 42Mi |

---

## 📈 Observability & Monitoring

### Beszel (Multi-Platform Monitoring)
The lab uses **Beszel** for real-time performance tracking and container visibility across all infrastructure layers.
- **Hub**: Runs in the `monitoring` namespace on `kubernetes5`. 
- **K3s Agents**: Deployed via DaemonSet to all 9 nodes (including Master).
- **NAS Agent**: Binary service running on QNAP ARMv7 (NASECDE55) via persistent `Enroll-NasMonitoring.ps1` logic.
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
**Protocol**: NFS v3  
**Use Case**: Used for bulk media data (Audiobooks, Ebooks) via the **media** namespace. This hybrid strategy offloads large static files from Longhorn replication to save cluster disk space while maintaining high performance for app configurations on Longhorn.

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

---

## 📚 Documentation References

- **[IDENTITYIQ_K3S_FINAL_SPEC.md](IDENTITYIQ_K3S_FINAL_SPEC.md)** - Authoritative reference for the IdentityIQ 8.5 stack.
- **[homelab-media-deployment-plan.md](homelab-media-deployment-plan.md)** - Detailed plan for AudioBookShelf and Calibre-Web.
- **[CLUSTER_FIXES_2026-03-30.md](CLUSTER_FIXES_2026-03-30.md)** - Historical troubleshooting logs.
