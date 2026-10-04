# Windows Lab

This directory holds **two unrelated things**. They share a folder and nothing else — no shared
config, no shared state, no dependency in either direction.

| Concern | What it is | Where it is documented |
|---|---|---|
| **K3s homelab power** | Power on/off, drain and repair for the 11-node K3s cluster whose hosts are physical Windows/Linux machines | [`docs/homelab/how-to-manage-homelab-power.md`](../docs/homelab/how-to-manage-homelab-power.md), [`docs/homelab/`](../docs/homelab/), [`docs/operations/`](../docs/operations/) |
| **AD / IAM lab** | Two independent AutomatedLab + Hyper-V environments holding a working two-forest Active Directory, joined by a shared cross-host network | **This file**, plus [`AutomatedLabAD.ps1`](./AutomatedLabAD.ps1) |

The rest of this document describes the **AD / IAM lab**. For K3s homelab power, follow the runbooks
linked above.

---

## 1. Physical inventory

Five physical Windows machines. **Two** of them act as Hyper-V hosts; the other three are ordinary
lab clients.

| Machine | Role | CPU / RAM | LAN IP | Notes |
|---|---|---|---|---|
| `DELL-1` (`DESKTOP-9ACV9GD`) | Hyper-V host | i7-2600, 16 GB | `192.168.0.123` | Static. Hosts `IAMLab`. |
| `HP-1` (`DESKTOP-32DRFM7`) | Hyper-V host | i7-6600U, 16 GB | `192.168.0.103` | DHCP on the wired I219-LM. Also has `192.168.0.120` on **Wi-Fi** (currently disconnected). Hosts `Lab0`. |
| `HP-2` | Physical lab client | Celeron N3050, 8 GB | `192.168.0.122` | Static. `OpenSSH_for_Windows_9.5`. |
| Lenovo ThinkCentre | Physical lab client | i3-6100T, 8 GB | — | |
| Fujitsu ESPRIMO C720 | Physical lab client | i3-4150, 4 GB | — | |

> [!IMPORTANT]
> **HP-1 has two interfaces, not two identities — and `.236` is NOT HP-1.**
>
> | Entry | Address | MAC | Interface | State |
> |---|---|---|---|---|
> | `DESKTOP-32DRFM7-1` | `192.168.0.103` | `c8:d3:ff:6a:72:2e` | Ethernet (I219-LM) | **active** — this is HP-1, use this one |
> | `DESKTOP-32DRFM7` | `192.168.0.120` | `f0:d5:bf:26:11:be` | Wi-Fi | inactive — disconnected during troubleshooting |
>
> `192.168.0.236` is the K3s homelab node **`server-236`**, a **Hyper-V guest running on HP-1**
> (MAC `00:15:5d:00:78:2e` — `00:15:5d` is the Hyper-V synthetic OUI). Because it is a guest, it
> disappears from the LAN whenever HP-1 is off, while HP-1 itself stays visible at `.103`. Do not
> read `.236` being absent as "HP-1 is down". `server-236` is recorded in
> [`homelab-nodes.json`](./homelab-nodes.json) and also runs the local Docker registry on `:5000`.

> [!NOTE]
> `AutomatedLabAD.ps1` describes the DELL-1 host as "Dell Vostro 470 | 16GB RAM | 4 Cores |
> Windows 11 Pro". That is the same physical machine as `DELL-1` / `DESKTOP-9ACV9GD` above — the
> OEM string is simply more precise about the model than the marketing name, and the i7-2600's
> 4 cores / 16 GB match the older note.

> [!WARNING]
> `docs/homelab/K3s_Homelab_Template.md` used to record MAC `f0:d5:bf:26:11:be` against
> "HP-1 → hosts `server-236`". That MAC is actually **HP-1's Wi-Fi adapter**, not the guest.
> **Corrected on 2026-10-04** to the wired MAC `c8:d3:ff:6a:72:2e` — it invited exactly the
> `.103`-vs-`.236` confusion above.

### Machine identities, as reported by the gateway

Verified against the Vodafone Station's host table (`192.168.0.1` → Overview → LAN devices):

| Hostname | IP | MAC | Active | Source |
|---|---|---|---|---|
| `DESKTOP-32DRFM7-1` (HP-1) | `192.168.0.103` | `c8:d3:ff:6a:72:2e` | yes | DHCP |
| `DESKTOP-32DRFM7` (HP-1 Wi-Fi) | `192.168.0.120` | `f0:d5:bf:26:11:be` | no | Static |
| `HP-2` | `192.168.0.122` | `fc:3f:db:86:1a:81` | yes | Static |
| `DELL-1` | `192.168.0.123` | `5c:f9:dd:6b:7b:cf` | yes | Static |
| `NASECDE55` (NAS) | `192.168.0.128` | `00:08:9b:ec:de:55` | yes | Static |

The gateway is a Vodafone Station (Technicolor `CGA4233DE`, firmware `6.0.0L-R36`). To re-check
these yourself: log in at `http://192.168.0.1`, open **Overview**, expand the LAN list, and click a
device row to see its IP/MAC/state.

---

## 2. Two labs, deliberately not merged

The architecture is intentionally split into **two independent AutomatedLab environments** on two
separate physical hosts. They are **not** joined into a single lab definition, and must not be
merged — each has its own AD forest, its own subnet, and its own router VM.

### DELL-1 — AutomatedLab `IAMLab` (`lab.local`)

```text
DELL-1  192.168.0.123
├── Hyper-V
├── IAMLab (Internal) — 192.168.100.0/24
│   ├── DC01              192.168.100.10
│   ├── ROUTER01          192.168.100.1  (IAMLab / gateway)
│   │                     192.168.0.130  (External, static)
│   │                     10.250.250.1   (CrossHost)
│   └── SRV01             192.168.100.20
└── External switch → physical LAN 192.168.0.0/24
```

### HP-1 — AutomatedLab `Lab0` (`mim.com`)

```text
HP-1  192.168.0.103
├── Hyper-V
├── Lab0 (Internal) — 192.168.11.0/24
│   ├── DC1               192.168.11.3
│   ├── Router1           192.168.11.4    (Lab0 / gateway)
│   │                     192.168.0.115   (External, static)
│   │                     10.250.250.2    (CrossHost)
│   └── Ubuntu
└── "WiFI External" switch → Intel(R) Ethernet Connection I219-LM @ 1 Gbps
                             → physical LAN 192.168.0.0/24
```

> [!WARNING]
> **HP-1's external switch is named `WiFI External`, but it is bound to wired Ethernet** — the
> `Intel(R) Ethernet Connection I219-LM` at 1 Gbps. The name is historical and actively misleading.
> The physical Wi-Fi adapter held `192.168.0.120` but was **disconnected** during troubleshooting.
> `192.168.0.103` is the address that matters for HP-1.

---

## 3. CrossHost — the shared network between the two hosts

Both hosts sit on the same physical LAN, so the two labs can reach each other without being merged.
Each host's external switch carries a **CrossHost NIC**, and those two NICs talk to each other
directly on `10.250.250.0/24`:

```text
                Physical LAN  192.168.0.0/24
                          │
              ┌───────────┴───────────┐
              │                       │
           DELL-1 .123             HP-1 .103
              │                       │
     Hyper-V External        "WiFI External"
              │                       │
      CrossHost NIC            CrossHost NIC
              │                       │
     10.250.250.1 ──────────── 10.250.250.2
              │                       │
          ROUTER01                 Router1
```

The domain controllers were then given CrossHost interfaces as well:

| Computer | Forest | CrossHost IP | Default gateway |
|---|---|---|---|
| `DC01.lab.local` | `lab.local` | `10.250.250.10` | **none** |
| `DC1.mim.com` | `mim.com` | `10.250.250.11` | **none** |

> [!IMPORTANT]
> The CrossHost interfaces on the DCs deliberately have **no default gateway**. They exist only for
> the inter-host lab network. Adding a gateway here would put ordinary LAN/Internet routing back on
> the path and reintroduce the failure described in §5.

### Verified connectivity

```text
Router1    10.250.250.2  → 10.250.250.1    ✓
ROUTER01   10.250.250.1  → 10.250.250.2    ✓
DC1        10.250.250.11 → 10.250.250.10   ✓
```

### DC Locator resolves across both forests

```powershell
nltest /dsgetdc:mim.com
  → DC1.mim.com
  → 10.250.250.11

nltest /dsgetdc:lab.local
  → DC01.lab.local
  → 10.250.250.10
```

---

## 4. Forest trust

```text
   lab.local   ⇄  Bidirectional Forest Trust ⇄   mim.com
```

```powershell
Get-ADTrust
  TrustType        : Uplevel
  Direction        : BiDirectional
  ForestTransitive : True
```

This is **not** a paper trust. A real cross-forest directory query from `DC01` against the other
forest succeeds:

```powershell
Get-ADUser -Filter * -Server "DC1.mim.com" -Credential $cred
```

returning `Administrator`, `Guest`, `krbtgt`, `a681990`, `a731098`.

So the lab is a functioning distributed, multi-forest Active Directory across two physical Hyper-V
hosts.

---

## 5. The abandoned approach: routing `192.168.100.0/24` ↔ `192.168.11.0/24`

> [!CAUTION]
> **Do not retry this.** It was attempted first and abandoned.

The original plan was to make the two lab networks talk by **routing** between them — RRAS, static
routes, IP forwarding. That did **not** produce reliable connectivity. The CrossHost design in §3
replaced it, and works. If you find yourself configuring RRAS static routes between the two lab
subnets, you are re-entering a dead end.

---

## 6. Known caveat: `10.250.250.0/24` is not isolated

`10.250.250.0/24` is a **logical** lab subnet riding over the shared physical
`192.168.0.0/24` Ethernet network. It is **not physically isolated** — anything else on the LAN can
reach it, and it can reach them.

A **VLAN** is the cleaner long-term implementation if true Layer-2 isolation is ever needed. Until
then, treat `10.250.250.0/24` as a trusted, lab-only range and do not put production or
untrusted-adjacent traffic on it.

---

## 7. Physical-host SSH (separate concern)

Configuring OpenSSH on the five physical Windows machines uses the common local account
**`SuryenduB`**. This work is **unrelated to the AD/CrossHost networking above** — do not conflate
the two, and do not treat an SSH problem as a lab-network problem.

Confirmed working on HP-1:

```text
sshd      Running
Startup   Automatic
TCP 22    Listening
192.168.0.103:22   works locally
```

> [!WARNING]
> **HP-1's host cannot be reached from the LAN — confirmed NIC-level receive fault (2026-10-04).**
>
> **Symptom:** the host answers ARP but never answers ICMP or TCP, from *any* LAN client (Mac and
> DELL-1 both fail). The guest `server-236` (`.236`) on the same physical NIC is reachable the
> whole time. Broadcast works, unicast to the host does not.
>
> Ruled out **by test**, not by inference:
>
> | Hypothesis | Result |
> |---|---|
> | Firewall / `NetworkCategory` | ❌ all profiles `Enabled=False`; `vEthernet (WiFI External)` is `Private` |
> | WFP / Azure-VFP vSwitch extensions | ❌ both `Enabled=False`; only `Microsoft NDIS Capture` is on |
> | Port ACLs on the management-OS vNIC | ❌ `Get-VMNetworkAdapterAcl` returns nothing |
> | Checksum / LSO offloads | ❌ disabled on **both** `Ethernet` and `vEthernet (WiFI External)` — no change |
> | VMQ / SR-IOV | ❌ not present on this NIC (`Get-NetAdapterVmq` / `Get-NetAdapterSriov` return no objects) |
> | IP address / duplicate IP | ❌ fails on `.103` **and** `.105`; no duplicate-IP events; no duplicate MAC on the LAN |
> | Switch port | ❌ cable moved `g9` → `g16`, no change |
> | MAC address | ❌ Hyper-V locks the management-OS MAC to the physical NIC (`Set-VMNetworkAdapter -StaticMacAddress` → *"cannot be set for a management OS adapter"*; the `Network Address` advanced property is also rejected) |
> | Hyper-V / the vSwitch | ❌ fails identically with `Disable-NetAdapterBinding -ComponentID vms_pp` **and** a static IP on the bare `Ethernet` adapter |
> | The MAC itself | ❌ a brand-new MAC (`00-1b-21-3c-4d:5e`) is answered on ARP but still gets no unicast reply |
>
> **Confirmed cause:** the **Intel I219-LM does not receive inbound unicast addressed to its own
> MAC**, while continuing to accept broadcast. Because the new MAC also fails, it is the NIC/driver
> receive path — not a stale switch FDB entry and not a stale MAC filter.
>
> **Workaround:** bind the external vSwitch to a **USB Gigabit Ethernet adapter** instead of the
> onboard I219-LM:
> `New-VMSwitch -Name "WiFI External" -NetAdapterName "<USB NIC>" -AllowManagementOS $true`.
> Optionally try HP's OEM I219-LM driver first, but expect the USB adapter to be the reliable fix.
>
> Until then, reach HP-1 over **Chrome Remote Desktop** (outbound), which is unaffected.
>
> All of the above was collected with `WindowsLab/Get-HP1NetworkDiagnostics.ps1` (read-only).
>
> This is deliberately *not* part of the working AD/CrossHost architecture — do not treat it as a
> regression against §3.

### For contrast: SSH that does work

| Host | Address | Banner |
|---|---|---|
| `DELL-1` | `192.168.0.123` | `SSH-2.0-OpenSSH_for_Windows_7.7` (stock Windows build) |
| `HP-2` | `192.168.0.122` | `SSH-2.0-OpenSSH_for_Windows_9.5` (manually installed) |

The version difference is the useful signal: `HP-2` has a manually installed OpenSSH, `DELL-1` only
the stock Windows one.

Note that the K3s homelab SSH usernames are **case-sensitive** and differ per machine
(`suryendub` on the Ubuntu workers, `SuryenduB` on `server-236` / `server-252`) — see
[`homelab-nodes.json`](./homelab-nodes.json) and
[`docs/homelab/how-to-manage-homelab-power.md`](../docs/homelab/how-to-manage-homelab-power.md).

---

## 8. Build script and known drift

[`AutomatedLabAD.ps1`](./AutomatedLabAD.ps1) is the AutomatedLab build script for **DELL-1's
`IAMLab` only**. It is the original, pre-CrossHost version and **does not describe the current
topology**. Read it as "how `IAMLab` was first built", not as the current architecture.

What the script encodes vs. what is actually deployed:

| Item | In `AutomatedLabAD.ps1` | Actually deployed |
|---|---|---|
| `ROUTER01` NICs | 2 — internal `192.168.100.1` static, external DHCP | 3 — internal `192.168.100.1`, external **static `192.168.0.130`**, CrossHost `10.250.250.1` |
| `DC01` NICs | 1 — `192.168.100.10` | 2 — `192.168.100.10` + CrossHost `10.250.250.10` |
| CrossHost switch | not defined | exists on both hosts |
| `Lab0` / HP-1 | not present at all | separate lab on a separate host |
| Forest trust | not present at all | bidirectional, working |

**This drift is expected and the script is intentionally left as-is.** The CrossHost interfaces were
added *after* `Install-Lab` had already deployed the lab, so they cannot be expressed in the
AutomatedLab definitions — AutomatedLab only builds networking at initial deploy time. Reproducing
the current topology means deploying the lab from the script and then adding the CrossHost NICs by
hand, as was done here.

Lab VM sizing and OS, as defined by the script:

| VM | Forest role | RAM | vCPU | OS |
|---|---|---|---|---|
| `ROUTER01` | RRAS router / NAT | 1 GB | 1 | Windows Server 2022 Standard Evaluation (Core) |
| `DC01` | RootDC + AD DS + DNS | 2 GB | 1 | Windows Server 2022 Standard Evaluation (Core) |
| `SRV01` | Member server / Entra Connect host | 4 GB | 2 | Windows Server 2022 Standard Evaluation (Desktop Experience) |

Two non-obvious things the script works around, worth preserving if you rebuild:

- **RRAS must be reinstalled as `RoutingOnly`** after `Install-Lab`. AutomatedLab's `Routing` role
  installs RRAS with VPN components that need machine certificates, which makes the service fail.
- **DNS forwarders must be set on `DC01`** post-build. AutomatedLab configures AD-integrated DNS but
  no external forwarders, so domain-joined VMs resolve `lab.local` but nothing external — breaking
  Windows Update and Entra Connect endpoint reach.

Lab VM credentials are defined in `AutomatedLabAD.ps1` (`Set-LabInstallationCredential` /
`Add-LabDomainDefinition`) and are intentionally **not** duplicated here.

---

## 9. Extension points

This foundation is intended to be extended with:

- additional forests
- member servers
- AD CS (certificate services)
- DNS scenarios
- identity / IAM testing
- privileged access
- additional trusts
- more sophisticated cross-host networking

When extending, preserve the two invariants that make the current setup work:

1. **Do not merge `IAMLab` and `Lab0`.** They stay independent AutomatedLab environments.
2. **CrossHost DC interfaces stay gateway-less.** Routing is what already failed once (§5).