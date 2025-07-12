# 🧪 K3s Homelab Documentation

## 📅 Last Update Date

<2025-07-10>
---

## 🖥️ System Overview

| Hostname     | Chassis        | OS Version           | Kernel                  | Architecture | Hardware Vendor        | Hardware Model                  | Firmware Version                        | Firmware Date      | Firmware Age     |
|--------------|----------------|----------------------|-------------------------|--------------|-----------------------|----------------------------------|-----------------------------------------|--------------------|------------------|
| NUC          | desktop 🖥️     | Ubuntu 24.04.2 LTS   | 6.11.0-26-generic       | x86-64       | Intel Corporation     | DCP847SKE                        | GKPPT10H.86A.0047.2013.1118.1714        | Mon 2013-11-18     | 11y 5m 3w        |
| kubernetes1  | desktop 🖥️     | Ubuntu 24.04.2 LTS   | 6.8.0-60-generic        | x86-64       | FUJITSU               | ESPRIMO Q520                      | V4.6.5.4 R1.47.0 for D3223-C1x          | Mon 2019-08-26     | 5y 8m 2w 1d      |
| kubernetes2  | desktop 🖥️     | Ubuntu 24.04.2 LTS   | 6.8.0-60-generic        | x86-64       | ITMediaConsult AG     | Pentino_H-Series A-4_M_H310-1     | 3202                                    | Sat 2021-07-10     | 3y 10m           |
| kubernetes3  | laptop 💻      | Ubuntu 24.04.2 LTS   | 6.8.0-60-generic        | x86-64       | GIGABYTE              | GB-BSi3-6100                      | F4                                      | Tue 2015-12-08     | 9y 5m 2d         |
| kubernetes4  |                | Ubuntu 24.04.2 LTS   | 6.8.0-60-generic        | x86-64       | Dell Inc.             | OptiPlex 9020                    | A25                                     | 05/30/2019         | 6y 1m 1w         |

---

### 🆔 Machine & Boot IDs

| Hostname     | Machine ID                           | Boot ID                               |
|--------------|--------------------------------------|---------------------------------------|
| NUC          | 7f008044c9034b0bb5336558d14146e4     | 018d8e4b4f944b46acd7d2622238a25a      |
| kubernetes1  | 069b4db95ee44204b2b9711a5c8c758e     | f7e55003772c4a62947e986761071b49      |
| kubernetes2  | 7b40a6eec44842b68c4b0e6ccece70b8     | 871de8b90262422d833376c12170509e      |
| kubernetes3  | fcf6d4cb3ab340a48e6567abb43f6334     | bf5ff8d6e62349648998170171fd8f09      |
| kubernetes4  | 8c1b18d2c52e4a1f941239f1abab8a06     | 4787e1fb-b008-494b-b9f6-ec9680be8097      |

---

### 🖥️ CPU Model Overview

| Hostname     | CPU Model                                      |
|--------------|------------------------------------------------|
| NUC          | Intel(R) Celeron(R) CPU 847E @ 1.10GHz         |
| kubernetes1  | Intel(R) Core(TM) i5-4590T CPU @ 2.00GHz       |
| kubernetes2  | Intel(R) Core(TM) i3-8100 CPU @ 3.60GHz        |
| kubernetes3  | Intel(R) Core(TM) i3-6100U CPU @ 2.30GHz       |
| kubernetes4  | Intel(R) Core(TM) i5-4590S CPU @ 3.00GHz       |

### 🖥️ Memory Overview

| Hostname     | Total RAM | Used RAM | Free RAM | Buff/Cache | Available RAM | Total Swap | Used Swap | Free Swap |
|--------------|----------:|---------:|---------:|-----------:|--------------:|-----------:|----------:|----------:|
| NUC          |    7.7 Gi |   1.4 Gi |   5.5 Gi |     1.1 Gi |        6.3 Gi |     4.0 Gi |      0 B  |    4.0 Gi |
| kubernetes1  |     15 Gi |   674 Mi |    14 Gi |     685 Mi |         14 Gi |     4.0 Gi |      0 B  |    4.0 Gi |
| kubernetes2  |     14 Gi |   2.6 Gi |   8.3 Gi |      4.0 Gi|         11 Gi |     4.0 Gi |      0 B  |    4.0 Gi |
| kubernetes3  |     15 Gi |   2.8 Gi |   9.2 Gi |      3.8 Gi|         12 Gi |     4.0 Gi |      0 B  |    4.0 Gi |
| kubernetes4  |    7.7 Gi |   1.5 Gi |   4.1 Gi |     2.3 Gi |        6.1 Gi |     0 B    |      0 B  |    0 B    |

## 📡 Network Configuration

| Node Role | Hostname | IP Address     | Interface | Notes         |
|-----------|----------|----------------|-----------|---------------|
| master    |   **NUC**       |    192.168.0.21             |  eno1         |               |
| worker-1  |   **KUBERNETES1**       |      192.168.0.19           |    enp0s25        |               |
| worker-2  |   **KUBERNETES2**       |   192.168.0.20             |     enp2s0      |               |
| worker-2  |   **KUBERNETES3**       |    192.168.0.22            |     enp0s31f6      |
| worker-3  |   **KUBERNETES4**       |    192.168.0.23            |     eno1           |               |

Commands:
```bash
ip a
ip route
nmcli device show
```

---

## 🚀 K3s Installation 


### 🚀 K3s Service Status

| Hostname     | K3s Version                | Go Version   | Systemd Unit        | Status   | Main PID | Memory Usage | Uptime      |
|--------------|----------------------------|-------------|---------------------|----------|---------:|-------------:|-------------|
| NUC          | v1.32.4+k3s1 (079ffa8d)    | go1.23.6    | k3s.service         | running  |     1351 |   760.7 MiB  | 24 min      |
| kubernetes1  | v1.32.4+k3s1 (079ffa8d)    | go1.23.6    | k3s-agent.service   | running  |     1022 |   305.8 MiB  | 24 min      |
| kubernetes2  | v1.32.4+k3s1 (079ffa8d)    | go1.23.6    | k3s-agent.service   | running  |      872 |   367.2 MiB  | 25 min      |
| kubernetes3  | v1.32.4+k3s1 (079ffa8d)    | go1.23.6    | k3s-agent.service   | running  |     1009 |   414.6 MiB  | 24 min      |
| kubernetes4  | v1.32.4+k3s1 (079ffa8d)    | go1.23.6    | k3s-agent.service   | running  |      961 |   994.7 MiB  | 1h 6min     |


| Setting             | Value                         |
|---------------------|-------------------------------|
| Install Method      | curl  |
| Version             | `k3s --version`               |
| Systemd Service     | `systemctl status k3s`        |
| Cluster Token       | `<Stored securely>`           |
| Kubeconfig Path     | `~/.kube/config`              |



---

## 🛠️ Installed Add-ons / Tools

| Add-on         | Description           | Install Method     | Status |
|----------------|-----------------------|--------------------|--------|
| Traefik        | Ingress Controller    | Built-in/Helm      | ✅     |
| Longhorn       | Storage               | Helm               | ❌     |
| MetalLB        | LoadBalancer          | Manifest/Helm      | ✅     |
| Metrics Server | Resource Monitoring   | Helm               | ✅     |
| Rancher        | UI/Management         | Helm               | ❌     |

---

## 📦 Workloads

| Namespace   | App Name         | Description             | Deploy Method   |
|-------------|------------------|-------------------------|-----------------|
| ai          | ollama           |                         |                 |
| ai          | openwebui        |                         |                 |
| argocd      | argocd-applicationset-controller |         |                 |
| argocd      | argocd-dex-server|                         |                 |
| argocd      | argocd-notifications-controller |         |                 |
| argocd      | argocd-redis     |                         |                 |
| argocd      | argocd-repo-server |                     |                 |
| argocd      | argocd-server    |                         |                 |
| bgd         | bgd              |                         |                 |
| default     | activemq         |                         |                 |
| default     | counter          |                         |                 |
| default     | db               |                         |                 |
| default     | iiq              |                         |                 |
| default     | ldap             |                         |                 |
| default     | loadbalancer     |                         |                 |
| default     | mail             |                         |                 |
| default     | pacman           |                         |                 |
| default     | phpldapadmin     |                         |                 |
| default     | ssh-deployment   |                         |                 |
| kube-system | coredns          |                         |                 |
| kube-system | local-path-provisioner |                 |                 |
| kube-system | metrics-server   |                         |                 |
| kube-system | traefik          |                         |                 |

---

## 🔐 Authentication & Access

| Component       | Configuration                                                                 |
|-----------------|-------------------------------------------------------------------------------|
| Kubeconfig      | Present (`cat ~/.kube/config` shows cluster, user, and certs)                 |
| RBAC Settings   | Roles and rolebindings exist in various namespaces (e.g., `argocd`, `kube-system`) |
| Users/Groups    | Single user (`default`) via kubeconfig; OIDC not configured                   |
| API Access      | Port `6443`, secured with certificates (see `server:` and `certificate-authority-data` in kubeconfig) |

---

## 📊 Monitoring & Logging

| Tool         | Status | Notes                   |
|--------------|--------|-------------------------|
| Grafana      | ❌     | Dashboard Enabled       |
| Prometheus   | ❌    | Targets OK              |
| Loki         | ⬜      | Planned                 |
| Fluent Bit   | ⬜      | TBD                     |

---

## 🔁 Backup & Recovery

| Tool      | Setup Status | Command/Notes                        |
|-----------|--------------|--------------------------------------|
| etcdctl   | ❌ / ✅        | `k3s etcd-snapshot save`             |
| Velero    | ❌ / ✅       | `velero backup create <name>`        |
| S3 Backup | ❌ / ✅            | AWS/GCP/Minio bucket used            |

---

## ⚠️ Issues & Troubleshooting Notes

- [ ] Node `worker-2` not joining: _Check token / firewall_
- [ ] Helm chart fails: _ImagePullBackOff - missing image tag_

---

## 📚 Useful Commands

\`\`\`bash
# List nodes
kubectl get nodes

# Get all pods in all namespaces
kubectl get pods -A

# View k3s logs
journalctl -u k3s -f

# Helm list
helm list -A
\`\`\`
