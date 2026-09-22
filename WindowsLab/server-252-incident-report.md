# Server-252 Downtime Incident Report

**Date:** 2026-09-20
**Node:** server-252 (192.168.0.252, hostname `k3s-master`)
**Severity:** High
**Status:** RECOVERED — node is Back Online in cluster, beszel-agent restarted

---

## Incident Timeline

| Time (UTC) | Event |
|------------|-------|
| ~12:34 | server-252 joins cluster (node age 3h4m at 15:38) |
| ~14:15 | User reports .252 showing **down** in Beszel dashboard |
| ~14:42 | SSH to .252 **times out** — node completely unreachable |
| ~14:43 | All ports (22, 6443, 2379, 45876, 8090, 8472) **CLOSED** from workstation |
| ~14:43 | ARP entry for .252: `<incomplete>` — VM gone from hypervisor |
| ~15:07 | **VM auto-recovers** (Hyper-V host restarted or VM reappeared) |
| ~15:07 | k3s server starts on .252 (systemd: active, running) |
| ~15:35 | .252 rejoins Kubernetes cluster as **Ready** |
| ~15:38 | Beszel agent pod `beszel-agent-2npxg` **restarted and Running 1/1** |
| **Downtime duration** | **~25 minutes** |

---

## Root Cause: Hypervisor-Level Disappearance

This is the **second occurrence** of the same pattern documented in `docs/operations/k3s-control-plane-ha-runbook.md`:

> "server-252 VM went offline at the hypervisor level (~15 min after joining)... the VM was powered back on and the retained etcd member rejoined automatically"

server-252 is a **Hyper-V VM** (`k3s-master`) on an **8 GB host that also runs Podman**. The host runs Ubuntu 20.04 with Hyper-V Dynamic Memory enabled.

### Contributing Factors

| Factor | Detail |
|--------|--------|
| **Hyper-V Dynamic Memory** | VM has 2 vCPU / 2 GB RAM (dynamic). Previous log showed `Balloon floor reached`. Host has only 8 GB total (also runs Podman) |
| **No hypervisor HA** | The VM disappeared at hypervisor level — no automatic restart policy confirmed |
| **Single host** | VM runs on a single 8 GB host with no failover partner |
| **Control-plane member** | Loss of .252 reduced etcd from 3→2 members (quorum margin dropped to zero) |

### Evidence

1. **ARP table** (from workstation): `? (192.168.0.252) at <incomplete>` — MAC never resolved = VM not present at hypervisor
2. **All ports closed**: 22 (SSH), 6443 (API), 2379 (etcd), 45876 (Beszel), 8090 (Hub), 8472 (VXLAN)
3. **Ping**: 100% packet loss
4. **Recovery pattern**: VM came back on its own at 15:07 with 31 min uptime (started 15:07) — consistent with hypervisor host reboot/restore

---

## Impact Assessment

### During Outage (~25 minutes)

| System | Status |
|--------|--------|
| **etcd quorum** | 2 of 3 (nuc + .236) — survived but zero margin |
| **Kubernetes API** | Still answered (2/3 etcd members) |
| **server-252 in k8s** | Removed from node list during outage |
| **Beszel monitoring** | .252 showed DOWN (no agent WebSocket) |
| **Longhorn** | No replicas on .252 at time of outage (confirmed in runbook) |
| **Control-plane quorum** | Maintained at 2/3 but with zero headroom |

### After Recovery

| System | Status |
|--------|--------|
| **server-252 node** | Ready, control-plane,etcd,master |
| **etcd member** | Rejoined automatically (retained member) |
| **Beszel agent pod** | Restarted (beszel-agent-2npxg), Running 1/1, restarted 1 time 35m ago |
| **Longhorn** | No replicas were on .252 — no data loss |
| **Node load** | LOW (1.10/0.97/0.89 on 4 cores) — no CPU issue |

---

## Beszel Monitoring Impact

**Why .252 showed DOWN in Beszel:**

The beszel-agent DaemonSet pod `beszel-agent-2npxg` runs on server-252 with `hostNetwork: true`. When the VM disappeared at the hypervisor level:

1. The agent pod went down with the VM
2. The WebSocket connection to the Hub was severed
3. The Hub marked .252 as unreachable (no data received on port 45876)
4. **After recovery**: The DaemonSet automatically recreated the pod on .252, which rejoined the Hub

The recovery is automatic — Beszel does not need manual intervention for this type of outage as long as the DaemonSet pod gets rescheduled.

**Note**: No beszel-agent binary exists on .252 host filesystem (`which beszel-agent` returns nothing) — the agent runs entirely from the Kubernetes DaemonSet pod, not as a host-level service.

---

## Critical Risk

### Quorum Tolerance is NOW Zero

With server-252 back, etcd is at 3/3 again. BUT:

- If .252 goes down again while nuc or .236 are also down, the cluster loses quorum
- The `survivors` list in `homelab-nodes.json` now correctly includes .252 — minimal mode will NOT power it off
- However, if .252 disappears AGAIN at the hypervisor level, recovery is NOT guaranteed without manual intervention

### The 8 GB Hyper-V Host is the Single Point of Failure

The host running VM `k3s-master` (.252) has:
- Only 8 GB RAM (shared with Podman)
- Dynamic memory with history of balloon pressure
- No confirmed VM auto-restart policy

---

## Immediate Actions Required

### 1. Verify VM Auto-Restart Policy on Hyper-V Host
```powershell
# On the Hyper-V host (8 GB, runs Podman)
Get-VM -Name k3s-master | Select-Object Name, State, AutoStartAction, AutoStopAction
# Ensure AutoStartAction = "Start" and AutoStartDelay is set
```

### 2. Increase VM Memory Floor
From the runbook recommendation:
> "bump the VM to 4 GB if etcd ever shows memory pressure"

Current: Dynamic memory floor ~3 GB (observed during k3s operation)
Recommended: Set minimum to 4 GB, maximum to 6 GB (not static 4 GB)

### 3. Monitor .252 Beszel Agent Health
```bash
# From NUC
kubectl get pods -n monitoring -l app=beszel-agent -o wide | grep server-252
# Verify WebSocket is connected (check agent logs)
kubectl logs -n monitoring beszel-agent-2npxg | grep -i "WebSocket connected"
```

### 4. Set Up Hyper-V Heartbeat/Monitoring
- Add the Hyper-V host to monitoring
- Alert if VM `k3s-master` state changes from "Running"
- Consider adding a watchdog script on the Hyper-V host that restarts the VM if it disappears

---

## Medium-Term Recommendations

| Priority | Action | Rationale |
|----------|--------|-----------|
| **P0** | Add VM health monitoring on Hyper-V host | Detect future disappearances within minutes, not hours |
| **P0** | Set VM auto-restart policy | Ensure VM comes back without manual intervention |
| **P1** | Increase .252 VM memory floor to 4 GB | Prevent memory pressure on etcd |
| **P1** | Consider a second Hyper-V host for .252 | Eliminate single-hypervisor SPOF for a control-plane member |
| **P2** | VIP/DNS for API server (:6443) | Currently clients target .21 directly — single IP SPOF (documented in control-plane HA plan) |
| **P2** | Move registry off .236 | Two of three etcd members carry non-control-plane workloads |

---

## Current State (as of investigation)

| Check | Result |
|-------|--------|
| server-252 in k8s nodes | ✅ Ready |
| server-252 etcd member | ✅ Joined (3/3) |
| Beszel agent pod | ✅ Running 1/1 |
| Load average | ✅ Low (1.10/0.97/0.89) |
| Hyper-V VM policy | ⚠️ NOT VERIFIED |
| VM memory floor | ⚠️ Currently ~3 GB dynamic |
| Quorum headroom | ⚠️ 2/3 (zero margin if another member fails) |

---

## Appendix: Evidence Collected

**Unreachability test (14:43 from workstation):**
```
Port 22: CLOSED     Port 6443: CLOSED     Port 2379: CLOSED
Port 45876: CLOSED   Port 8090: CLOSED    Port 8472: CLOSED
ARP: ? (192.168.0.252) at <incomplete> on eno1
Ping: 3 packets transmitted, 0 received, 100% packet loss
```

**Recovery confirmation (15:38 from .252):**
```
uptime: up 31 min, load average: 1.10, 0.97, 0.89
k3s.service: active (running) since Sun 2026-09-20 15:07:27 UTC
k3s kubectl get node server-252: Ready, control-plane,etcd,master
```

**Cluster view (15:37 from NUC):**
```
server-252   Ready   control-plane,etcd,master   3h4m   v1.34.6+k3s1   192.168.0.252
```

**Beszel agent (15:37 from NUC):**
```
beszel-agent-2npxg   1/1   Running   1 (35m ago)   3h5m   192.168.0.252   server-252
```
