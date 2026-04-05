# 🏠 K3s Homelab - Complete Kubernetes Environment

**Last Updated**: 2026-04-03 | **Status**: ✅ Production Ready | **Version**: K3s v1.34.5+k3s1

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Cluster Overview](#cluster-overview)
3. [Application Access](#application-access)
4. [System Infrastructure](#system-infrastructure)
5. [Kubernetes Cluster Health](#kubernetes-cluster-health)
6. [Storage Architecture](#storage-architecture)
7. [Installed Components](#installed-components)
8. [Deployment Manifests](#deployment-manifests)
9. [Operations & Maintenance](#operations--maintenance)
10. [Troubleshooting](#troubleshooting)
11. [Documentation References](#documentation-references)

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

### Check Cluster Status
```bash
# View cluster info
kubectl cluster-info

# Check node status
kubectl get nodes -o wide

# View all running pods
kubectl get pods -A -o wide

# Check resource usage
kubectl top nodes
kubectl top pods -A
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
- **Storage**: 100% NAS-backed (NASECDE55)
- **CNI**: Flannel (default K3s)
- **Ingress**: Traefik (automatic with K3s)

---

## 🌐 Application Access & URLs

### Web Applications

| Application | URL | Access | Description | Status |
|-------------|-----|--------|-------------|--------|
| **OpenWebUI** | http://openwebui.local | Internal LAN | AI Chat Interface (Ollama backend) | ✅ Running |
| **IdentityIQ** | http://identityiq.example.com/identityiq | Internal LAN | SailPoint Identity Governance | ✅ Running |
| **phpLDAPadmin** | http://phpldapadmin.example.com | Internal LAN | LDAP Directory Manager | ✅ Running |
| **ArgoCD** | https://argocd.example.com | Internal LAN | GitOps CD Platform | ✅ Running |
| **MailHog** | http://192.168.0.21:30266 | Internal LAN | Email Testing Server | ✅ Running |

### Database Services

| Service | Host | Port | Type | Status |
|---------|------|------|------|--------|
| **MSSQL** | db | 1433 | TCP | ✅ Running |
| **MySQL** | db-mysql | 3306 | TCP | ✅ Running |
| **LDAP** | ldap | 389 | TCP | ✅ Running |

### Internal Services (Cluster-only)

| Service | Port | Protocol | Status |
|---------|------|----------|--------|
| **Ollama API** | 11434 | HTTP | ✅ Running |
| **Counter** | 8080 | HTTP | ✅ Running |
| **ActiveMQ** | 8161 | HTTP | ✅ Running |

### DNS Configuration

To access `.local` and `.example.com` domains from your browser, add these entries to your **hosts file**:

**Windows** (`C:\Windows\System32\drivers\etc\hosts`):
```
192.168.0.21  openwebui.local
192.168.0.21  identityiq.example.com
192.168.0.21  phpldapadmin.example.com
192.168.0.21  argocd.example.com
```

**Linux/macOS** (`/etc/hosts`):
```
192.168.0.21  openwebui.local identityiq.example.com phpldapadmin.example.com argocd.example.com
```

---

## 🖥️ System Infrastructure

### Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Network                             │
│                  192.168.0.0/24                              │
└─────────────────────────────────────────────────────────────┘
  │        │        │        │        │        │        │        │        │
  ▼        ▼        ▼        ▼        ▼        ▼        ▼        ▼        ▼
┌───┐  ┌───┐  ┌───┐  ┌───┐  ┌───┐  ┌───┐  ┌───┐  ┌───┐  ┌──────┐
│NUC│  │ k1│  │ k2│  │ k3│  │ k4│  │ k5│  │ k6│  │ k7│  │ REG  │
└───┘  └───┘  └───┘  └───┘  └───┘  └───┘  └───┘  └───┘  └──────┘
 CP     W      W      W      W      W      W      W     Registry
               └────────────────────────────────────┘
                    Kubernetes Workload Pool
                     (NFS Storage Access)
                              │
                              ▼
                    ┌──────────────────┐
                    │  NASECDE55 (NAS) │
                    │  192.168.0.128   │
                    │   423GB NFS      │
                    └──────────────────┘
```

### Node Specifications

| Hostname | IP | Type | Role | CPU Model | Cores | Threads | Memory | Storage | Status |
|----------|----|----|------|-----------|-------|---------|--------|---------|--------|
| **nuc** | 192.168.0.21 | 🖥️ Desktop | control-plane, master | Intel Celeron 847E | 2 | 2 | 16GB | NFS | ✅ Ready |
| **kubernetes1** | 192.168.0.19 | 🖥️ Desktop | worker | Intel i5-4590T | 4 | 4 | 16GB | NFS | ✅ Ready |
| **kubernetes2** | 192.168.0.20 | 🖥️ Desktop | worker | Intel i3-8100 | 4 | 4 | 16GB | NFS | ✅ Ready |
| **kubernetes3** | 192.168.0.22 | 💻 Laptop | worker | Intel i3-6100U | 2 | 4 | 8GB | NFS | ✅ Ready |
| **kubernetes4** | 192.168.0.23 | 🖥️ Desktop | worker | Intel i5-4590S | 4 | 4 | 16GB | NFS | ✅ Ready |
| **kubernetes5** | 192.168.0.24 | 🖥️ Desktop | worker | Intel i3-4130 | 2 | 4 | 16GB | NFS | ✅ Ready |
| **kubernetes6** | 192.168.0.25 | 🖥️ Desktop | worker | Intel i3-4350T | 2 | 4 | 8GB | NFS | ✅ Ready |
| **kubernetes7** | 192.168.0.27 | 💻 Laptop | worker | Intel i5-4210U | 2 | 4 | 8GB | Local + NFS | ✅ Ready |
| **registry** | 192.168.0.236 | 🖥️ Desktop | Docker Registry | Intel (see note) | - | - | - | Local | ✅ Running |

**Registry Server Details:**
- **OS**: Ubuntu 24.04.1 LTS (Kernel 6.17.0-19-generic)
- **SSH User**: `SuryenduB` (password: `558068`)
- **Registry**: Docker Registry v2 (HTTP, no auth) on port 5000
- **Images**: `sailpoint-docker:latest`, `sailpoint-iiq:latest`
- **Config**: `/etc/rancher/k3s/registries.yaml` on all nodes points here

---

## 📊 Kubernetes Cluster Health

### Real-time Node Status

```
kubectl get nodes -o wide
```

**Expected Output:**
```
NAME          STATUS   ROLES                  VERSION        INTERNAL-IP    
nuc           Ready    control-plane,master   v1.34.5+k3s1   192.168.0.21
kubernetes1   Ready    <none>                 v1.34.5+k3s1   192.168.0.19
kubernetes2   Ready    <none>                 v1.34.5+k3s1   192.168.0.20
kubernetes3   Ready    <none>                 v1.34.5+k3s1   192.168.0.22
kubernetes4   Ready    <none>                 v1.34.5+k3s1   192.168.0.23
kubernetes5   Ready    <none>                 v1.34.5+k3s1   192.168.0.24
kubernetes6   Ready    <none>                 v1.34.5+k3s1   192.168.0.25
kubernetes7   Ready    worker                 v1.34.6+k3s1   192.168.0.27
```

### Pod Distribution

| Namespace | Deployment | Pod Name | Node | CPU | Memory | Status |
|-----------|-----------|----------|------|-----|--------|--------|
| **default** | db | db-7666489568-b22rl | kubernetes1 | 38m | 404Mi | ✅ Running |
| **default** | db-mysql | db-mysql-0 | kubernetes5 | 24m | 449Mi | ✅ Running |
| **default** | iiq | iiq-5d4fff6cbd-hmddf | kubernetes3 | 26m | 946Mi | ✅ Running |
| **default** | counter | counter-* | kubernetes2 | 0m | 3Mi | ✅ Running |
| **default** | ldap | ldap-* | kubernetes6 | 0m | 51Mi | ✅ Running |
| **default** | phpldapadmin | phpldapadmin-* | kubernetes7 | 12m | 39Mi | ✅ Running |
| **ai** | ollama | ollama-7574c454ff-qhcjg | kubernetes6 | 1m | 50Mi | ✅ Running |
| **ai** | openwebui | openwebui-* | kubernetes2 | 362m | 1216Mi | ✅ Running |
| **argocd** | *various* | argocd-* | mixed | 5m avg | 30Mi avg | ✅ Running |
| **kube-system** | *infrastructure* | *various* | mixed | - | - | ✅ Running |

### Resource Usage Summary

| Category | Usage | Status |
|----------|-------|--------|
| **Cluster CPU** | ~1.5 cores / 28 cores available | ✅ 5% |
| **Cluster Memory** | ~8GB / 120GB available | ✅ 7% |
| **Pod Count** | 35 running pods | ✅ Healthy |
| **Node Capacity** | 8/8 nodes available | ✅ Full |

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
**Protocol**: NFS v3 (Enforced via `mountOptions`)  
**Use Case**: Primarily used for cluster backups and bulk data that doesn't require high IOPS.

### 3. Storage Classes

| Storage Class | Provisioner | Access Mode | Best For |
|---------------|-------------|-------------|----------|
| **longhorn** | `driver.longhorn.io` | RWO / RWX | Databases, IIQ App, Production State |
| **nfs-nas** | `nfs-client` | RWX | Backups, Shared Scripts |
| **local-path** | `rancher.io/local-path` | RWO | Ephemeral cache, Single-node tests |

### 4. Persistent Volumes & Claims (IdentityIQ)

| PVC Name | Namespace | Size | Mode | Storage Class | Mount Path |
|----------|-----------|------|------|---------------|------------|
| **iiq-nas-pvc** | `iiqstack` | 10Gi | **RWX** | `longhorn` | `/opt/tomcat/webapps` |
| **mssql-storage** | `iiqstack` | 10Gi | RWO | `longhorn` | `/var/opt/mssql` |
| **mysql-storage** | `iiqstack` | 10Gi | RWO | `longhorn` | `/var/lib/mysql` |

### 5. Storage Maintenance & Monitoring

**Check Longhorn Volume Health:**
```bash
# View all Longhorn volumes
kubectl get volumes.longhorn.io -n longhorn-system

# View RWX Share Managers
kubectl get pods -n longhorn-system -l longhorn.io/component=share-manager
```

**Access Longhorn UI:**
The UI is available via Traefik or port-forward:
```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Open http://localhost:8080
```

**Repair NFS permissions (Legacy only):**
```bash
# SSH to NAS
ssh admin@192.168.0.128
sudo chmod 777 /share/Public/default-mssql-nas-pvc-*
```

---

## 🛠️ Installed Components

### Core Infrastructure (Automatic with K3s)

| Component | Version | Status | Purpose |
|-----------|---------|--------|---------|
| **Traefik** | v2.11+ | ✅ Running | Ingress Controller & Load Balancer |
| **Flannel** | v0.25+ | ✅ Running | Container Network Interface (CNI) |
| **CoreDNS** | v1.11+ | ✅ Running | DNS Service Discovery |
| **kube-proxy** | v1.34.5 | ✅ Running | Network Proxy & Service Routing |
| **Local Path Provisioner** | latest | ✅ Running | Local Storage Provider |
| **Metrics Server** | latest | ✅ Running | Resource Metrics (top/stats) |

### Add-ons (Installed)

| Add-on | Version | Status | Purpose |
|--------|---------|--------|---------|
| **NFS Subdir Provisioner** | latest | ✅ Running | Dynamic NAS Volume Provisioning |
| **CNPG (CloudNative PG)** | v1.27+ | ✅ Running | PostgreSQL Operator (if used) |

### Applications (User-Deployed)

| Application | Namespace | Replicas | Status | Purpose |
|-------------|-----------|----------|--------|---------|
| **OpenWebUI** | ai | 1/1 | ✅ Running | AI Chat Interface |
| **Ollama** | ai | 1/1 | ✅ Running | LLM Runtime |
| **IdentityIQ (IIQ)** | default | 1/1 | ✅ Running | Identity Governance |
| **MSSQL DB** | default | 1/1 | ✅ Running | Database (IIQ backend) |
| **MySQL** | default | 1/1 | ✅ Running | MySQL Database |
| **LDAP** | default | 1/1 | ✅ Running | Directory Service |
| **phpLDAPadmin** | default | 1/1 | ✅ Running | LDAP Management UI |
| **ActiveMQ** | default | 1/1 | ✅ Running | Message Queue |
| **MailHog** | default | 1/1 | ✅ Running | Email Testing |
| **ArgoCD** | argocd | 6/6 | ✅ Running | GitOps CD |

---

## 🐳 Local Docker Registry

### Registry Server

| Property | Value |
|----------|-------|
| **Hostname** | registry |
| **IP** | 192.168.0.236 |
| **OS** | Ubuntu 24.04.1 LTS |
| **SSH Access** | `ssh SuryenduB@192.168.0.236` |
| **Registry URL** | `http://192.168.0.236:5000` |
| **Auth** | None (HTTP, insecure) |

### Stored Images

| Image | Tag | Used By |
|-------|-----|---------|
| `sailpoint-docker` | `latest` | IIQ pods in iiqstack namespace |
| `sailpoint-iiq` | `latest` | Not currently deployed |

### Registry Configuration on K3s Nodes

All 8 nodes have `/etc/rancher/k3s/registries.yaml` configured via the `registry-fixer` DaemonSet:

```yaml
mirrors:
  "192.168.0.236:5000":
    endpoint:
      - "http://192.168.0.236:5000"
```

### Registry Management

```bash
# List all images on registry
curl http://192.168.0.236:5000/v2/_catalog

# List tags for an image
curl http://192.168.0.236:5000/v2/sailpoint-docker/tags/list

# Push a new image to registry
docker tag my-image:latest 192.168.0.236:5000/my-image:latest
docker push 192.168.0.236:5000/my-image:latest

# Delete an image from registry
curl -X DELETE http://192.168.0.236:5000/v2/my-image/manifests/$(curl -s -I http://192.168.0.236:5000/v2/my-image/manifests/latest | grep -i docker-content-digest | awk '{print $2}' | tr -d '\r')
```

### Registry DaemonSet

```bash
# Check registry-fixer status
kubectl get daemonset registry-fixer -n kube-system

# View registry-fixer logs
kubectl logs -n kube-system -l name=registry-fixer --tail=10
```

---

## 📦 Deployment Manifests

### Manifest Location
```
kubernetes-manifests/
├── base/
│   ├── db-mssql-deployment.yaml          # MSSQL Server (NAS-backed)
│   ├── db-mysql-deployment.yaml          # MySQL Server
│   ├── iiq-deployment.yaml               # IdentityIQ (SailPoint)
│   ├── ollama-deployment.yaml            # Ollama LLM Runtime
│   ├── ldap-deployment.yaml              # OpenLDAP Service
│   ├── phpldapadmin-deployment.yaml      # LDAP Admin Interface
│   ├── activemq-deployment.yaml          # ActiveMQ Message Broker
│   ├── mail-deployment.yaml              # MailHog Email Server
│   ├── counter-deployment.yaml           # Counter Demo App
│   ├── loadbalancer-deployment.yaml      # LoadBalancer Service
│   ├── ssh-deployment.yaml               # SSH Jump Pod
│   ├── nfs-provisioner-*.yaml            # NFS Volume Provisioner
│   └── *.yaml                            # Other services
├── k3s-manifest.yaml                     # AudiobookShelf & misc
└── kustomization.yaml                    # Kustomize config
```

### Deploy from Manifests

```bash
# Deploy all base manifests
kubectl apply -k kubernetes-manifests/

# Deploy specific manifest
kubectl apply -f kubernetes-manifests/base/iiq-deployment.yaml

# Roll out new version
kubectl rollout restart deployment iiq -n default
```

### Critical Manifests with Recent Fixes

**Files modified in remediation (2026-03-30):**

- ✏️ **db-mssql-deployment.yaml** - Fixed NFS permissions issue
  - Added security context with fsGroup: 10001
  - Added fix-permissions init container
  - Changed PVC from RWO to RWX with nfs-nas storage class
  - See: CLUSTER_FIXES_2026-03-30.md

- ✏️ **iiq-deployment.yaml** - Fixed startup probe timeout
  - Extended startupProbe failureThreshold to 60 (600s)
  - Added proper timeout settings for Java initialization
  - See: CLUSTER_FIXES_2026-03-30.md

- 📄 **ollama-deployment.yaml** (NEW) - Created proper deployment
  - Full Kubernetes manifest with resource limits
  - Node affinity for disk-intensive workload
  - PVC configuration for model cache
  - See: kubernetes-manifests/base/ollama-deployment.yaml

---

## 🔧 Operations & Maintenance

### Daily Monitoring

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Check resource usage
kubectl top nodes
kubectl top pods -A

# View recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Check for pod issues
kubectl get pods -A --field-selector=status.phase!=Running
```

### Backup & Recovery

**Datastore**: SQLite (K3s default, NOT etcd)
**Backup Location**: NAS `192.168.0.128:/share/Public/backups/k3s/`

#### Triple Protection System

| Type | Schedule | Trigger | Downtime |
|------|----------|---------|----------|
| Scheduled | Daily 2:00 AM UTC | Cron job | ~30 sec |
| Pre-Shutdown | Before reboot/shutdown | systemd service | ~30 sec |
| Manual | On-demand | Command | ~30 sec |

#### What Gets Backed Up

- SQLite database (`/var/lib/rancher/k3s/server/db/state.db`)
- K3s configuration (`/etc/rancher/k3s/`)
- Node token and certificates
- All Kubernetes manifests and resources

**Manual Backup** (run before major changes):
```bash
sudo /usr/local/bin/k3s-backup-to-nas.sh
```

**List Available Backups:**
```bash
sudo /usr/local/bin/k3s-recovery.sh
```

**Restore from Backup:**
```bash
# Restore from specific backup (use date directory name)
sudo /usr/local/bin/k3s-recovery.sh 20260403-140442
```

**Backup Structure on NAS:**
```
NAS:/share/Public/backups/k3s/
├── 20260403-140442/
│   ├── k3s-state.db        # SQLite database (33MB)
│   └── k3s-config.tar.gz   # K3s configuration
└── ... (up to 10 most recent)
```

**Scheduled Backups:**
- Frequency: Daily at 2:00 AM UTC (root crontab)
- Destination: NAS `/share/Public/backups/k3s/`
- Retention: 10 most recent backups (automatic cleanup)

**Pre-Shutdown Service:**
- `k3s-pre-shutdown.service` — runs backup before any reboot/shutdown
- Enabled for: halt.target, reboot.target, shutdown.target

**Backup Logs:**
```bash
tail -f /var/log/k3s-backup.log
```

### Node Maintenance

**Drain node for maintenance:**
```bash
kubectl drain kubernetes1 --ignore-daemonsets --delete-emptydir-data
```

**Uncordon after maintenance:**
```bash
kubectl uncordon kubernetes1
```

**Restart a node:**
```bash
ssh suryendub@192.168.0.19
sudo reboot
# Wait for node to come back and show Ready status
```

### Update K3s

```bash
# Update control plane (nuc)
ssh suryendub@192.168.0.21
curl -sfL https://get.k3s.io | sh -

# Update workers (one at a time)
ssh suryendub@192.168.0.19
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.0.21:6443 \
  K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token) sh -
```

---

## 🐛 Troubleshooting

### Pod Not Starting

**Check pod events:**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Check pod logs:**
```bash
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # If crashed
```

**Common Issues:**
- `ImagePullBackOff` - Image not found or registry unreachable
- `CrashLoopBackOff` - Application crashes on startup
- `Pending` - No node with sufficient resources
- `NotReady` - Health probe failing

### NFS Storage Issues

**Check NFS mount status:**
```bash
kubectl exec -it -n default db-* -- mount | grep nfs
```

**Fix NFS permissions:**
```bash
# From the node
ssh suryendub@kubernetes1
sudo ls -la /var/lib/kubelet/pods/*/volumes/kubernetes.io~nfs/

# If permissions wrong, fix on NAS
ssh admin@192.168.0.128
sudo chmod 777 /share/Public/default-mssql-nas-pvc-*
```

**Fix NFS Protocol Mismatch (`Protocol not supported`):**
*Symptom:* Pods stuck in `ContainerCreating` with `mount.nfs: Protocol not supported` after node restart or rescheduling.
*Cause:* Linux kernel defaults to NFSv4, but the NAS (NASECDE55) expects NFSv3.
*Fix:* Ensure `nfsvers=3` is defined in your StorageClass `mountOptions`.

```yaml
# Edit storageclass nfs-nas
kubectl edit storageclass nfs-nas

# Add/Verify mountOptions:
mountOptions:
  - nfsvers=3
  - noatime
  - nodiratime
```
*Note:* After changing the StorageClass, you must delete and recreate the stuck PVC/Pod for the new options to take effect.

### Node Not Ready

**Check kubelet status:**
```bash
ssh suryendub@kubernetes1
sudo systemctl status k3s-agent

# View kubelet logs
sudo journalctl -u k3s-agent -n 50 -f
```

**Restart K3s service:**
```bash
sudo systemctl restart k3s-agent
```

### Cluster Network Issues

**Test DNS:**
```bash
kubectl exec -it <pod-name> -- nslookup kubernetes.default
```

**Test service connectivity:**
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  wget -O- http://db:1433
```

**Restart networking:**
```bash
# On affected node
ssh suryendub@kubernetes1
sudo systemctl restart k3s-agent
```

---

## 📚 Documentation References

### Recent Fix Documentation

- **[REMEDIATION_COMPLETE_2026-03-30.md](REMEDIATION_COMPLETE_2026-03-30.md)** - Executive summary of recent cluster fixes
- **[CLUSTER_FIXES_2026-03-30.md](CLUSTER_FIXES_2026-03-30.md)** - Detailed technical documentation of all fixes

### Configuration Files

- **[iiq-deployment.yaml](iiq-deployment.yaml)** - IdentityIQ deployment configuration
- **[iiq-stateful.yaml](iiq-stateful.yaml)** - Alternative stateful version
- **[docker-compose.yaml](docker-compose.yaml)** - Docker Compose reference
- **[keycloak.yaml](keycloak.yaml)** - Keycloak configuration
- **[keycloak-ingress.yaml](keycloak-ingress.yaml)** - Keycloak Ingress rules

### External Resources

- [K3s Official Documentation](https://docs.k3s.io/)
- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [Traefik Ingress Documentation](https://doc.traefik.io/traefik/)
- [NFS CSI Driver](https://github.com/kubernetes-csi/csi-driver-nfs)

---

## 🎯 Quick Reference Commands

```bash
# Cluster Info
kubectl cluster-info                          # Cluster details
kubectl get nodes -o wide                     # Node list with IPs
kubectl top nodes                             # Node resource usage
kubectl describe node <node-name>             # Node detailed info

# Pod Management
kubectl get pods -A                           # All pods across namespaces
kubectl get pods -n <namespace>               # Namespace pods
kubectl describe pod <pod-name> -n <namespace> # Pod details
kubectl logs <pod-name> -n <namespace>        # Pod logs
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash  # Shell access
kubectl port-forward <pod-name> 8080:8080 -n <namespace>  # Port forwarding

# Deployment Management
kubectl set image deployment/iiq iiq=image:newtag -n default  # Update image
kubectl rollout restart deployment/iiq -n default             # Restart deployment
kubectl rollout status deployment/iiq -n default              # Check rollout
kubectl scale deployment/iiq --replicas=3 -n default          # Scale deployment

# Storage
kubectl get pvc -A                            # All persistent volume claims
kubectl get pv                                # All persistent volumes
kubectl describe pvc <pvc-name> -n <namespace> # PVC details

# Debugging
kubectl get events -A --sort-by='.lastTimestamp' | tail -20   # Recent events
kubectl get pods -A --field-selector=status.phase!=Running    # Non-running pods
kubectl debug node/<node-name> -it --image=ubuntu:24.04       # Debug node
```

---

**Status**: ✅ All systems operational  
**Last Health Check**: 2026-03-30 19:20 UTC  
**Next Review**: 2026-04-06  
**Emergency Contact**: Check CLUSTER_FIXES_2026-03-30.md for troubleshooting

## 🔗 Tailscale Service Exposure

### Prerequisites: Tailscale ACL Policy

Before services can get Tailscale IPs, your **Tailscale ACL policy** (`policy.hujson` or `acl.json`) must define tag owners:

```json
{
  "tagOwners": {
    "tag:k8s":          ["your-user@domain.com"],
    "tag:k8s-operator": ["your-user@domain.com"]
  }
}
```

Without these tags, the operator cannot assign Tailscale IPs to services.

### Exposing a Service

Add these annotations to your Service or Ingress:

```yaml
metadata:
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "service-name"
    tailscale.com/tags: "tag:k8s"
```

The operator will create a proxy pod (`ts-<service>-<hash>-0`) and assign a `100.x.x.x` Tailscale IP.

### Currently Exposed Services

| Service | Tailscale Hostname | Namespace |
|---------|-------------------|-----------|
| **OpenWebUI** | `openwebui` | ai |
| **ArgoCD** | `argocd` | argocd |
| **Homepage** | auto-generated | default |
| **ActiveMQ** | auto-generated | iiqstack |
| **Counter** | auto-generated | iiqstack |
| **MSSQL (db)** | auto-generated | iiqstack |
| **MySQL** | auto-generated | iiqstack |
| **MailHog** | auto-generated | iiqstack |
| **IIQ** | auto-generated | iiqstack |
| **LDAP** | auto-generated | iiqstack |
| **phpLDAPadmin** | auto-generated | iiqstack |
| **SSH** | auto-generated | iiqstack |

### Accessing Services

From any device on your Tailscale network:
```
# Named services
http://openwebui:8080
https://argocd:443

# For auto-generated hostnames, check your Tailscale admin console
# at https://login.tailscale.com/admin/machines
```

### Managing the Operator

```bash
# Check operator status
kubectl get pods -n tailscale

# View operator logs
kubectl logs -n tailscale deploy/operator --tail=20

# List all Tailscale services
kubectl get svc -A | grep tailscale
```
