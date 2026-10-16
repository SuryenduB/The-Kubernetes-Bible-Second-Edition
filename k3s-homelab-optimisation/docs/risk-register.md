# K3s Homelab Risk Register

This document tracks identified architectural, operational, and data risks across the seven-node K3s homelab cluster.

---

## Risk Summary Matrix

| Risk ID | Category | Risk Description | Likelihood | Impact | Severity | Mitigation Strategy | Owner / Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **R-01** | Availability | Single-Node etcd Control Plane on NUC | Medium | Critical | **High** | Maintain frequent verified etcd snapshots copied to NAS; evaluate 3-node HA control plane. | Open / Under Review |
| **R-02** | Availability | Scheduled 02:00 UTC K3s Service Stoppage | High | High | **High** | Replace disruptive legacy SQLite backup script with native non-disruptive `k3s etcd-snapshot`. | Actionable / Prepared |
| **R-03** | DNS | CoreDNS Single Replica Failure | Medium | High | **High** | Scale CoreDNS deployment from 1 to 2 replicas with host anti-affinity and PDB. | Actionable / Prepared |
| **R-04** | Storage | Mixed SSD and Rotational HDD Latency in Longhorn | High | Medium | **Medium** | Ensure 3-replica Longhorn volumes avoid all-HDD placement where possible; monitor replica sync latency. | Managed |
| **R-05** | Provisioning | Ambiguity from Dual Default StorageClasses | Medium | Medium | **Medium** | Remove default annotation from `local-path`, leaving `longhorn` as sole default. | Actionable / Prepared |
| **R-06** | Maintenance | Node Drain Deadlock due to `maxUnavailable: 0` PDBs | High | Medium | **Medium** | Update node maintenance runbook to safely handle single-replica PDB overrides during planned drains. | Documented in Runbook |
| **R-07** | OS Stability | Inotify Instance Exhaustion under Heavy Pod Density | Medium | High | **Medium** | Increase `fs.inotify.max_user_instances` from 128 to 8192 via sysctl. | Actionable / Prepared |
| **R-08** | Security | Accidental Credential Leakage in Git or Logs | Low | Critical | **High** | Hardened `.gitignore` and enforced `redact-output.sh` pipeline on all command outputs. | Mitigated |

---

## Detailed Risk Analyses

### R-01: Single-Node etcd Control Plane on NUC
- **Description:** The cluster currently relies on `nuc` as the sole K3s server and etcd voter. The hardware is an older Intel Celeron 847E (dual-core 1.10GHz) with a 120GB mSATA SSD.
- **Potential Impact:** A hardware failure, power cut, or operating system crash on `nuc` brings down the Kubernetes API, stops reconciliation, and prevents scheduling.
- **Mitigation:**
  1. Short-term: Ensure etcd snapshots are taken every 6 hours and copied off-node to the NAS (`192.168.0.128`).
  2. Long-term: Evaluate promoting two fast worker nodes (`kubernetes2` and `kubernetes4`) to K3s servers to establish a 3-node quorum.

### R-02: Scheduled 02:00 UTC K3s Service Stoppage
- **Description:** A legacy script `/usr/local/bin/k3s-backup-to-nas.sh` is executed by crontab every day at 02:00 UTC. The script executes `systemctl stop k3s` to copy an obsolete 0-byte SQLite database.
- **Potential Impact:** Daily control-plane outage for 10–30 seconds, risking transient workload errors and failed health probes.
- **Mitigation:** Remove the crontab entry and install the online atomic snapshot script that does not stop the K3s daemon.

### R-03: CoreDNS Single Replica Failure
- **Description:** CoreDNS is running with `spec.replicas: 1` located on `kubernetes6`.
- **Potential Impact:** Any scheduled reboot, kernel update, or pod eviction of `kubernetes6` terminates cluster-wide DNS resolution until Kubelet reschedules and launches the replacement pod.
- **Mitigation:** Deploy `kubernetes/monitoring/coredns-ha-patch.yaml` to ensure at least 2 replicas are running across distinct worker nodes.

### R-04: Mixed SSD and Rotational HDD Latency in Longhorn
- **Description:** Three worker nodes (`kubernetes1`, `kubernetes5`, `kubernetes6`) utilize 2.5" and 3.5" rotational mechanical hard drives (5400/7200 RPM), while three nodes (`kubernetes2`, `kubernetes3`, `kubernetes4`) use SSDs or NVMe.
- **Potential Impact:** Longhorn synchronously writes to all 3 volume replicas. The write latency of any volume is bounded by the slowest disk in its replica set.
- **Mitigation:** Group fast storage nodes using Kubernetes labels (`storage.tier: nvme-ssd`) and use Longhorn disk tags or storage classes for latency-sensitive databases.
