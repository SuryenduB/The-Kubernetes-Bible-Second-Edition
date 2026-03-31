# 🏠 K3s Homelab - Complete Kubernetes Environment

**Last Updated**: 2026-03-30 | **Status**: ✅ Production Ready | **Version**: K3s v1.34.5+k3s1

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
  │        │        │        │        │        │        │        │
  ▼        ▼        ▼        ▼        ▼        ▼        ▼        ▼
┌───┐  ┌───┐  ┌───┐  ┌───┐  ┌───┐  ┌───┐  ┌───┐  ┌───┐
│NUC│  │ k1│  │ k2│  │ k3│  │ k4│  │ k5│  │ k6│  │ k7│  K3s Cluster
└───┘  └───┘  └───┘  └───┘  └───┘  └───┘  └───┘  └───┘
 CP     W      W      W      W      W      W      W
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

### NAS-Backed Storage Configuration

**NAS Server**: NASECDE55  
**Address**: 192.168.0.128  
**Protocol**: NFS v3/v4  
**Total Capacity**: 423GB  
**Usage**: ~50GB (12%)  
**Mount Type**: RWX (Read-Write-Many)

### Storage Classes

```bash
kubectl get storageclass
```

**Available Storage Classes:**
- `nfs-nas` - Default NAS-backed storage (RWX)
- `local-path` - Local node storage (RWO, for single-node workloads)

### Persistent Volumes & Claims

| PVC Name | Namespace | Size | Storage Class | Status | Mount Path |
|----------|-----------|------|---------------|--------|------------|
| mssql-nas-pvc | default | 15Gi | nfs-nas | Bound | /var/opt/mssql |
| mysql-nas-pvc | default | 2Gi | nfs-nas | Bound | /var/lib/mysql |
| ldap-nas-pvc | default | 2Gi | nfs-nas | Bound | /var/lib/ldap |
| ldap-config-nas-pvc | default | 2Gi | nfs-nas | Bound | /etc/ldap |
| ollama-pvc | ai | 50Gi | local-path | Bound | /root/.ollama |

### NFS Mounted Paths

```
NAS:/share/Public/
├── default-mssql-nas-pvc-pvc-5ebaa04b-d457-40d0-8ff2-9e9a08972d1d/
├── default-mysql-nas-pvc-pvc-a332e0b9-a853-48a7-822b-d1193143c680/
├── default-ldap-nas-pvc-pvc-3a5d9b23-7bfb-472e-8395-8311b4f55f96/
└── default-ldap-config-nas-pvc-pvc-9f365a43-6bba-4d64-978c-0086a9928eb5/
```

### Storage Maintenance

**Check NFS connectivity:**
```bash
kubectl exec -it -n default db-* -- mount | grep nfs
```

**Repair NFS permissions (if needed):**
```bash
# SSH to NAS
ssh admin@192.168.0.128

# Fix MSSQL volume permissions
sudo chmod 777 /share/Public/default-mssql-nas-pvc-*
sudo chown -R 10001:10001 /share/Public/default-mssql-nas-pvc-*
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

**Manual Backup** (Recommended before major changes):
```bash
# Backup etcd (K3s stores in SQLite by default)
sudo /usr/local/bin/k3s-backup-to-nas.sh
```

**Scheduled Backups:**
- Frequency: Daily at 2:00 AM (UTC)
- Destination: NAS (/share/Public/k3s-backups/)
- Retention: 7 days (automatic)

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
ssh ubuntu@192.168.0.19
sudo reboot
# Wait for node to come back and show Ready status
```

### Update K3s

```bash
# Update control plane (nuc)
ssh ubuntu@192.168.0.21
curl -sfL https://get.k3s.io | sh -

# Update workers (one at a time)
ssh ubuntu@192.168.0.19
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
ssh ubuntu@kubernetes1
sudo ls -la /var/lib/kubelet/pods/*/volumes/kubernetes.io~nfs/

# If permissions wrong, fix on NAS
ssh admin@192.168.0.128
sudo chmod 777 /share/Public/default-mssql-nas-pvc-*
```

### Node Not Ready

**Check kubelet status:**
```bash
ssh ubuntu@kubernetes1
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
ssh ubuntu@kubernetes1
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

## Tailscale Service Exposure
Services are exposed via Tailscale annotations. To expose a new service:
1. Add annotations:
   `yaml
   tailscale.com/expose: "true"
   tailscale.com/hostname: "service-name"
   `
2. The operator will assign a 100.x.x.x IP.
