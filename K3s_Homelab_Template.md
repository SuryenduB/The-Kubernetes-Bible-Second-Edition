# 🏠 K3s Homelab - Complete Kubernetes Environment

**Last Updated**: 2026-04-05 | **Status**: ✅ Production Ready | **Version**: K3s v1.34.5+k3s1

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Cluster Overview](#cluster-overview)
3. [Application Access](#application-access)
4. [System Infrastructure](#system-infrastructure)
5. [Kubernetes Cluster Health](#kubernetes-cluster-health)
6. [Storage Architecture](#storage-architecture)
7. [Governance & Security](#governance--security)
8. [Installed Components](#installed-components)
9. [Deployment Manifests](#deployment-manifests)
10. [Operations & Maintenance](#operations--maintenance)
11. [Troubleshooting](#troubleshooting)
12. [Documentation References](#documentation-references)

---

## 🚀 Quick Start

### Start the Homelab Cluster
```powershell
# Power on all nodes and wait for cluster convergence
Start-K3sHomelab

# Verify cluster health
kubectl get nodes
kubectl get pods -A
```

### Stop the Homelab Cluster
```powershell
# Gracefully shut down cluster (waits for pod termination)
Stop-K3sHomelab
```

---

## 🗺️ Cluster Overview

### Architecture Diagram
![Homelab Architecture](homelab_architecture.png)

### Cluster Configuration
- **Kubernetes Version**: K3s v1.34.5+k3s1 (control plane: nuc)
- **Nodes**: 8 total (1 control-plane + 7 workers)
- **Status**: ✅ All Ready
- **Network**: Flat LAN (192.168.0.0/24)
- **Storage**: Longhorn (Production) + QNAP NAS (Legacy/Backup)
- **CNI**: Flannel (default K3s)
- **Ingress**: Traefik (automatic with K3s)

---

## 🌐 Application Access & URLs

### Web Applications (Tailscale / LAN)

| Application | Tailscale URL | Internal LAN URL | Description |
|-------------|---------------|------------------|-------------|
| **IdentityIQ** | [http://iiq-main/identityiq](http://iiq-main/identityiq) | http://192.168.0.21/identityiq | SailPoint Identity Governance |
| **OpenWebUI** | [http://openwebui:8080](http://openwebui:8080) | http://openwebui.local | AI Chat Interface |
| **phpLDAPadmin** | [http://iiq-ldap-admin](http://iiq-ldap-admin) | http://192.168.0.21:30081 | LDAP Directory Manager |
| **ActiveMQ UI** | [http://iiq-mq-admin:8161](http://iiq-mq-admin:8161) | http://192.168.0.21:30082 | Middleware Console |
| **Mailpit UI** | [http://iiq-mail:8025](http://iiq-mail:8025) | http://192.168.0.21:30083 | Email Testing Dashboard |
| **ArgoCD** | [https://argocd](https://argocd) | https://argocd.example.com | GitOps CD Platform |
| **Longhorn UI** | [http://nuc:30080](http://nuc:30080) | http://192.168.0.21:30080 | Storage Management |

### Infrastructure Services (Tailscale Access)

| Service | Tailscale Host | Port | Type |
|---------|----------------|------|------|
| **MSSQL** | `iiq-db` | 1433 | Primary DB |
| **MySQL** | `iiq-db-mysql` | 3306 | Plugin DB |
| **LDAP** | `iiq-ldap` | 389 | Directory |
| **SSH Jump** | `iiq-ssh` | 22 | Terminal Access |
| **Counter** | `iiq-counter` | 12345 | Demo Service |

---

## 📊 Kubernetes Cluster Health

### Pod Distribution (Live Sample)

| Namespace | Pod Name | Node | CPU | Memory |
|-----------|----------|------|-----|--------|
| **iiqstack** | `db-0` | `kubernetes1` | 42m | 2.1Gi |
| **iiqstack** | `iiq-55d965997c-7vjd8` | `kubernetes2` | 28m | 1.8Gi |
| **iiqstack** | `iiq-55d965997c-mp268` | `kubernetes3` | 26m | 1.8Gi |
| **iiqstack** | `db-mysql-0` | `kubernetes7` | 18m | 450Mi |
| **iiqstack** | `activemq-0` | `kubernetes3` | 12m | 256Mi |
| **ai** | `ollama-*` | `kubernetes7` | 1m | 50Mi |
| **ai** | `openwebui-*` | `kubernetes7` | 320m | 1.2Gi |

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

### 2. NAS-Backed Storage (Legacy/Bulk)
**NAS Server**: NASECDE55  
**Address**: 192.168.0.128  
**Protocol**: NFS v3  
**Use Case**: Primarily used for cluster backups and bulk data that doesn't require high IOPS.

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

## 📚 Documentation References

- **[IDENTITYIQ_K3S_FINAL_SPEC.md](IDENTITYIQ_K3S_FINAL_SPEC.md)** - Authoritative reference for the IdentityIQ 8.5 stack.
- **[CLUSTER_FIXES_2026-03-30.md](CLUSTER_FIXES_2026-03-30.md)** - Historical troubleshooting logs.
