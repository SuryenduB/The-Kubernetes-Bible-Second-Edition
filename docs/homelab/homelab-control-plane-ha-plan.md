# Homelab Control-Plane HA Plan — Eliminating the NUC Single Point of Failure

**Status**: ✅ EXECUTED 2026-09-20 — achieved with different hosts than planned (see "Implementation status")  
**Author**: Kilo (on behalf of suryendub)  
**Date**: 2026-09-19  
**Combines**: `docs/homelab/K3s_Homelab_Template.md` • `docs/operations/k3s-control-plane-ha-runbook.md` • `docs/operations/cluster-resilience-2026-09-06.md` • `docs/homelab/backups/Backup_Strategy.md`

---

## Implementation status (2026-09-20)

The goal of this plan - a three-member embedded-etcd control plane - is **live**. The
hosts differ from the ones assumed in §2, so the sections below are kept as the original
analysis, not as instructions.

| Planned | Actual |
|---------|--------|
| NUC = only server, migrate to etcd | Done 2026-09-19: NUC runs `/usr/local/bin/k3s server` with **no flags**; the SQLite store was migrated (`server/db/state.db.migrated`) and it now boots etcd ("Managed etcd cluster bootstrap already complete and initialized") |
| `192.168.0.249` = 2nd server | **Never existed on this LAN** (no ping, no registry on `:5000`). The 2nd server is **`server-236`** (joined 2026-09-19) |
| `192.168.0.236` wiped to Linux, registry relocated to `.249` | **Registry stay-put**: `.236` is Ubuntu 24.04 (not Windows) and still serves `192.168.0.236:5000` (4 repos), now **co-hosted on the control-plane node `server-236`** |
| 3rd server = `.236` | 3rd server is **`server-252`** (Hyper-V VM `k3s-master`, Ubuntu 20.04, 2 vCPU / 2 GB), joined 2026-09-20 |
| ThinkCentre worker (Phase 4/5) | Not started - out of scope here |

### Verified state

```text
$ kubectl get nodes
nuc          Ready  control-plane,etcd,master  v1.34.6+k3s1  192.168.0.21
server-236   Ready  control-plane,etcd,master  v1.34.6+k3s1  192.168.0.236
server-252   Ready  control-plane,etcd,master  v1.34.6+k3s1  192.168.0.252

$ etcdctl member list          # 3 members, all "started"
$ etcdctl endpoint health      # .21, .236, .252 -> all true
```

Quorum was proven, not assumed: with `server-252` stopped, `kubectl get --raw=/readyz`
still returned `ok` from `nuc` (2 of 3 members), and the member rejoined cleanly
(`EtcdIsVoter=True`, node `Ready`) on restart.

### Follow-up incident: `server-252` went offline (~15 min after joining)

The Hyper-V VM holding `server-252` disappeared at the **hypervisor level** shortly after
the successful join and the failover test: no ICMP reply, and ports 22/6443/2379/8472 all
closed. The cluster was unaffected because quorum is 2 of 3:

```text
nuc          Ready    control-plane,etcd,master   <- alive
server-236   Ready    control-plane,etcd,master   <- alive
server-252   NotReady control-plane,etcd,master   <- dead member, retained
```

- `kubectl get --raw=/readyz` -> `ok` while `server-252` was down.
- `etcdctl endpoint health --endpoints=https://192.168.0.252:2379` -> `false`
  (context deadline exceeded), while `.21`/`.236` stayed `true`.
- **No Longhorn replica had been placed on `server-252`** (`replicas.longhorn.io` with
  `nodeID=server-252`: 0), so its loss affected no volume.
- The member was deliberately **not removed** from etcd: it holds no data the cluster needs
  to forget, and removing it while only two members are alive would drop quorum tolerance
  to zero. Its `node-role.kubernetes.io/master` label is still present, so it will come back
  as a master on rejoin.

To restore the third master: start the `k3s-master` VM on its Hyper-V host. The unit is
enabled (`systemctl is-enabled k3s` -> `enabled`), so K3s starts on boot and the existing
etcd member rejoins with its own data directory - no re-install, no new token.

Open question for the host owner: why the VM stopped. It is a 2 vCPU / 2 GB Ubuntu 20.04
guest (kernel 5.4) with **Hyper-V dynamic memory** (observed growing 1.9 -> 2.4 GB under
K3s) and `unattended-upgrades` active - a combination known to hang on older Hyper-V
integration drivers. Recommended hardening before relying on it: give the VM static RAM
(4 GB), update the kernel/Hyper-V integration services, and set the VM's automatic stop
action to *Restart* rather than *Save state*, so a guest panic does not look like a power-off.

Cleanup owed when the VM returns (files were staged in `/tmp` on the guest for the join and
the cleanup could not run because the host went offline):
`rm -f /tmp/install-k3s-252.sh /tmp/launch-252.sh /tmp/k3s-install.log /tmp/sshp-test.txt`
(the first two contain the server token and the sudo password).


### Deviations worth knowing

1. **`.236` and `.252` are not control-plane-only.** `.236` also serves the local Docker
   registry, and `.252` was auto-registered in Longhorn (`allowScheduling: true`, default
   disk `/var/lib/longhorn`, `storageReserved` 26.6 GB) despite being a 2 GB VM. Acceptable
   for a homelab, but it means two of the three etcd members share their fate with a
   non-control-plane workload. Consider `kubectl -n longhorn-system patch node.longhorn.io
   server-252 --type merge -p '{"spec":{"allowScheduling":false}}'` if the VM must stay lean.
2. **`server-252` version floor.** Ubuntu 20.04 / kernel 5.4 is on the K3s v1.34 support
   matrix, and K3s sets kubelet `FailSwapOn=false`, so the existing 2 GB swap file was left
   in place. The VM has Hyper-V dynamic memory (it grew 1.9 -> 2.4 GB under k3s) with
   ~1.1 GB available; bump the VM to 4 GB if etcd ever shows memory pressure.
3. **Client endpoint still single-IP (§Phase 3.1 is the real remaining SPOF).** Every
   kubeconfig/monitor uses `https://192.168.0.21:6443`. Server-side quorum survives losing
   `nuc`; client access does not until a VIP/DNS name spans all three servers.
4. **Power tooling had to be fixed** (the reason §7's inventory update mattered):
   `WindowsLab/shutdown_homelab.ps1` matched a *single* master, so with several control-plane
   members the others were treated as workers and powered off **before** the master - which
   spends etcd quorum mid-run and kills the API the script itself depends on. It now
   excludes every control-plane node from the worker list and powers the control plane off
   last (`nuc` last of all, because clients/kubectl target `.21`). Its Longhorn detach gate
   is skipped with a warning only when the API is already unreachable, so a full shutdown
   still completes.
5. **Minimal mode must keep a control-plane majority.** `WindowsLab/homelab-nodes.json`
   now registers `server-236`/`server-252`, so `Stop-K3sHomelab-Minimal.ps1` would otherwise
   power them off and leave `nuc` alone = **no quorum**. All three masters are therefore in
   `survivors`.

### Inventory changes applied

`WindowsLab/homelab-nodes.json`: `expectedNodes` 9 -> 11; `server-236` moved from
`external.registry` to `nodes` (role `control-plane`, `neverCordon: true`); `server-252`
added (role `control-plane`, `neverCordon: true`); `survivors` extended with both masters.

### Still open

- VIP/DNS for `:6443` and repointing kubeconfigs, WindowsLab scripts, Uptime Kuma (§Phase 3.1).
- `WindowsLab/Upgrade-K3sCluster.ps1` has a hard-coded node list (`workers + nuc`) and picks
  the service name as `if ($n -eq "nuc") { "k3s" } else { "k3s-agent" }`; the two new servers
  are absent, so a future upgrade would leave them (and their `k3s server` unit) behind.
- ThinkCentre worker join and its Podman workload migration (§5).

---

## 1. Executive Summary

> ⚠️ **Superseded by "Implementation status" above.** Kept for the reasoning and the quorum
> math; the host names in it (`.249`, Windows `.236`) were never what got built.

`nuc` (192.168.0.21) is the **only** K3s server. A single point of failure: if NUC
fails, the Kubernetes API at `192.168.0.21:6443` is unavailable until it is restored.

This plan brings two additional K3s servers online — **192.168.0.249** (a new Ubuntu
host) and **192.168.0.236** (HP-1 / DESKTOP-32DRFM7, currently the Windows Docker-registry
box — to be repurposed after the registry is relocated) — for a **3-server embedded-etcd
quorum**. Three servers tolerate the loss of any one (quorum = 2 of 3), which closes the
SPOF.

> **Why three, not two?** K3s embedded etcd requires an odd member count. Two servers
> tolerate *zero* failures (lose either → no quorum). See
> `docs/operations/k3s-control-plane-ha-runbook.md:14-20` and §8.1 for the quorum math.

---

## 2. Current State Assessment

### 2.1 Cluster (`docs/homelab/K3s_Homelab_Template.md:38-44`)

| Metric | Value |
|--------|-------|
| K3s version | v1.34.5+k3s1 (NUC server) / v1.34.6+k3s1 (workers) |
| Nodes | 9 K3s nodes + 1 external (`registry` at .236, Windows) |
| Control-plane | `nuc` — the only server |
| CNI | Flannel (default) |
| Storage | Longhorn (prod) + QNAP NAS (bulk/backup) |
| Flat LAN | 192.168.0.0/24 |

### 2.2 Node inventory (`WindowsLab/homelab-nodes.json`)

| Node | IP | Role today | OS | Notes |
|------|----|-----------|----|-------|
| `nuc` | 192.168.0.21 | control-plane (only) | Ubuntu 24.04 | `neverCordon`/`neverPowerOff` |
| `kubernetes1` | 192.168.0.19 | worker | Ubuntu 24.04 | healthy, 455 G disk |
| `kubernetes2` | 192.168.0.20 | worker | Ubuntu 24.04 | — |
| `kubernetes3`–`8` | .22–.27 | workers | Ubuntu/Debian | — |
| **192.168.0.236** | 192.168.0.236 | **external** | Windows (HP-1) | **Local Docker registry (port 5000)** — to be repurposed |
| **192.168.0.249** | 192.168.0.249 | ⛔ not yet in JSON | Ubuntu (new) | **2nd control-plane target** |
| **ThinkCentre** | (LAN, discoverable) | — | Windows + Podman | unjoined; Podman workloads to migrate (§5) |

### 2.3 The two new control-plane hosts

| Host | IP | Source |
|------|----|--------|
| `.249` | 192.168.0.249 | New Ubuntu 24.04 box, on the flat LAN, ready for K3s |
| `.236` | 192.168.0.236 | HP-1 (DESKTOP-32DRFM7). Currently hosts the local Docker registry; will be wiped to Linux and promoted to the 3rd server after the registry is relocated (§4.1) |

### 2.4 SPOF root cause (`cluster-resilience-2026-09-06.md:54-64`)

> "The cluster currently has one K3s server: `nuc`. Surviving loss of NUC requires
> host-level K3s conversion or reinstallation of at least two additional servers
> using the same server token, with embedded-etcd quorum."

The `k3s-control-plane-ha-runbook.md:71-77` was previously **not performed** because
host SSH/console access was unavailable. `.249` and `.236` are now ready on-LAN hosts
to close that gap.

---

## 3. Objective & Design Decision

**Bring 3 K3s servers online** — NUC + `.249` + `.236` — with embedded etcd, so the
cluster survives the loss of any single control-plane node.

**Server promotion path chosen by the user**: NUC (.21) is already a server; `.249` and
`.236` become the 2nd and 3rd servers. No existing Ubuntu worker (`kubernetes1`–`8`) needs
promotion. The ThinkCentre (Windows+Podman) is joined as a **worker** in Phase 5 to host
its existing Podman workloads inside Kubernetes.

**Constraint**: K3s server requires Linux.
- `.249` is already Ubuntu → install K3s server directly.
- `.236` is Windows → **wipe to Linux** (Ubuntu 24.04) after relocating the registry (§4.1).
- ThinkCentre is Windows → for control-plane it would also need Linux, but the user has
  chosen `.249`/`.236` for the control plane, so the ThinkCentre joins as a **worker**
  (K3s agent), which still works on a Linux host or via a lightweight Linux VM.

> ⚠️ A K3s server cannot run on macOS or on a Windows host directly — the kubelet,
> containerd, and embedded etcd have no supported macOS/Windows control-plane build.
> A worker agent likewise needs Linux; to join the ThinkCentre while keeping Windows, run
> a lightweight Linux VM (Multipass/colima). That is optional and separate from the
> control-plane HA fix in this plan.

---

## 4. Pre-flight + Prerequisites (run from workstation)

These must be green **before** touching NUC/.249/.236:

```bash
# 1. K3s version on the control plane — all servers must match this
sudo k3s --version        # on NUC; e.g. v1.34.5+k3s1  (NOT the worker v1.34.6)

# 2. Server token (protected — never commit to git or paste into logs)
sudo cat /var/lib/rancher/k3s/server/node-token   # server join token
# Store in PowerShell SecretStore: k3s-server-token  (docs/homelab/how-to-manage-homelab-power.md §2)

# 3. Control-plane backup is healthy (Backup_Strategy.md §2)
pwsh -File WindowsLab/Restore-K3sCluster.ps1 -ListOnly   # latest snapshot present

# 4. All Longhorn volumes healthy (no faulted/detached replicas)
kubectl -n longhorn-system get volumes -o json | \
  jq -r '.items[] | select(.status.state!="attached" or .status.robustness!="healthy") | .metadata.name'

# 5. Ports open between the three planned servers (runbook §Preconditions #4)
#    TCP 6443 (API), 2379/2380 (embedded etcd)
for ip in 192.168.0.21 192.168.0.249 192.168.0.236; do
  nc -z  $ip 6443 && echo "$ip:6443 OK"  || echo "$ip:6443 FAIL"
  nc -z  $ip 2379 && echo "$ip:2379 OK"  || echo "$ip:2379 FAIL"
done
```

### 4.1 Relocate the Docker registry off .236

`.236` (HP-1) hosts `192.168.0.236:5000`, the local Docker registry that all nodes use
(template §Local Docker Registry). Wiping it to Linux destroys that registry, so it must
move first.

**Relocation target** (`.236` will be reinstalled, so co-locate the registry on `.249`
first — `.249` is a brand-new Linux box with available resources and avoids introducing
a second fresh host):

```bash
# On .249 (Ubuntu) — run a standalone Docker registry
sudo apt update && sudo apt install -y docker.io
sudo docker run -d -p 5000:5000 --restart=always --name registry -v /opt/registry:/var/lib/registry registry:2

# Mirror the existing registry image set
# (copy tags from 192.168.0.236:5000 to 192.168.0.249:5000; sailpoint-iiq:8.5, mysql:8.0, etc.)
```

Then **point the cluster at `.249:5000`** instead of `.236:5000`:
- The image-build helper `k3s-build.sh:31` hard-codes `192.168.0.236:5000` — update it to `.249`.
- `registries.yaml` on every node points at `.236:5000` (see
  `docs/homelab/how-to-audit-homelab.md:69-75`); the `registry-fixer` DaemonSet
  (`kubernetes-manifests/registry-fixer.yaml`) rewrites this file cluster-wide, so update
  the registry IP in that manifest and re-apply so every node trusts `.249:5000`.
- Update Tailscale/ingress references that hard-code `.236` where they mean the registry
  (not the node).

> ✅ Gate: all nodes can `curl -s http://192.168.0.249:5000/v2/_catalog` and image pulls
> succeed. Only then proceed to reprovision `.236`.

---

## 5. Phase-by-Phase Plan

### Phase 1 — Bring `.249` up as the 2nd K3s server

`.249` is already Ubuntu. Install K3s server joining NUC's existing server token:

```bash
# On 192.168.0.249, as root
curl -sfL https://get.k3s.io | \
  K3S_URL=https://192.168.0.21:6443 \
  K3S_TOKEN='<server-token from §4 step 2>' \
  INSTALL_K3S_VERSION='v1.34.5+k3s1' \
  sh -s - server
```

**Validate** (runbook §Migration outline "After each host joins"):

```bash
# From a workstation with kubectl
ETCDCTL_API=3 sudo ETCDCTL_ENDPOINT="https://127.0.0.1:2379" etcdctl member list   # expect 2 members
kubectl get nodes -o wide                                                           # .249 = server role
kubectl get --raw='/readyz?verbose'
kubectl -n longhorn-system get nodes.longhorn.io                                     # .249 registered
```

### Phase 2 — Reprovision `.236` (HP-1) as the 3rd K3s server

1. **Wipe HP-1 to Ubuntu 24.04** (the registry already lives on `.249` from Phase 0/§4.1).
2. **Static IP** `192.168.0.236` (reuse the existing address so DNS/SSH/known_hosts stay
   stable), gateway `.1`, DNS `192.168.0.99` (Netgear) or upstream.
3. **Install K3s server** joining the pool:

```bash
# On 192.168.0.236, as root
curl -sfL https://get.k3s.io | \
  K3S_URL=https://192.168.0.21:6443 \
  K3S_TOKEN='<server-token from §4 step 2>' \
  INSTALL_K3S_VERSION='v1.34.5+k3s1' \
  sh -s - server
```

**Validate** the 3-member quorum:

```bash
ETCDCTL_API=3 sudo ETCDCTL_ENDPOINT="https://127.0.0.1:2379" etcdctl member list   # expect 3 members
kubectl get nodes -o wide | grep -E 'nuc|192.168.0.2(49|36)'
kubectl -n kube-system get pods -o wide
kubectl -n longhorn-system get nodes.longhorn.io
```

### Phase 3 — Stabilise the cluster post-HA

1. **Stable API endpoint** (runbook §Migration outline, lines 53-54: *"Do not point
   clients at a single server IP as the long-term endpoint."*):
   - **Option A (quick)**: floating VIP e.g. `192.168.0.30` on NUC with keepalived
     (move it between servers on failure).
   - **Option B (Tailscale)**: register `k3s-api.tail35421d.ts.net` and alias it to all
     three server Tailscale IPs; update the `apiServer` in `homelab-nodes.json` and every
     `kubeconfig`.
   - **Option C (document only)**: keep `kubectl --server https://192.168.0.21:6443`
     but record all three server IPs for manual failover.
2. **Update `homelab-nodes.json`** — see §7. This propagates to
   `Start-K3sHomelab.ps1`, `Stop-K3sHomelab-Minimal.ps1`, `Run-K3sAudit.ps1` via
   `WindowsLab/HomelabNodes.psm1`.
3. **Controlled-failover test** (runbook lines 66–69): reboot NUC; confirm the API
   endpoint, Longhorn attachment, and each app monitor survive on `.249` + `.236`.
   Restore NUC and confirm quorum returns to 3.
4. **Re-validate backups** (`docs/homelab/backups/Backup_Strategy.md` §2): the next
   02:00 run of `WindowsLab/k3s-backup-to-nas.sh` must still `integrity_check: ok`.
   `k3s etcd-snapshot` is a good belt-and-suspenders before the NUC reboot:
   ```bash
   sudo k3s etcd-snapshot --snapshot-dir /var/lib/rancher/k3s/server/db/
   ```

### Phase 4 — Join the ThinkCentre as a worker + migrate Podman workloads

The ThinkCentre (Windows + Podman) is currently unjoined. With the control-plane
SPOF already solved by `.249`/`.236`, join it as a **worker** and migrate its existing
Podman containers into Kubernetes.

> K3s agent also requires Linux. To keep Windows on the ThinkCentre, run a lightweight
> **Multipass** Ubuntu VM; otherwise wipe to Ubuntu as in Phase 2.

1. **Inventory the Podman stack** (on the ThinkCentre, PowerShell):
   ```powershell
   podman ps -a --format "table {{.Names}}`t{{.Image}}`t{{.Ports}}`t{{.Status}}" > thinkcentre-podman-inventory.txt
   podman volume ls
   podman port -a
   ```
2. **Pick a target namespace** (reuse an existing one, e.g. `media` or `server-management`).
3. **Mirror images** to the local registry if the cluster is offline for the source:
   ```bash
   podman pull <image>
   podman tag  <image> 192.168.0.249:5000/<app>:v1    # registry now on .249
   podman push 192.168.0.249:5000/<app>:v1
   ```
4. **Re-declare as a Deployment** (template §Local Docker Registry +
   `homelab-media-deployment-plan.md` patterns); add Tailscale
   `tailscale.com/expose` annotations if MagicDNS access is needed:
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: thinkcentre-app
     namespace: media
   spec:
     replicas: 1
     selector: { matchLabels: { app: thinkcentre-app } }
     template:
       metadata: { labels: { app: thinkcentre-app } }
       spec:
         containers:
         - name: app
           image: 192.168.0.249:5000/thinkcentre-app:v1
           ports: [{ containerPort: 8080 }]
   ```
5. **Join the ThinkCentre worker** to the cluster (agent install) — `homelab-nodes.json`
   gets a worker entry at §7. After join, `kubectl get nodes -w` should show it `Ready`.

---

## 6. Risk Register & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Registry relocation breaks image pulls | Medium | Build/deploy fails | Validate `curl 192.168.0.249:5000/v2/_catalog` from all nodes **before** wiping `.236` |
| `.249`/`.236` static IP conflicts | Medium | etcd peer unreachable | `.249` is new/unused; `.236` is released by the registry move. Verify with `arping` before install. |
| Server token leaked to git/logs | High | Cluster-wide compromise | Read token from `PowerShell SecretStore` only; never paste where it gets logged. (`how-to-manage-homelab-power.md` §2.2) |
| etcd quorum lost during 1→2→3 transition | Low | API downtime | Add one server at a time; `etcdctl member list` after each. Never reprovision NUC while quorum is already degraded. |
| K3s version skew between servers | Medium | Split brain / join fails | Pin `INSTALL_K3S_VERSION='v1.34.5+k3s1'` — the **NUC server** version, not the worker `v1.34.6`. |
| `registry-fixer` overwrites `registries.yaml` | High | New nodes can't trust local registry | Update `kubernetes-manifests/registry-fixer.yaml` to `.249:5000` and re-apply before joining servers. |
| HP-1 has less RAM/CPU than assumed | Low | Control-plane slow | Confirm `.236` specs match NUC class; K3s control plane needs ~2 vCPU + 2 Gi minimum. |

---

## 7. Node Inventory Update (homelab-nodes.json)

Apply **after Phase 2** (all servers confirmed healthy). Two new nodes; `.236` moves from
"external" to the server list; expectedNodes 9 → 11 (9 + `.249` + `thinkcentre`; `.236`
already existed in `external` and is now reclassified).

```jsonc
// homelab-nodes.json — changes only
{
  "cluster": {
    "expectedNodes": 11,                 // was 9 (+ .249, + thinkcentre)
    "apiServer": "https://192.168.0.21:6443",  // update to VIP/DNS in §Phase 3.1 before long-term use
  },
  "survivors": ["nuc", "kubernetes5", "kubernetes7"],   // unchanged

  "nodes": [
    // ... existing nuc, kubernetes1..8 unchanged ...

    // NEW — 2nd control-plane server
    {
      "name": "server-249",
      "ip": "192.168.0.249",
      "role": "control-plane",
      "os": "Ubuntu 24.04",
      "sshUser": "suryendub",
      "neverCordon": true,
      "neverPowerOff": false,
      "notes": "2nd K3s server (embedded etcd). Also hosts the relocated Docker registry on :5000."
    },
    // RECLASSIFIED — HP-1 was 'external' registry; now a control-plane server
    {
      "name": "server-236",
      "ip": "192.168.0.236",
      "role": "control-plane",              // was external "registry"
      "os": "Ubuntu 24.04",                 // was Windows
      "sshUser": "suryendub",
      "neverCordon": true,
      "neverPowerOff": false,
      "notes": "3rd K3s server (embedded etcd). Repurposed from Windows registry box after registry moved to .249."
    },
    // NEW — ThinkCentre worker (Phase 4)
    {
      "name": "thinkcentre",
      "ip": "<discovered-LAN-ip>",
      "role": "worker",
      "os": "Ubuntu 24.04",                 // or 'Ubuntu 24.04 (Multipass VM)' if Windows retained
      "sshUser": "suryendub",
      "neverCordon": false,
      "neverPowerOff": false,
      "notes": "Joined as worker. Podman workloads migrated to k8s Deployments (§5 Phase 4)."
    }
  ],

  "external": [
    // .236 removed from here (now a control-plane server)
    { "name": "nas", "ip": "192.168.0.128", "role": "nas", "os": "QNAP QTS", "notes": "NFS backup target." }
    // NOTE: local registry now on .249:5000, no longer a separate external host
  ]
}
```

---

## 8. Verification

```bash
# 1. Three members in the embedded-etcd pool
ETCDCTL_API=3 sudo ETCDCTL_ENDPOINT="https://127.0.0.1:2379" etcdctl member list   # expect 3

# 2. All three servers Ready + server role
kubectl get nodes -o wide | grep -E 'nuc|server-249|server-236'

# 3. Quorum survives one server loss — controlled-failover test (§5 Phase 3.3)
#    Reboot nuc, confirm kubectl still works; check Longhorn + apps; restore NUC.

# 4. Cluster still pulls from the relocated registry
curl -s http://192.168.0.249:5000/v2/_catalog
kubectl get nodes -o json | jq -r '.items[].metadata.name' | while read n; do
  ssh "$n" "curl -s http://192.168.0.249:5000/v2/_catalog >/dev/null && echo $n OK || echo $n FAIL"
done

# 5. Control-plane backup still integrity-checks (Backup_Strategy.md §2)
pwsh -File WindowsLab/Restore-K3sCluster.ps1 -ListOnly   # latest snapshot present & restorable
```

**Success criteria**
- 3 control-plane nodes (`nuc`, `server-249`, `server-236`) all `Ready` with the `server` role.
- `etcdctl member list` reports 3 healthy members.
- Cluster survives a reboot of **any one** server with no loss of API or Longhorn volume
  attachment (PDBs respected — template §High Availability PDBs).
- The Docker registry at `192.168.0.249:5000` is reachable from all nodes and image pulls succeed.
- `WindowsLab/Restore-K3sCluster.ps1 -ListOnly` shows a recent, restorable control-plane snapshot.

### 8.1 Quorum note — embedded etcd vs external datastore

With **embedded etcd** (the topology above) quorum is mandatory: 3 servers tolerate 1
loss; a second simultaneous server loss stops the API until the failed server returns
or you run `k3s server --cluster-reset` to rebuild the pool from a single survivor
(emergency, loses the etcd history of removed members). Always snapshot before a
controlled failover: `sudo k3s etcd-snapshot`.

**Alternative that removes the odd-number rule**: an **external datastore** via
`--datastore-endpoint='mysql://...' or postgres://...`. The cluster already runs MySQL
and PostgreSQL for iiqstack, so all three servers could point at one external HA
datastore and avoid embedded-etcd quorum math. That is a larger change (DB-side HA,
connection-string rotation) and is **out of scope for this plan** — embedded etcd is
sufficient for this homelab's "tolerate one server loss" goal. Revisit if you later want
4+ servers or to tolerate 2 simultaneous losses.

---

## 9. References (existing docs this plan inherits from)

| Doc | Relevance |
|-----|-----------|
| `docs/homelab/K3s_Homelab_Template.md` | Cluster/node inventory, storage, Tailscale, PDBs, local registry |
| `docs/operations/k3s-control-plane-ha-runbook.md` | Authoritative 3-server embedded-etcd install recipe (lines 14-55) |
| `docs/operations/cluster-resilience-2026-09-06.md` §Control-plane HA | States the single-server limitation explicitly |
| `docs/homelab/backups/Backup_Strategy.md` §2 | Pre-change control-plane backup + restore validation |
| `docs/homelab/how-to-manage-homelab-power.md` §2 | SecretStore credential retrieval |
| `WindowsLab/homelab-nodes.json` | Node identity source-of-truth (must be updated per §7) |
| `docs/homelab/how-to-audit-homelab.md` §Verify registry | registries.yaml / local-registry trust for new nodes |
| `kubernetes-manifests/registry-fixer.yaml` | DaemonSet that rewrites registries.yaml cluster-wide (update IP to .249) |
| `k3s-build.sh:31` | Hard-coded `192.168.0.236:5000` registry ref to update |
