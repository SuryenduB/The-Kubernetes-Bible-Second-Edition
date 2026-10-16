# K3s Homelab Cluster Architecture

This document outlines the architectural topology, data flow, storage model, and networking of the seven-node Ubuntu K3s homelab.

---

## 1. High-Level Cluster Topology

```mermaid
flowchart TD
    subgraph LAN["Physical LAN (192.168.0.0/24)"]
        NAS["NAS Storage (192.168.0.128)<br/>NFS Exports & Longhorn Backups"]
        CP["Control Plane Node: nuc (192.168.0.21)<br/>Intel Celeron 847E (2 cores) | 8GB RAM<br/>Single etcd Member (Leader)"]
        
        subgraph Workers["Active Worker Tier (6 Ubuntu Nodes)"]
            W1["kubernetes1 (.19)<br/>i5-4590T | 16GB RAM<br/>500GB HDD (Longhorn Storage)"]
            W2["kubernetes2 (.20)<br/>i3-8100 | 16GB RAM<br/>1TB NVMe SSD (Longhorn Storage)"]
            W3["kubernetes3 (.22)<br/>i3-6100U | 16GB RAM<br/>120GB SSD (Longhorn Storage)"]
            W4["kubernetes4 (.23)<br/>i5-4590S | 8GB RAM<br/>256GB SSD (Longhorn Storage)"]
            W5["kubernetes5 (.24)<br/>i3-4130 | 8GB RAM<br/>1TB HDD (Longhorn Storage)"]
            W6["kubernetes6 (.25)<br/>i3-4350T | 16GB RAM<br/>500GB HDD (Longhorn Storage)"]
        end
    end

    CP -->|"Flannel Overlay (10.42.0.0/16)"| Workers
    Workers -->|"Replicated Storage (3 Replicas)"| Workers
    Workers -.->|"NFS Media Mounts"| NAS
    CP -.->|"etcd Snapshots (Daily / 6-hourly)"| NAS
```

---

## 2. Ingress & Traffic Routing Architecture

```mermaid
flowchart LR
    Client["Clients / Tailscale Mesh"] --> IngressEntry["Traefik LoadBalancer Service<br/>(Ports 80 / 443 on Worker Nodes)"]
    IngressEntry --> ServiceLB["K3s ServiceLB (Klipper DaemonSet)<br/>Bound across kubernetes1-6"]
    ServiceLB --> Traefik["Traefik Ingress Controller Pods"]
    Traefik --> CoreDNS["CoreDNS (10.43.0.10:53)<br/>Single Active Replica on kubernetes6"]
    Traefik --> Workloads["Application Services<br/>(AI, Immich, OpenLingo, IIQ, Monitoring)"]
```

---

## 3. Storage Hierarchy & Resilience Model

```mermaid
flowchart TD
    App["Stateful Applications<br/>(PostgreSQL, MariaDB, Immich, Beszel)"]
    
    subgraph StorageClasses["Storage Class Layer"]
        SC1["longhorn (Default)<br/>driver.longhorn.io<br/>numberOfReplicas: 3"]
        SC2["nfs-nas<br/>NFS Subdir External Provisioner<br/>NAS Target: 192.168.0.128"]
        SC3["local-path<br/>rancher.io/local-path<br/>(Host-pinned)"]
    end
    
    App --> SC1
    App --> SC2
    
    subgraph StorageBackends["Storage Providers"]
        SC1 --> LonghornEngine["Longhorn Engine (Distributed Block Storage)"]
        SC2 --> NFSExport["Synology/QNAP NFS (/share/Public)"]
    end

    subgraph PhysicalDisks["Physical Disk Heterogeneity"]
        LonghornEngine --> FastTier["Fast SSD Tier<br/>kubernetes2 (NVMe)<br/>kubernetes3 (SSD)<br/>kubernetes4 (SSD)"]
        LonghornEngine --> SlowTier["Rotational HDD Tier<br/>kubernetes1 (HDD)<br/>kubernetes5 (HDD)<br/>kubernetes6 (HDD)"]
    end

    LonghornEngine -.->|"Recurring Backup Jobs"| NFSExport
```

---

## 4. Single Points of Failure (SPOF) Analysis

1. **Embedded etcd Quorum:**
   - Single voter on `nuc`. If `nuc` suffers hardware or network failure, the Kubernetes API becomes unavailable cluster-wide.
2. **CoreDNS Replica Count:**
   - Single running replica on `kubernetes6`. If `kubernetes6` is rebooted or experiences memory pressure, in-cluster DNS resolution fails for all pods.
3. **Legacy Backup Cron Disruption:**
   - Daily cron job `/usr/local/bin/k3s-backup-to-nas.sh` stopping `k3s.service` on `nuc` every morning at 02:00 UTC.
4. **Storage Latency Bottleneck:**
   - 3-replica Longhorn volumes spanning across both NVMe and spinning HDDs are throttled by the slowest rotational drive write latency.
