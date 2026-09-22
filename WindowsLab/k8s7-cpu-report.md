# Kubernetes7 CPU Incident Report

**Date:** 2026-09-20  
**Node:** kubernetes7 (192.168.0.26)  
**Severity:** High  
**Status:** Active — Node operational but severely overcommitted

---

## Node Profile

| Property | Value |
|----------|-------|
| Role | Worker (PERMANENT SURVIVOR) |
| OS | Ubuntu 24.04 |
| CPU | 4 cores (2C/4T) |
| Memory | 7.7 GiB |
| Disk | 295 GiB (31% used) |
| Special | Physical power switch broken — cannot be powered off |
| Context | Carries largest workload share while other nodes are down |

---

## Symptoms

- CPU at ~90%+ sustained
- Load average: **34.08** (1min), **22.04** (5min), **15.59** (15min) on **4 cores** = ~8.5x overcommit
- CPU utilization: **98.8%** (only 1.2% idle)
- User CPU: 51.8%, System CPU: 42.6%

---

## Root Cause Analysis

### Primary: Longhorn Storage Engines Consuming Excessive CPU

Multiple Longhorn replica engine processes are running simultaneously and consuming the majority of CPU:

| Process | CPU |
|---------|-----|
| longhorn (PID 879859) | 66.6% |
| longhorn (PID 879823) | 50.0% |
| longhorn (PID 879808) | 42.8% |
| longhorn (PID 879834) | 33.3% |
| longhorn-manager (PID 3650707) | 15.0% |
| longhorn-instance-manager (PID 3188754) | 4.8% |
| longhorn (PID 2113852) — volume `pvc-e17ecada...` replica | 2.9% |
| longhorn (PID 2789549) | 0.2% |
| longhorn (PID 987804, 985466, 983792, 971906) | 0.1% each |

**At least 7 Longhorn engine processes** consuming ~240% CPU combined (snapshots changed between samples). These are running Longhorn replica engines for volumes stored on this node — likely because other storage nodes are down and their replicas have been re-replicated onto kubernetes7.

### Secondary: K3s Agent Under Load

| Process | CPU | Notes |
|---------|-----|-------|
| k3s-agent (PID 3163124) | 20.2% | Handling cluster operations from absorbed workloads |
| containerd (PID 3163195) | 6.8% | Container runtime servicing pods |
| containerd-shim (PIDs 12169, 3182632) | 0.4-0.6% | Running container sandbox processes |
| argocd-application-controller | 1.2% | GitOps sync loop |

### Tertiary: User Systemd Process

| Process | CPU | User |
|---------|-----|------|
| systemd (PID 877859) | 65.0% | suryendub |

A user-session systemd running as `suryendub` consuming 65% CPU — this is anomalous and needs investigation. Could be a background service, user-managed daemon, or a runaway process under the user's session.

---

## Memory Status

| Metric | Value | Status |
|--------|-------|--------|
| Total | 7.7 GiB | — |
| Used | 4.2 GiB (55%) | Moderate |
| Free | 574 MiB | Low |
| Buff/Cache | 3.2 GiB | — |
| Available | 3.4 GiB | OK |
| Swap | 189 MiB / 4.0 GiB | Minimal |

Memory is not the bottleneck — CPU is.

---

## Network Status

- 535 TCP total, 18 established
- Not a network bottleneck

---

## Why This Node Is Overcommitted

1. **Permanent survivor**: Physical power switch is broken — node cannot be drained or powered off even under overload
2. **Workload absorber**: Other nodes are down/reduced; kubernetes7 absorbs their Longhorn replicas and Kubernetes workloads
3. **Longhorn storage node**: Volumes from down nodes have replicas re-replicated onto kubernetes7, causing multiple engine processes to spin up
4. **No relief valve**: Unlike other nodes, this one cannot be taken offline for maintenance without losing cluster membership

---

## Immediate Actions

### 1. Identify the rogue user systemd process (PID 877859)
```bash
ps -p 877859 -o pid,ppid,cmd,etime
ls -la /proc/877859/cwd 2>/dev/null
cat /proc/877859/environ 2>/dev/null | tr '\0' '\n'
```

### 2. Check for orphaned Longhorn replica engines
```bash
# From a healthy node
kubectl get pods -A --field-selector spec.nodeName=kubernetes7
# Check Longhorn volume replicas and their nodes
kubectl -n longhorn-system get volumes -o json | jq '.items[] | {name: .metadata.name, state: .state, nodeId: .nodeId, replicaMembers: .status.replicaMembers}'
```

### 3. Identify what workloads have migrated onto this node
```bash
kubectl get pods -A --sort-by=.metadata.creationTimestamp | tail -30
kubectl top pods -A 2>/dev/null | sort -k3 -rn | head -20
```

### 4. Scale down non-critical workloads or redistribute
- If other nodes are coming back, drain workloads from kubernetes7 gradually
- Consider increasing CPU limits on critical pods scheduled here

---

## Medium-Term Recommendations

1. **Replace the physical power switch** on kubernetes7 to restore drain capability
2. **Add CPU headroom**: Either upgrade this VM or ensure at least one other node can absorb workloads before this node hits saturation
3. **Longhorn replica rebalancing**: Verify replica distribution — if kubernetes7 is holding replicas for volumes whose home nodes are down, those engines will be CPU-intensive during rebuild
4. **Investigate user systemd process (PID 877859)**: If this is a user-launched service consuming 65% CPU, it should be managed or constrained

---

## Risk Assessment

| Risk | Impact | Likelihood |
|------|--------|------------|
| Node becomes completely unresponsive | Control plane instability (node is a worker, not control-plane) | Medium |
| Longhorn IO degradation | All volumes with replicas on this node experience slow IO | High |
| OOMKill of critical pods | Memory pressure increases if CPU-bound pods also spike memory | Low |
| Cannot recover node | Power switch broken — requires physical intervention | Already true |
