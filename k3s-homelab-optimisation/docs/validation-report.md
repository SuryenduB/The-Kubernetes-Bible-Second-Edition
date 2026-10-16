# K3s Homelab Validation & Health Conformance Report

**Execution Date:** 2026-10-17  
**Validation Suite:** `scripts/validate-cluster.sh`, `scripts/validate-dns.sh`, `scripts/validate-network.sh`, `scripts/verify-etcd-snapshot.sh`  
**Overall Conformance Status:** **MEASURED LIVE BASELINE (Approval-gated remediations not applied)**

---

## 1. Conformance Test Results Matrix

| Test Suite / Area | Check Description | Method / Command | Result | Details |
| :--- | :--- | :--- | :--- | :--- |
| **Node Health** | Active Ubuntu nodes Ready | `kubectl get nodes` | **PASS** | 7/7 active Ubuntu nodes Ready (`nuc`, `kubernetes1`–`kubernetes6`). 4 offline nodes detected (`server-236`, `server-252`, `kubernetes8-debian`, `kubernetes7`). |
| **API Server** | Control plane responsiveness | `kubectl cluster-info` | **PASS** | API Server at `https://192.168.0.21:6443` responded instantly. |
| **etcd Datastore** | Snapshot presence & metadata | `k3s etcd-snapshot list` | **METADATA VERIFIED** | Latest snapshot `etcd-snapshot-nuc-1792188003` valid locally (225 MB). Snapshot presence and metadata were verified. Recoverability is not yet proven. (Not copied off-node; no isolated restore test). |
| **Cluster DNS** | Internal service discovery | `validate-dns.sh` | **PASS** | `kubernetes.default` resolved to `10.43.0.1`. |
| **Public DNS** | External public resolution | `validate-dns.sh` | **PASS** | `google.com` resolved A and AAAA records without delay. |
| **DNS Latency** | Sequential lookup duration | 5 consecutive queries | **PASS** | 0.02 seconds real elapsed time (4ms per query). |
| **CoreDNS Availability** | Active ready replica count | `kubectl -n kube-system get deployment coredns` | **WARN** | 1 ready replica (SPOF on `kubernetes6`; HA patch prepared). |
| **Pod Overlay Network** | Cross-node pod ICMP reachability | `validate-network.sh` | **PASS** | `kubernetes1` -> `kubernetes2` ping: 0% loss, 0.59ms avg latency. |
| **Network MTU** | Overlay MTU fragmentation test | 1400-byte ICMP payload | **PASS** | 0% packet loss through Flannel VXLAN overlay. |
| **ClusterIP Routing** | Pod-to-Service ClusterIP | `nc -z -w 3 10.43.0.1 443` | **PASS** | Direct TCP connectivity established. |
| **Longhorn Storage** | Volume robustness & replica placement | `kubectl get volumes,replicas.longhorn.io` | **PASS** | 39/40 Longhorn volumes attached and healthy with 3 running RW replicas across distinct nodes. 1 volume detached (`iiq-nas-pvc`). |
| **Manifest Validation** | Server-side dry-run conformance | `kubectl apply --dry-run=server` | **PASS** | StorageClass patch, CoreDNS HA patch, smoke test, and PSA audit policies all accepted by apiserver. |

---

## 2. Point-in-Time Metrics & Performance Evidence

### Network Latency & Packet Statistics
```text
PING 10.42.2.29 (10.42.2.29): 56 data bytes
64 bytes from 10.42.2.29: seq=0 ttl=62 time=0.721 ms
64 bytes from 10.42.2.29: seq=1 ttl=62 time=0.367 ms
64 bytes from 10.42.2.29: seq=2 ttl=62 time=0.700 ms

--- 10.42.2.29 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.367/0.596/0.721 ms
```

### DNS Latency Evidence
```text
Testing DNS Latency (time to resolve 5 queries):
real 0.02s
user 0.00s
sys  0.01s
Query Status: All queries returned valid A records for cluster services.
```

### Storage Robustness Evidence
```text
Total Longhorn Volumes: 40
Configured for 3 Replicas: 40
Healthy Attached Volumes (3 RW Replicas): 39
Volumes with Insufficient Healthy Replicas: 1 (pvc-1a05dbf3 - detached intentionally for iiq-nas-pvc)
Degraded / Faulted Volumes: 0
Replicas Concentrated on Fewer Failure Domains: 0 (all 39 attached volumes distribute replicas across 3 distinct nodes)
```

---

## 3. Operational Warnings Summary

1. **CoreDNS Single Replica:** Only 1 replica is active. Remediation manifest `kubernetes/monitoring/coredns-ha-patch.yaml` has passed server-side dry-run and is approval-gated.
2. **Offline Node DaemonSets:** DaemonSets (`beszel-agent`, `node-disk-cleanup`, `registry-fixer`) report pending pods on the 4 offline node objects (`server-236`, `server-252`, `kubernetes8-debian`, `kubernetes7`).
3. **Control-Plane Datastore Single Point of Failure:** 1 active server node (`nuc`) backing etcd and API server.
