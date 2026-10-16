# K3s Homelab Cluster: Current State Assessment

**Assessment Date:** 2026-10-17  
**Post-Execution Updates:** 2026-10-17 — APP-01…APP-05 applied & verified live; see `change-log.md` §7–§9.  
**Cluster Name:** `k3s-homelab`  
**API Server Endpoint:** `https://192.168.0.21:6443`  
**K3s Version:** `v1.34.6+k3s1`  
**Container Runtime:** `containerd://2.2.2-bd1.34`  
**Installed CNI:** Flannel (`flannel.1` overlay VXLAN, MTU 1450)  
**Cluster CIDR:** `10.42.0.0/16`  
**Service CIDR:** `10.43.0.0/16`  
**Cluster DNS:** `10.43.0.10` (CoreDNS)  
**Active Nodes:** 7 Ubuntu nodes (1 Server / Control Plane, 6 Agents / Workers)

---

## 1. Node Inventory and Hardware Classification

| Node Name | IP Address | Role | Hardware Class / Model | CPU Specs | RAM (Total/Avail) | Storage Device & Type | Root Filesystem (Used / Total) | Swap |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`nuc`** | `192.168.0.21` | `control-plane,etcd,master` | Intel DCP847SKE (Mini PC) | Intel Celeron 847E @ 1.10GHz (2 cores) | 7.7 GiB / 5.3 GiB | Kingston SMS200S3120G (120GB SSD, ROTA=0) | 52G / 109G (50%) | 4.0G (0 used) |
| **`kubernetes1`** | `192.168.0.19` | `worker` | Fujitsu ESPRIMO Q520 (USFF) | Intel Core i5-4590T @ 2.00GHz (4 cores) | 15.0 GiB / 10.0 GiB | Seagate ST500LM000 (500GB HDD, ROTA=1) | 318G / 455G (74%) | 4.0G (2M used) |
| **`kubernetes2`** | `192.168.0.20` | `worker` | ITMediaConsult AG | Intel Core i3-8100 @ 3.60GHz (4 cores, 8th Gen) | 15.0 GiB / 12.0 GiB | Crucial CT1000P3SSD8 (1TB NVMe SSD, ROTA=0) | 59G / 197G (32%) | 4.0G (1M used) |
| **`kubernetes3`** | `192.168.0.22` | `worker` | Gigabyte BRIX / Laptop | Intel Core i3-6100U @ 2.30GHz (2C/4T) | 15.0 GiB / 12.0 GiB | Kingston SM2280S (120GB SSD, ROTA=0) | 78G / 107G (77%) | 4.0G (1M used) |
| **`kubernetes4`** | `192.168.0.23` | `worker` | Dell OptiPlex (SFF) | Intel Core i5-4590S @ 3.00GHz (4 cores) | 7.7 GiB / 5.2 GiB | Samsung MZ7LN256 (256GB SSD, ROTA=0) | 64G / 98G (69%) | 0B (Disabled) |
| **`kubernetes5`** | `192.168.0.24` | `worker` | Acer Veriton | Intel Core i3-4130 @ 3.40GHz (2C/4T) | 7.7 GiB / 4.5 GiB | WD Blue WD10EZEX (1TB HDD, ROTA=1) | 68G / 197G (37%) | 4.0G (0 used) |
| **`kubernetes6`** | `192.168.0.25` | `worker` | Fujitsu ESPRIMO | Intel Core i3-4350T @ 3.10GHz (2C/4T) | 15.0 GiB / 12.0 GiB | Toshiba MQ02ABF0 (500GB HDD, ROTA=1) | 165G / 295G (59%) | 4.0G (0 used) |

### Inactive / Stale Node Objects in Cluster
Two node objects remain in Kubernetes metadata, both intentionally retained (expected to return):
- `server-236` (`192.168.0.236`): Hyper-V VM host on HP-1. Cordoned, NotReady in K3s. Hosts local Docker registry on port 5000.
- `server-252` (`192.168.0.252`): Hyper-V VM (`k3s-master`). Offline / NotReady,SchedulingDisabled.

`kubernetes7` (dead hardware, broken power switch) and `kubernetes8-debian` (stale test node) were **fully decommissioned on 2026-10-17** (Kubernetes + Longhorn objects; see `change-log.md` §9).

---

## 2. Point-in-Time Resource Baseline

### Node Resource Consumption (`kubectl top nodes`)

| Node | CPU (Cores) | CPU % | Memory (Bytes) | Memory % |
| :--- | :--- | :--- | :--- | :--- |
| `nuc` | 537m | 26% | 2788Mi | 35% |
| `kubernetes1` | 370m | 9% | 5323Mi | 33% |
| `kubernetes2` | 431m | 10% | 3405Mi | 21% |
| `kubernetes3` | 477m | 11% | 4152Mi | 26% |
| `kubernetes4` | 370m | 9% | 2856Mi | 36% |
| `kubernetes5` | 610m | 15% | 4593Mi | 58% |
| `kubernetes6` | 477m | 11% | 3974Mi | 25% |

**Total Cluster Memory Capacity:** ~83 GiB  
**Total Cluster Memory Consumed:** ~27.1 GiB (32.6% utilization)  
**Total Cluster CPU Allocation:** 24 Cores across 7 active physical machines  
**Total Cluster CPU Consumed:** 3.27 cores (13.6% utilization)

---

## 3. Datastore and Control-Plane Topology

- **Datastore Type:** Embedded etcd (migrated from SQLite on 2026-09-19).
- **Cluster Members:** Single active voter (`nuc-1e55bd21`, ID `5e5bac64bb6a6190`).
- **Quorum:** 1/1. Tolerates 0 failures. Loss of `nuc` stops API server.
- **Snapshot Location:** `/var/lib/rancher/k3s/server/db/snapshots/`.
- **Latest Snapshot:** `etcd-snapshot-nuc-1792188003` (Size: 225 MB, created 2026-10-17 00:00:03 CEST).
- **Control-Plane Workload Isolation:** `nuc` has no control-plane taints (`NoSchedule` is absent), but runs minimal user workloads due to Longhorn node exclusion.

---

## 4. Storage Architecture

- **Default StorageClass:** Longhorn (`driver.longhorn.io`), 3 replicas across workers.
- **Secondary:** `local-path` — default flag removed on 2026-10-17 (`storageclass.kubernetes.io/is-default-class: "false"`); `longhorn` is now the sole default.
- **NFS Class:** `nfs-nas` on Synology/QNAP NAS (`192.168.0.128:/share/Public`).
- **Active Persistent Volumes:** 42 PVs bound.
  - 38 Longhorn volumes (healthy and attached).
  - 4 NFS volumes (`ollama-pvc`, `webui-nas-pvc`, `ollama-nas-pvc`, `iiq-nas-pvc-nfs`).
- **Storage Performance Division:**
  - Fast SSD/NVMe tier: `kubernetes2` (Crucial NVMe), `kubernetes4` (Samsung SSD), `kubernetes3` (Kingston SSD).
  - Rotational HDD tier: `kubernetes1` (500GB HDD), `kubernetes5` (1TB HDD), `kubernetes6` (500GB HDD).

---

## 5. Networking, DNS, and Ingress

- **CNI:** Flannel VXLAN overlay (`flannel.1` on `10.42.0.0/16`).
- **CoreDNS:** Version 1.14.2 — scaled to **2 replicas** with hard host spread + `coredns-pdb` on 2026-10-17 (previously a single-replica SPOF).
- **Ingress Controller:** Traefik (packaged with K3s).
- **Load Balancer:** K3s ServiceLB (Klipper LB DaemonSet binding ports 80/443 on worker nodes).
- **Remote Access:** Tailscale Kubernetes Operator. 48 `ts-*` StatefulSets configured; the pods stuck `Terminating` on the offline `kubernetes7` were force-cleaned during its decommissioning on 2026-10-17.
