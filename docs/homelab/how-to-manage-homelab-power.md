# How to Manage K3s Homelab Cluster Power

This guide walks you through safely starting and shutting down the K3s homelab cluster. It covers secure password management, non-interactive remote commands, and executing tasks in the background without terminal suspension.

---

## Prerequisites

Before executing power management scripts, ensure your orchestration host (e.g., your local machine) has the necessary modules and utilities installed.

### 1. Install PowerShell SecretStore Modules
To securely store passwords without hardcoding them in scripts, install the Microsoft SecretManagement modules:
```powershell
# Install modules globally
Install-Module -Name Microsoft.PowerShell.SecretManagement -Scope CurrentUser -Force
Install-Module -Name Microsoft.PowerShell.SecretStore -Scope CurrentUser -Force
```

### 2. Install sshpass
For non-interactive SSH password authentication in background tasks, install `sshpass` on your host:
* **macOS (via Homebrew):**
  ```bash
  brew install hudochenkov/sshpass/sshpass
  ```
* **Debian/Ubuntu:**
  ```bash
  sudo apt-get install -y sshpass
  ```

---

## Step 1: Secure Credential Setup

Rather than using plaintext credential files (`cred.xml`), the scripts are configured to retrieve credentials from the PowerShell SecretStore.

### 1. Configure the SecretStore for Non-Interactive Automation
Run the following command to allow background scripts to retrieve secrets without prompting for a master vault password:
```powershell
Set-SecretStoreConfiguration -Authentication None -Interaction None -Confirm:$false
```

### 2. Register the Sudo Password
Store your homelab sudo password (`558068`) under the secret key `k3s-homelab-sudo`:
```powershell
# Store the password securely in the default LocalStore vault
Set-Secret -Name "k3s-homelab-sudo" -Secret "558068"
```

### 3. Per-Node Login Identities (case-sensitive)

The sudo password is only half of a poweroff: the scripts also need the right **login account per
node**. That identity comes from `WindowsLab/homelab-nodes.json` (`sshUser`), because it is *not*
the same everywhere and Linux usernames are case-sensitive:

| Nodes | `sshUser` | Notes |
|---|---|---|
| `nuc`, `kubernetes1`–`kubernetes8-debian` | `suryendub` | Ubuntu workers + the primary control plane |
| `server-236` (192.168.0.236) | `SuryenduB` | **Capital S matters** - `suryendub` is rejected |
| `server-252` (192.168.0.252) | `SuryenduB` | Same Hyper-V/Windows-style account (`SuryenduB`) |

`shutdown_homelab.ps1` (v10.0) resolves the identity per node and *proves* it before powering
anything off: it tries the registry spelling plus its lowercase and capitalised forms, keeps the
one that authenticates, and then verifies that the stored sudo password is accepted. A node whose
credential fails is named in the pre-flight output, in the summary, in the JSON report
(`credentialFailures`) and in the exit code.

Check every node's credential on demand (powers nothing off, exit `1` if any node cannot be
authenticated):

```bash
pwsh -File WindowsLab/shutdown_homelab.ps1 -VerifyCredentials -Force
```

```text
--- Pre-flight: SSH credentials ---
  [+] kubernetes1 (192.168.0.19): authenticated as 'suryendub' and sudo accepted.
  ...
  [+] server-236 (192.168.0.236): authenticated as 'SuryenduB' and sudo accepted.
  [-] server-252 (192.168.0.252): already unreachable on TCP 22 - no credential needed.
```

If a host is re-imaged with a different account name, update its `sshUser` in
`homelab-nodes.json` - never hardcode it in a script. `Stop-K3sHomelab-Minimal.ps1` resolves the
same registry field for its poweroff step.

---

## Step 2: How to Start the Cluster

> **Important:** `Start-K3sHomelab.ps1` restores **capacity** (uncordon + reconcile). It does **not**
> power the hardware on - there is no Wake-on-LAN in it. Power the physical nodes on first
> (power buttons), or run the script with `-WaitForNodesMinutes <n>` so it waits for nodes
> that are still booting.

1. Physically power on the nodes you want running, then execute the recovery (dry-run first is free):
   ```powershell
   pwsh -File WindowsLab/Start-K3sHomelab.ps1 -DryRun
   pwsh -File WindowsLab/Start-K3sHomelab.ps1 -RepairStorage
   ```
2. Monitor node convergence:
   ```bash
   kubectl get nodes -w
   ```
3. Verify that all system pods are running:
   ```bash
   kubectl get pods -A
   ```

### Start script v2 (Start-K3sHomelab.ps1) reference

| Flag | Effect |
|---|---|
| `-DryRun` | Preview every action; writes a report, changes nothing. Safe to run any time. |
| `-RepairStorage` | Allow Longhorn repairs (recycle the CSI plugin on nodes with stale mounts; remove zombie Longhorn pods left on offline nodes). **Recommended for a standard recovery.** |
| `-RestartWorkloads` | Opt-in full serialized rolling restart (StatefulSets, storage-gated, one at a time, then Deployments). Off by default - uncordoning usually suffices. |
| `-Rebalance` | Redistribute movable workloads off overloaded nodes using Eviction-API drains (PodDisruptionBudgets respected, protected nodes skipped). |
| `-WaitForNodesMinutes <n>` | Wait up to N minutes for expected nodes to report Ready. |
| `-Force` | Acknowledge that restoring a faulted Longhorn volume from backup **discards every write made after that backup**, and let the restore phase run it. Needed to recover volumes whose last replica sat on a down `kubernetes1`-`kubernetes6` worker. |
| `-SkipFaultedVolumeRestore` | Detect and report faulted volumes even with `-Force`, but never delete/recreate them. |
| `-FaultedVolumeRestoreNodes <names>` | Override which down nodes trigger the restore phase (default: the `kubernetes1`-`kubernetes6` workers from the registry). |
| `-RestoreReplicaCount <n>` | Replica count written onto restored volumes (default `3`). |
| `-FailOnDegraded` | Exit `2` when degraded workloads remain (for automation). |

Faulted-volume restore: when a `kubernetes1`-`kubernetes6` worker is NotReady and a Longhorn
volume is `faulted` with no live replica left, the run names its newest backup. Without `-Force`
it stops there; with `-Force` it validates the restore manifest against the API server, deletes
the dead Longhorn volume and recreates it from that backup **under the same name**, then rebuilds
the PV/PVC that Longhorn removes along with the volume (marked `Retain` so a future deletion
cannot cascade into the claim again). Deleting a Longhorn volume also deletes its PV/PVC - the
script captures that binding up front and re-creates it, and scales any owning StatefulSet down
and back up so the controller cannot race in an empty replacement. There is no in-place repair
for a faulted volume - the backup is the recovery point.

> Recovered volumes come back **degraded** until Longhorn rebuilds their replicas; that converges
> on its own once the down workers return. If the down workers stay off, rebuild may never
> happen: the surviving disks have little headroom above their reserved space, so Longhorn
> reports `ReplicaSchedulingFailure` and the volumes stay at a single replica (no redundancy).

Exit codes: `0` healthy, `1` fatal, `2` completed-but-degraded (only with `-FailOnDegraded`).

Each run writes a transcript plus a machine-readable JSON report to `WindowsLab/logs/`
(`start-<timestamp>.log`, `start-report-<timestamp>.json`). Node identity and the
*kubernetes7 must never be powered off* rule live in `WindowsLab/homelab-nodes.json`
(loaded via `WindowsLab/HomelabNodes.psm1`) - do not hardcode node lists in the scripts.

---

## Step 3: How to Stop the Cluster Gracefully

Shutting down the cluster systematically cordons and drains the nodes (migrating active workloads and respecting Pod Disruption Budgets) before sending a remote `poweroff` instruction.

### 1. Run the Shutdown Script in the Background
Because draining nodes and ssh timeouts can take several minutes, run the command in the background. 

> [!IMPORTANT]
> To prevent the background job from being suspended by the OS shell (Job Control `SIGTTIN`/`SIGTTOU` signals), you **must** redirect stdout/stderr to a log file and stdin from `/dev/null`:

```bash
pwsh -File WindowsLab/shutdown_homelab.ps1 -Force > shutdown.log 2>&1 < /dev/null &
```

### 2. Monitor Shutdown Progress
Follow the logs in real-time to track node cordoning, pod eviction, and power-off sequences:
```bash
tail -f shutdown.log
```

### 3. Flag reference (shutdown_homelab.ps1 v10.0)

| Flag | Effect |
|---|---|
| `-Force` | **Definitive shutdown.** Skips the confirmation prompt and runs unattended. It still honors the storage gates unless `-AllowDirtyPowerOff` is also given: degraded attached volumes refuse to start, and a node whose cleanliness cannot be proven is skipped and (see the finish gate below) takes the control plane with it. What *is* new since v9: a node whose drain merely overran its budget is no longer skipped blind - the **evidence gate** re-judges the actual safety invariant (below) and the node powers off when it is proven safe. Every poweroff is retried through an escalating ladder - `sudo poweroff` → `sudo shutdown -h now` → `sudo systemctl poweroff -i` - with a bounded SSH connect timeout, and success is judged by **reachability** (TCP 22 closes), so the `255` exit code of a *successful* poweroff is no longer reported as a failure. |
| `-ForceKernelPowerOff` | With `-Force`: adds a final kernel-level stage - `sysrq` sync + remount-ro + poweroff - for hosts that ignore every graceful stage (a hung systemd shutdown is the usual cause). It bypasses orderly service shutdown, so it is opt-in and only ever reached after the graceful stages fail. |
| `-CompletePendingNodes` | **Second-run completion mode** (ordinary standalone run, not combinable with other actions): for every registry worker it checks TCP 22 - already down costs nothing; otherwise it runs the evidence gate and powers the node off **only on positive proof of cleanliness** (0 Longhorn devices, 0 data mounts, only system containers running). Anything unproven is refused with the evidence named in the report. Use it when a previous shutdown stranded a worker and the API has since died, so drains can no longer run. Control-plane members are never touched here. |
| `-DryRun` | Prints the whole plan (read-only kubectl queries, no SSH, no prompts, no changes) - the safe way to rehearse. Lists the login identity that *would* be used per node but does not probe it (no password is resolved). |
| `-VerifyCredentials` | Credential check only: resolves the per-node login identity from the registry, proves the SSH login and that the stored sudo password is accepted (`sudo -k`, so a cached ticket cannot fake a pass), writes the transcript + JSON report, then exits. Powers nothing off, skips the degraded-storage gate, and exits `1` when any node has no usable credential. |
| `-SkipDrain` | Power the nodes off without draining workloads first. The evidence gate still protects each node individually. |
| `-ShutdownLocalMac` | Also power off the machine running the script (opt-in; kills your terminal and kubectl access mid-run). |
| `-Mode <Auto\|Dynamic\|Fallback>` | Node discovery: detect via the API, force the API, or use the registry list. |
| `-DrainTimeoutSeconds` / `-DetachTimeoutSeconds` | Per-node drain budget and Longhorn detach budget. Drain default **600 s since v10** (kubernetes5's argocd singletons were still terminating at grace 120 s when the old 300 s budget expired - the drain "failed" on time, not on safety). |
| `-PowerOffAttempts` | Poweroff attempts per node (default 3). The kernel stage, when enabled, is always the last attempt. |
| `-VerifyPowerOffSeconds` | How long to wait for a node to stop answering SSH after each attempt (default 45 s). |
| `-SshConnectTimeoutSeconds` | SSH connect timeout (default 15 s), so a hung host cannot stall the whole run. |

**Exit codes:** `0` = every target node was verified down (or the run was a dry run); `1` = at
least one node was skipped or is still answering after every stage, a credential failed, or any
recoverable error was recorded; `2` = the **finish gate shut** (see below): worker(s) are stranded
without proof of cleanliness and the control plane was **deliberately left running** so the
situation stays recoverable.

### 4. Error isolation (v9.3): one error never ends the run

A shutdown that stops at the first error is the worst possible outcome - part of the fleet down,
the control plane up, nothing explaining why. So the run is now split into independently failing
stages, and the whole of it lives in a `try/catch/finally`:

| Where an error happens | What the script does |
|---|---|
| One node's drain fails | With no `-Force` it is skipped (accidental-run behaviour). With `-Force` the **evidence gate** judges the node's actual state instead of trusting the drain exit code: proven clean → poweroff proceeds; unclean/unverifiable → skipped, and the finish gate (below) keeps the etcd members up. |
| One node's poweroff fails | That node is listed under `failed`; every other node is still processed. |
| Longhorn/API query fails | Reported as `UNKNOWN-API-FAILURE` (never as "healthy" or "clean" - see below). When the API is dead, the node-local SSH probe answers the same cleanliness question without it. |
| API discovery fails | Recorded in `errors`, falls back to the **complete** registry list (workers + control plane, primary last) and keeps going. |
| Any unexpected exception, in any phase | Caught, recorded, and the remaining work is skipped rather than half-done. |
| A worker still up when the etcd phase would start | **Finish gate**: one invariant re-check + one 2×-budget drain retry; if it cannot be resolved, the control plane is deliberately left running (exit `2`) instead of destroying the ability to finish the job. |
| A node flagged `neverPowerOff` reaches a target list | **Fatal by design** (that power-off cannot be undone): nothing is powered off, the reason is recorded, and `finally` still writes the report. |
| Degraded attached volumes without `-Force` | **Refuses to start** - a pre-flight gate, so nothing has been touched yet and there is no half-powered state to recover from. |

Whatever happens, the `finally` block still writes the transcript, the JSON report and the exit
code, so a failed run can always be explained afterwards:

```json
{
  "mode": "FALLBACK",
  "credentials": [ { "node": "server-236", "user": "SuryenduB", "status": "ok" } ],
  "credentialFailures": [],
  "errors": [
    { "context": "phase:discovery", "message": "API discovery failed (Auto mode): ... Using the registry node list instead." }
  ],
  "down": ["kubernetes1", "..."], "skipped": [], "failed": []
}
```

> Note the two silent-failure bugs this work fixed: `kubectl` prints its errors on stderr and exits
> non-zero, and piping that into `ConvertFrom-Json` yields `$null` **without throwing** - so an
> unreachable API used to look like an empty cluster, and worse, "no degraded volumes / no
> attachments" (which would have waved the storage gate through with live Longhorn attachments).
> Both helpers now check `$LASTEXITCODE` explicitly.

> ⚠️ The one thing `-Force` never overrides: a node flagged `neverPowerOff` in
> `WindowsLab/homelab-nodes.json` (`kubernetes7`, whose physical power switch is broken) is still
> refused, because that power-off is physically unrecoverable.

### 5. v10.0: the evidence gate, the finish gate, and the second run

Motivation - the 2026-10-17 kubernetes5 incident: its drain overran the 300 s budget while the
last pods (argocd singletons at grace 120 s) were still terminating, the storage gate refused a
dirty power-off, and then the control-plane phase powered the API off anyway. From that moment a
rerun could never finish the node: the fallback path cannot drain, and its detach gate reads
`UNKNOWN` while the API is down. The node could only be finished by hand over SSH. v10 turns that
manual procedure into default behaviour with three layers:

**1. The evidence gate (replaces drain-exit-code decisions).** A failed drain/detach is no longer
judged by exit codes alone - the actual safety invariant is asked directly:

- **API channel**: zero eligible (non-DaemonSet) Running/terminating pods on the node AND zero
  Longhorn `volumeattachment`s on it, live from kubectl.
- **Node-local channel** (once the API is gone): over SSH - `/dev/longhorn/` empty, `findmnt`
  shows no Longhorn data mounts, and every running container matches the system allowlist
  (Longhorn, CSI, svclb, kube plumbing, agents). One unrecognised container name → not clean.

| Situation | v9 behaviour | v10 default |
|---|---|---|
| Drain timed out, but node is actually empty | skip (or dirty poweroff with `-AllowDirtyPowerOff`) | **proven clean → poweroff proceeds** |
| Detach gate can't reach the API | poll kubectl to the timeout, then skip | SSH probe answers in seconds; clean → poweroff |
| Still unclean or unverifiable | skip | skip, with evidence logged to the transcript, summary and report |
| `-AllowDirtyPowerOff` | override | override (unchanged) |

**2. The finish gate (structural).** Before a single etcd member loses quorum, every worker is
TCP-probed. A worker still up gets one invariant re-check plus one 2×-budget drain retry; only a
worker that remains up **without proof of cleanliness** blocks the control-plane phase. In that
case the etcd members stay running (exit code `2`) and the summary says exactly which nodes are
stranded and why. Because the API never died, the plain rerun completes cleanly:

```bash
pwsh -File WindowsLab/shutdown_homelab.ps1 -Force > shutdown.log 2>&1 < /dev/null &
```

**3. `-CompletePendingNodes` (the post-mortem).** If the API *has* already died with a worker
stranded, reruns cannot help. This mode asks the node itself: TCP 22 closed → already down;
otherwise the node-local probe runs and **only a positively proven clean node is powered off**
(through the same escalation ladder). Unproven nodes are refused and named, with evidence. It
never touches control-plane members and cannot be combined with `-AllowDirtyPowerOff`
(powering off unproven nodes is what that switch exists for in the normal flow, and this mode
deliberately has no equivalent when nobody can verify storage):

```bash
pwsh -File WindowsLab/shutdown_homelab.ps1 -CompletePendingNodes
```

Every cleanup decision lands in the JSON report under `cleanliness`
(`{ node, verdict, channel, evidence }`), and stranded nodes under `strandedWorkers` +
`finishGateBlocked`, so the "why is this node still up" question is answerable without the
transcript.

Rehearse first (changes nothing):

```bash
pwsh -File WindowsLab/shutdown_homelab.ps1 -DryRun -Force -ForceKernelPowerOff
```

Definitive background shutdown, including the kernel stage for stubborn hosts:

```bash
pwsh -File WindowsLab/shutdown_homelab.ps1 -Force -ForceKernelPowerOff > shutdown.log 2>&1 < /dev/null &
```

An unattended `-Force` run must be able to resolve the sudo password without prompting: if neither
`WindowsLab/cred.xml` nor the `k3s-homelab-sudo` SecretStore entry is available, the script stops
before touching any node instead of sending an unauthenticated poweroff.

---

## Technical Details & Troubleshooting

### Cross-Platform Marshaling Support
When retrieving secrets from the SecretStore on non-Windows hosts, standard `.NET` marshaling using `PtrToStringAuto` can truncate UTF-16 strings because of Unix-specific null-byte string terminators. The power scripts solve this by forcing UTF-16 decoding using `PtrToStringUni`:
```powershell
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringUni(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
)
```

### Non-Interactive SSH Failures
If you see connection errors or password prompts in `shutdown.log`, verify that `sshpass` is accessible in your shell's `PATH`. The scripts automatically fall back to standard `ssh` if `sshpass` is missing, which will require an interactive terminal.

`Permission denied (publickey,password)` on one node only is almost always the **username case**,
not the password: `server-236` and `server-252` reject `suryendub` and only accept `SuryenduB`
(same password, `558068`). Set the correct `sshUser` in `WindowsLab/homelab-nodes.json` and confirm
with:

```bash
pwsh -File WindowsLab/shutdown_homelab.ps1 -VerifyCredentials -Force
```

A node that logs in but whose sudo is rejected is reported as `sudo-failed` - that is a *stale or
wrong* `k3s-homelab-sudo` secret, not a username problem; re-store it with `Set-Secret`.

### Embedded-etcd lineage check & rejoin (added 2026-10-17)

After a full-fleet power cycle, a control-plane node whose kubelet stays `NotReady` while the API
server is healthy has an **etcd lineage problem**, not a network problem. `etcd` cluster IDs never
change for a data directory, so a member whose embedded etcd branched off earlier (for example a VM
that kept running through the shutdown, or a rebuilt member whose data dir predates a restore) will
form raft connections but reject every message:

```
"msg":"request sent was ignored by remote peer due to cluster ID mismatch",
"local-member-cluster-id":"afb0a5e986f206a9"
```

**Ground truth:** `etcdctl` lives at `/usr/local/bin/etcdctl` on `nuc` (static v3.5.21, certs in
`/var/lib/rancher/k3s/server/tls/etcd/`):

```bash
etcdctl --endpoints https://127.0.0.1:2379 \
  --cacert .../etcd/server-ca.crt --cert .../etcd/server-client.crt --key .../etcd/server-client.key \
  member list -w table
```

If a node is *absent* from the member list yet identifies a *different* `local-member-cluster-id`
than the live leader's, it is a stale fork. Do **not** try to fix it with networking.

**Rejoin procedure (validated twice on 2026-10-17: server-236, server-252):**

1. Check the node's token matches the live cluster: `sha256sum /var/lib/rancher/k3s/server/token`
   on the member vs on `nuc`. If it differs/missing, plant the live token (`chmod 600`).
2. Guard disk space (`du -sm` of `server/db` + 200 MB headroom), then `systemctl stop k3s`.
3. Archive, never delete: `mv /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/server/db-backup-$(date +%Y%m%d-%H%M%S)`.
4. Point the bare `k3s server` unit at the live cluster via the env file its unit already reads
   (`EnvironmentFile=-/etc/systemd/system/k3s.service.env`):

   ```
   K3S_URL=https://192.168.0.21:6443
   K3S_TOKEN=<live token>          # only when the token file had to be planted
   ```

5. `systemctl daemon-reload && systemctl restart k3s`. Success markers in the journal: registry
   ranges at the *live* revision, `Reconciliation of ETCDSnapshotFile`, cloud-controller-manager
   lease election - and on `nuc`, the member list grows by one `started` row with the right peer
   address. Settle on `kubectl get nodes` reporting `Ready`.
6. Repeat per node, one at a time; the serving members stay up throughout. End state: all member
   rows `started` in one raft term, `endpoint health` green for every member.

After server-236/252 rejoined, `K3S_URL` is now part of their systemd env - a later shutdown of all
three is safe (quorum fully restart-able again), but **any single member must never be left running
while the other two reboot**: that is what forked the lineage in the first place. The stale forks
are archived in-place and may be deleted once a week passes without a rollback need
(`server-236: db-backup-20261017-202456`, `server-252: db-backup-20261017-182829`).
