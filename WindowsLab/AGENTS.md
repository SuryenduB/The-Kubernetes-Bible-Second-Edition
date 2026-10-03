# Memory — `WindowsLab/`

## Project Overview

This directory contains **two unrelated projects**. Do not assume a dependency between them.

1. **K3s homelab power tooling** (`Start-K3sHomelab.ps1`, `shutdown_homelab.ps1`,
   `Stop-K3sHomelab-Minimal.ps1`, `Restore-K3sCluster.ps1`, `Repair-ContainerCreating-Pods.ps1`,
   `HomelabNodes.psm1`, `homelab-nodes.json`, Beszel/NAS helpers). Docs:
   `docs/homelab/how-to-manage-homelab-power.md`, `docs/homelab/`, `docs/operations/`.
2. **AD / IAM lab** (`AutomatedLabAD.ps1` + the architecture in [`README.md`](./README.md)).

There is **no npm/pnpm project here** and no build, test or lint command. The root
`package-lock.json` is empty.

## Read this first

**[`README.md`](./README.md) — Windows Lab architecture.** Covers the physical machine inventory,
the two AutomatedLab environments (`IAMLab` on DELL-1 / `lab.local`, `Lab0` on HP-1 / `mim.com`),
the `10.250.250.0/24` CrossHost network, and the bidirectional forest trust.

## Architecture Notes

### HP-1 is `.103`; `.236` is its guest, not HP-1

HP-1 (`DESKTOP-32DRFM7`) is `192.168.0.103` on its wired I219-LM, and also `192.168.0.120` on
Wi-Fi (currently disconnected). `192.168.0.236` is the K3s node **`server-236`**, a Hyper-V *guest*
on HP-1 (MAC `00:15:5d:…`). So `.236` vanishes from the LAN whenever HP-1 is off while HP-1 itself
stays visible at `.103` — do not read a missing `.236` as "HP-1 is down". `HP-2` is `.122` and
`DELL-1` is `.123`.

### The two AD labs must stay separate

`IAMLab` and `Lab0` are independent AutomatedLab environments on independent hosts. The user
explicitly does **not** want them merged. Each keeps its own forest, subnet and router VM.

### CrossHost is the only working inter-host path — do not re-add routing

`10.250.250.0/24` over the shared physical LAN is what connects the labs. Routing
`192.168.100.0/24` ↔ `192.168.11.0/24` via RRAS/static routes/forwarding was **tried and
abandoned** — it never produced reliable connectivity. The CrossHost interfaces on the DCs
(`10.250.250.10`, `10.250.250.11`) intentionally have **no default gateway**; adding one puts
routing back on the path.

Caveat: `10.250.250.0/24` is a *logical* subnet over the physical `192.168.0.0/24` LAN — not
isolated. VLAN is the long-term fix if real L2 isolation is needed.

### `AutomatedLabAD.ps1` is stale on purpose

It encodes only the original DELL-1 `IAMLab` build (2-NIC `ROUTER01`, single-NIC `DC01`, no
CrossHost, no `Lab0`, no trust). **The CrossHost NICs were added after `Install-Lab`**, so they
cannot appear in the AutomatedLab definitions at all. Do not "fix" the script to match the README —
that drift is expected and is documented in `README.md` §8.

### Mac → HP-1 SSH: unresolved, and it is host-level filtering

HP-1 is up, active at 1 Gbps, and ARP-resolvable, yet ICMP and TCP get **no reply** (not a
refusal). Ruled out: wrong address, dead cable/port, vSwitch ownership of the NIC, and the K3s
cluster being up. Most likely the filter is on the **vSwitch host adapter**
(`vEthernet (WiFI External)`), not the raw Ethernet profile — so check `Get-NetConnectionProfile`
for a **Public** category and `Get-NetFirewallProfile` per interface rather than assuming the
machine-wide firewall state is what matters.

Don't file it as a regression in the AD/CrossHost architecture, and don't infer host state from
TCP timeouts on this LAN — a powered-off host times out identically. Check ARP or the gateway's
device list instead.

## Code Style Guidelines

- Use descriptive variable names.
- Follow existing patterns in the codebase.
- Extract complex conditions into meaningful boolean variables.

## Common Workflows

### K3s homelab power

`homelab-nodes.json` is the single source of truth for node identity and safety flags — never
hardcode node lists in the scripts.

- Bring up: `pwsh -File WindowsLab/Start-K3sHomelab.ps1 -DryRun` first, then `-RepairStorage`.
  Watch `kubectl get nodes -w`, then `kubectl get pods -A`.
- Shut down **must** run detached, or the shell suspends it:
  `pwsh -File WindowsLab/shutdown_homelab.ps1 -Force > shutdown.log 2>&1 < /dev/null &`
- Rehearse with `-DryRun`; check credentials with `-VerifyCredentials -Force`.
- SSH usernames are **case-sensitive**: `suryendub` on Ubuntu workers and `nuc`, `SuryenduB`
  (capital S) on `server-236` / `server-252`.

Full flag reference and troubleshooting: `docs/homelab/how-to-manage-homelab-power.md`.

### AD lab

See `README.md` for topology and `AutomatedLabAD.ps1` for the DELL-1 build steps. Lab VM
credentials live in the script, not in the docs.