# K3s homelab

**Updated:** 2026-10-18
**Scope:** Cluster architecture, application access, infrastructure, storage, and dated audit snapshots. Sections marked as snapshots retain their observation dates.
**K3s baseline:** `v1.34.6+k3s1`; current versions were not checked during the 2026-10-18 host inspection.

---

## Table of contents

1. [Operational guides](#operational-guides)
2. [Cluster overview](#cluster-overview)
3. [Application access and URLs](#application-access-and-urls)
4. [System infrastructure](#system-infrastructure-audit-snapshot)
5. [Kubernetes cluster health](#kubernetes-cluster-health)
6. [Observability and monitoring](#observability-and-monitoring)
7. [Storage architecture](#storage-architecture)
8. [Governance and security](#governance-and-security)
9. [Local container registry](#local-container-registry)
10. [Application image versions](#application-image-versions)
11. [Audit and compliance reference](#audit-and-compliance-reference)
12. [Troubleshooting](#troubleshooting)
13. [Documentation References](#documentation-references)

---

## Operational guides

Use these runbooks for cluster operations:

- [Manage homelab power](how-to-manage-homelab-power.md) covers startup, shutdown, and SecretStore credentials.
- [Audit and recover the cluster](how-to-audit-homelab.md) covers audits, certificates, the local registry, backups, and Tailscale recovery.
- The [control-plane HA runbook](../operations/k3s-control-plane-ha-runbook.md) records the three-member embedded-etcd setup, join steps, quorum, and member-loss verification.
- The [control-plane HA plan](homelab-control-plane-ha-plan.md) records the design, implementation status, and client endpoint gap.

---

## Cluster overview

### Architecture diagram

![Homelab Architecture](../../diagrams/homelab_architecture.png)

### Cluster configuration

- **Version baseline:** K3s `v1.34.6+k3s1`, documented on all nodes.
- **Node inventory:** 10 nodes, 3 control-plane members and 7 workers. `kubernetes7` was decommissioned on 2026-10-17.
- **Readiness:** all 11 nodes were Ready on 2026-09-20. Readiness of the remaining 10 was not checked during the 2026-10-18 host inspection.
- **Network:** flat LAN, `192.168.0.0/24`.
- **Storage:** Longhorn for cluster volumes; QNAP NAS for NFS data and backups.
- **CNI:** Flannel.
- **Ingress:** Traefik, installed with K3s.

### Control plane (embedded etcd, 3 members)

| Node         | IP            | Role                        | Joined          |
| ------------ | ------------- | --------------------------- | --------------- |
| `nuc`        | 192.168.0.21  | control-plane, etcd, master | original server |
| `server-236` | 192.168.0.236 | control-plane, etcd, master | 2026-09-19      |
| `server-252` | 192.168.0.252 | control-plane, etcd, master | 2026-09-20      |

> **Verified 2026-09-20:** the three embedded-etcd members tolerate one server loss (quorum is 2 of 3). The test stopped `server-252` and confirmed `/readyz` returned `ok`. The members were rejoined into one etcd lineage after the 2026-10-17 shutdown recovery. See
> [`docs/operations/k3s-control-plane-ha-runbook.md`](../operations/k3s-control-plane-ha-runbook.md);
> the `.249` target in the original [design plan](./homelab-control-plane-ha-plan.md) was never built.

> **Client endpoint gap:** kubeconfigs and monitors point to `https://192.168.0.21:6443`. The etcd quorum survives one member loss, but clients still depend on `nuc`. See Phase 3.1 of the plan for the VIP/DNS work.

---

## Application access and URLs

### Web applications (Tailscale MagicDNS)

This inventory was checked on 2026-09-17 against workloads, Service ports, and device FQDNs recorded by the Tailscale operator. A listed hostname does not prove end-to-end reachability. Access requires a connected Tailscale client and the right tailnet permissions.

| MagicDNS setting   | Verified value      |
| ------------------ | ------------------- |
| Tailnet DNS domain | `tail35421d.ts.net` |

#### AI and language learning

| Application       | Namespace              | MagicDNS access                                   | Purpose                           |
| ----------------- | ---------------------- | ------------------------------------------------- | --------------------------------- |
| Ollama            | `ai`                   | Internal only; no dedicated Tailscale proxy found | Local AI model serving            |
| Open WebUI        | `ai`                   | <http://openwebui.tail35421d.ts.net:8080>         | AI chat interface                 |
| AI Language Tutor | `ai-language-learning` | <http://lang-tutor.tail35421d.ts.net>             | Custom language-learning backend  |
| OpenLingo         | `openlingo`            | <http://openlingo.tail35421d.ts.net>              | Language-learning platform        |
| LinguaCafe        | `linguacafe`           | <http://linguacafe.tail35421d.ts.net>             | Language learning through reading |

#### Books and media

| Application    | Namespace | MagicDNS access                                                               | Public access                                                                                                                                                                                                                                                                             |
| -------------- | --------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Audiobookshelf | `media`   | <http://audiobookshelf.tail35421d.ts.net> (daily access path) | Cloudflare Quick Tunnel, protected by the nginx session-cookie gate (`absproxy`). The hostname changes. Run `pwsh -File ./WindowsLab/Get-CloudflareTunnelUrls.ps1 -Verify` to read it. See `kubernetes-manifests/cloudflare/README.md`. |
| Calibre-Web    | `media`   | <http://calibre-web.tail35421d.ts.net:8083>                                   | Not listed                                                                                                                                                                                                                                                                                         |
| BookHoarder    | `media`   | <http://bookhoarder.tail35421d.ts.net>                                        | Not listed                                                                                                                                                                                                                                                                                         |
| Booklogr       | `media`   | <http://booklogr.tail35421d.ts.net>                                           | Not listed                                                                                                                                                                                                                                                                                         |
| BookOrbit      | `media`   | <http://bookorbit.tail35421d.ts.net>                                          | Not listed                                                                                                                                                                                                                                                                                         |
| LibrisLog      | `media`   | <http://librislog.tail35421d.ts.net>                                          | Not listed                                                                                                                                                                                                                                                                                         |
| Immich         | `media`   | <http://immich.tail35421d.ts.net>                                             | Not listed                                                                                                                                                                                                                                                                                         |
| Flick          | `media`   | <http://flick.tail35421d.ts.net>                                              | Not listed                                                                                                                                                                                                                                                                                         |

#### Dashboards and server management

| Application     | Namespace           | MagicDNS access                              | Public access                                                                                                                              |
| --------------- | ------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Homepage        | `homepage`          | <http://homepage-homepage.tail35421d.ts.net> | Cloudflare Quick Tunnel, with no authentication gate. The hostname changes; use the script above to read it. |
| Homarr          | `dashboard`         | <http://homarr.tail35421d.ts.net>            | Not listed                                                                                                                                          |
| Cairn           | `dashboard`         | <http://cairn.tail35421d.ts.net>             | Not listed                                                                                                                                          |
| Homelab Manager | `server-management` | <http://homelab-manger.tail35421d.ts.net>    | Not listed                                                                                                                                          |
| RemotePower     | `server-management` | <http://remotepower.tail35421d.ts.net>       | Not listed                                                                                                                                          |

The spelling `homelab-manger` matches the deployed Service and registered hostname.

#### Monitoring and observability

| Application     | Namespace    | MagicDNS access                                          |
| --------------- | ------------ | -------------------------------------------------------- |
| Beszel Hub      | `monitoring` | <http://beszel.tail35421d.ts.net>                        |
| Dozzle          | `monitoring` | <http://dozzle.tail35421d.ts.net>                        |
| Gotify          | `monitoring` | <http://gotify.tail35421d.ts.net>                        |
| Apprise         | `monitoring` | <http://apprise.tail35421d.ts.net>                       |
| Homelab Monitor | `monitoring` | <http://homelab-monitor.tail35421d.ts.net>               |
| LanGuard        | `monitoring` | <http://languard.tail35421d.ts.net>                      |
| Lantern         | `monitoring` | <http://lantern.tail35421d.ts.net>                       |
| LogChef         | `monitoring` | <http://logchef.tail35421d.ts.net>                       |
| OmniSight       | `monitoring` | <http://omnisight.tail35421d.ts.net>                     |
| PooML           | `monitoring` | <http://pooml.tail35421d.ts.net>                         |
| Uptime Kuma     | `monitoring` | <http://uptime-kuma.tail35421d.ts.net>                   |

#### IdentityIQ lab and deployment management

| Application          | Namespace  | MagicDNS access                                | Purpose                    |
| -------------------- | ---------- | ---------------------------------------------- | -------------------------- |
| SailPoint IdentityIQ | `iiqstack` | <http://iiq-main.tail35421d.ts.net/identityiq> | Identity governance        |
| phpLDAPadmin         | `iiqstack` | <https://iiq-ldap-admin.tail35421d.ts.net>     | LDAP directory management  |
| ActiveMQ UI          | `iiqstack` | <http://iiq-mq-admin.tail35421d.ts.net:8161>   | Message broker console     |
| Mailpit UI           | `iiqstack` | <http://iiq-mail.tail35421d.ts.net:8025>       | Email testing dashboard    |
| Counter              | `iiqstack` | `iiq-counter.tail35421d.ts.net:12345`          | Demo service; TCP endpoint |
| SSH service          | `iiqstack` | `iiq-ssh.tail35421d.ts.net:22`                 | SSH access                 |
| Argo CD              | `argocd`   | <https://argocd.tail35421d.ts.net>             | Deployment management      |

Use the canonical `argocd` and `openwebui` Tailscale endpoints. A registered MagicDNS name does not guarantee a trusted HTTPS certificate.

#### Read on mobile with Moon+ Reader

Calibre-Web serves an OPDS catalog. Add it to Moon+ Reader on Android:

1. Open Moon+ Reader, tap the hamburger menu, then Net Library.
2. Tap the top-right menu, then Add new catalog.
3. Set the catalog name to `Calibre-Web`.
4. Set the catalog URL to `http://calibre-web.tail35421d.ts.net:8083/opds`.
5. Tap OK and log in with Calibre-Web credentials.
6. Browse the catalog, tap a book, then Download to read offline.

Other compatible apps include KOReader, Aldiko, FBReader, and PocketBook.

### Infrastructure services over Tailscale

| Service         | Namespace  | MagicDNS host                    | TCP port / access |
| --------------- | ---------- | -------------------------------- | ----------------- |
| MSSQL           | `iiqstack` | `iiq-db.tail35421d.ts.net`       | 1433              |
| MySQL           | `iiqstack` | `iiq-db-mysql.tail35421d.ts.net` | 3306              |
| LDAP            | `iiqstack` | `iiq-ldap.tail35421d.ts.net`     | 389               |
| SSH             | `iiqstack` | `iiq-ssh.tail35421d.ts.net`      | 22                |
| ActiveMQ broker | `iiqstack` | `iiq-mq-admin.tail35421d.ts.net` | 61616             |
| Mailpit SMTP    | `iiqstack` | `iiq-mail.tail35421d.ts.net`     | 1025              |
| Counter         | `iiqstack` | `iiq-counter.tail35421d.ts.net`  | 12345             |

### Supporting components

These components have no dedicated MagicDNS proxy and are not user-facing applications.

| Component                                                | Namespace(s)                                               | Role / access                                                                                                                                                             |
| -------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Longhorn and CSI components                              | `longhorn-system`                                          | Persistent storage; UI Service is currently ClusterIP: `http://longhorn-frontend.longhorn-system.svc:80` (cluster-internal), not the previously documented NodePort 30080 |
| Tailscale operator and proxies                           | `tailscale`                                                | Publish the MagicDNS endpoints above; proxies are not separate apps                                                                                                       |
| CloudNativePG controller                                 | `cnpg-system`                                              | PostgreSQL operator                                                                                                                                                       |
| Traefik                                                  | `kube-system`                                              | Ingress controller                                                                                                                                                        |
| CoreDNS                                                  | `kube-system`                                              | Cluster DNS                                                                                                                                                               |
| metrics-server                                           | `kube-system`                                              | Kubernetes resource metrics                                                                                                                                               |
| Local-path provisioner                                   | `kube-system`                                              | Local persistent storage provisioning                                                                                                                                     |
| NFS provisioner                                          | `default`                                                  | NAS-backed persistent storage provisioning                                                                                                                                |
| PostgreSQL                                               | `ai-language-learning`, `openlingo`, `media`, `monitoring` | Databases for AI Language Tutor, OpenLingo, BookOrbit, Immich, and Flick                                                                                          |
| MariaDB                                                  | `linguacafe`                                               | LinguaCafe database                                                                                                                                                       |
| Redis / Valkey                                           | `linguacafe`, `argocd`, `media`                            | Supporting cache services; Valkey 9 backs Immich                                                                                                                          |
| Flick API / web / Caddy                                  | `media`                                                    | Internal Flick tiers; only Caddy has a MagicDNS proxy                                                                                                                     |
| Immich ML                                                | `media`                                                    | Machine-learning backend; only the server has a MagicDNS proxy                                                                                                            |
| Booklogr API and LibrisLog backend                       | `media`                                                    | Internal application backends                                                                                                                                             |
| Beszel agent                                                    | `monitoring`                                               | Monitoring agent; not a separate user-facing app                                                                                                                          |
| Argo CD controllers, repo server, Dex, and notifications | `argocd`                                                   | Supporting components of the Argo CD installation                                                                                                                         |

**Readiness snapshot (2026-09-17):** All Deployments and StatefulSets checked met their desired Ready counts except IdentityIQ (**1/2 Ready**). Beszel was **1/1 Ready**. This covers Deployments and StatefulSets only. It says nothing about node or DaemonSet health.

---

## System infrastructure (audit snapshot)

### Host access and identity probe (2026-10-18 01:56 CEST)

This was a bounded, read-only SSH reachability and host inventory pass from the repository
workstation. Linux identity probes ran at 2026-10-18 01:56 CEST. Supplemental PowerShell
inventory ran at 2026-10-18 02:02 CEST on HP-2 and the Lenovo ThinkCentre. Sources: local
`arp -an`, inventory in `WindowsLab/homelab-nodes.json`, documented physical-host inventory in
`WindowsLab/README.md`, TCP/22 probes, and SSH with existing known-host verification enabled.
PowerShell collection used CIM, volume/network/listener/service queries, Hyper-V cmdlets where
available, command discovery for container runtimes, and a filtered scheduled-task name query.
No remote configuration was changed. The task query recorded task names and states only; it did
not expose task action arguments.

| Host / candidate | Address(es) | TCP/22 | SSH outcome | Verified observation / limitation |
| --- | --- | --- | --- | --- |
| `kubernetes1` (K3s node) | `192.168.0.19` | Reachable | Authenticated as `suryendub` | Hostname `kubernetes1`; Linux x86_64, kernel `6.8.0-147-generic`. CPU, memory, uptime, filesystems, network configuration, services, K3s/Longhorn health, and workloads: Not verified; the single permitted login was used by the identity probe. |
| `kubernetes2` (K3s node) | `192.168.0.20` | Reachable | Authenticated as `suryendub` | Hostname `kubernetes2`; Linux x86_64, kernel `6.8.0-147-generic`. Remaining profile: Not verified for the same reason. |
| `nuc` (K3s node) | `192.168.0.21` | Reachable | Authenticated as `suryendub` | Hostname `NUC`; Linux x86_64, kernel `7.0.0-38-generic`. Remaining profile: Not verified for the same reason. |
| `kubernetes3` (K3s node) | `192.168.0.22` | Reachable | Authenticated as `suryendub` | Hostname `kubernetes3`; Linux x86_64, kernel `6.8.0-147-generic`. Remaining profile: Not verified for the same reason. |
| `kubernetes4` (K3s node) | `192.168.0.23` | Reachable | Authenticated as `suryendub` | Hostname `kubernetes4`; Linux x86_64, kernel `6.8.0-147-generic`. Remaining profile: Not verified for the same reason. |
| `kubernetes5` (K3s node) | `192.168.0.24` | Reachable | Authenticated as `suryendub` | Hostname `kubernetes5`; Linux x86_64, kernel `7.0.0-38-generic`. Remaining profile: Not verified for the same reason. |
| `kubernetes6` (K3s node) | `192.168.0.25` | Reachable | Authenticated as `suryendub` | Hostname `kubernetes6`; Linux x86_64, kernel `6.8.0-147-generic`. Remaining profile: Not verified for the same reason. |
| `kubernetes8-debian` (K3s node) | `192.168.0.27` | Reachable | Authenticated as `suryendub` | Hostname `kubernetes8-debian`; Linux x86_64, kernel `6.12.74+deb13+1-amd64`. Remaining profile: Not verified for the same reason. |
| `server-236` (inventory K3s node / registry host) | `192.168.0.236` | Reachable | Authenticated as `SuryenduB` | **Identity conflict:** live hostname is `install-Virtual-Machine`, Linux x86_64, kernel `7.0.0-38-generic`; inventory/documentation calls this `server-236`. Physical/VM mapping and all remaining profile: Not verified. Preserve the conflict until independently reconciled. |
| `server-252` (K3s node / VM) | `192.168.0.252` | Reachable | Authenticated as `suryendub` | Guest hostname `k3s-master`; Linux x86_64, kernel `5.4.0-216-generic`. The ThinkCentre at `.170` independently reports its Hyper-V VM `k3s-master-2` Running (Generation 2, 2 vCPU, 3 GiB startup memory), matching the documented parent/guest relationship. Guest OS release, readiness, Longhorn state, and workloads: Not verified. |
| QNAP NAS `NASECDE55` | `192.168.0.128` | Reachable | Authenticated as documented `admin` | Hostname `NASECDE55`; Linux ARMv7l, kernel `3.2.26`. NAS firmware, disks, shares, services, backup/monitoring configuration: Not verified; the single permitted login was used by the identity probe. |
| HP-1 physical Windows host | `192.168.0.103` (wired); `192.168.0.120` (Wi-Fi) | No reply on either address | SSH unavailable; no authentication attempted | The local ARP table maps `.120` to the Wi-Fi MAC documented for HP-1. The cached neighbor entry does not establish current power/interface state; the README's prior disconnected state is not confirmed live. These are two interfaces of one physical host. Windows configuration and hosted VMs: Not verified. |
| HP-2 physical Windows host | `192.168.0.122` | Reachable | Authenticated as `SuryenduB`; PowerShell inventory completed | Hostname `DESKTOP-EAJUV53`; Windows 10 Home, version `10.0.19045`/build `19045`; HP Notebook; Intel Celeron N3050, 2 cores; 8,440,266,752 bytes RAM (~7.86 GiB); booted 2026-10-03 22:24 CEST; C: NTFS, 127.3 GB total / 90.2 GB free. Ethernet is Up at `.122`, MAC `FC-3F-DB-86-1A-81`, gateway `.1`; Wi-Fi is Disconnected. SSHD is Running/Automatic and listens on TCP 22; `beszel-agent` listens on 45876. Hyper-V cmdlet returned no host VM inventory; Docker, Podman, and containerd commands were not found in the current user's PATH. Filtered scheduled-task results included `MareBackup`; its action/target was not inspected. No K3s role or hosted VM was observed. |
| DELL-1 physical Windows host | `192.168.0.123` | No reply | SSH unavailable; no authentication attempted | Existing SSH host key is present, but TCP/22 did not answer. Windows configuration and hosted VMs: Not verified. |
| Lenovo ThinkCentre physical Windows host | `192.168.0.170` | Reachable | Authenticated as `SuryenduB`; PowerShell inventory completed | Hostname `DESKTOP-F3QNNA5`; Windows 11 Pro, version `10.0.26200`/build `26200`; Lenovo model `10J0A0GPGE`; Intel Core i3-6100T, 2 cores/4 logical processors; 8,474,767,360 bytes RAM (~7.89 GiB); booted 2026-10-17 18:09 CEST; C: NTFS, 254.9 GB total / 163.9 GB free. `vEthernet (ExternalSwitch)` is Up at `.170`, MAC `00-23-24-BD-64-3F`; Tailscale IPv4 `100.120.142.61`; default gateway `.1`. Hyper-V services are running; VM `k3s-master-2` is Running, Generation 2, 2 vCPU, 3 GiB startup memory. SSHD listens on 22; VMMS listens on 2179; Tailscale daemon has listeners. Docker, Podman, and containerd commands were not found in the current user's PATH, while repository guidance says the host runs Podman; current Podman installation/runtime state therefore remains Not verified. No VM guest workload inventory or current K3s/Longhorn health was collected. |
| Fujitsu ESPRIMO C720 physical Windows host | No address recorded | Not tested | No SSH attempt; host is in scope but its address is unresolved | WindowsLab README identifies this physical lab client with i3-4150; the older 4 GB RAM note is unverified and the owner is unsure whether installed RAM is 4 or 8 GB. No current ARP entry could be safely tied to it. OS, IP/MAC, SSH service, storage, and hosted services/VMs: Not verified. |

The candidate set is the ten K3s node records, the explicitly inventoried NAS, and the five
physical Windows hosts listed in `WindowsLab/README.md`. The two HP-1 addresses are one physical
host. The Fujitsu has no recorded IP and could not be mapped to a current neighbor entry, so it
was not probed. Other ARP entries were not contacted because the supplied inventory and
documentation did not establish homelab ownership. Corrected PowerShell sessions verified HP-2
and ThinkCentre identities and the ThinkCentre's Hyper-V relationship to `server-252`. Existing
host-key checking was not disabled. HP-1 and DELL-1 remain unreachable on TCP/22. The `.236`
live/inventory hostname conflict remains a blocker; all uncollected configuration, including
Linux hardware/storage/network profiles, K3s readiness, Longhorn health, Linux-hosted containers,
and live workload placement/dependencies, remains explicitly Not verified rather than inferred
from older snapshots.

| Node                          | OS           | CPU            | RAM            | Disk (Root)     | Status                           |
| ----------------------------- | ------------ | -------------- | -------------- | --------------- | -------------------------------- |
| **NUC**                       | Ubuntu 24.04 | 2C/4T          | 7.7Gi          | 109G (49% used) | Master                        |
| **kubernetes1**               | Ubuntu 24.04 | 4C/4T          | 15Gi           | 455G (36% used) | Worker                        |
| **kubernetes2**               | Ubuntu 24.04 | 4C/4T          | 15Gi           | 98G (66% used)  | Worker                        |
| **kubernetes3**               | Ubuntu 24.04 | 2C/4T          | 15Gi           | 107G (46% used) | Worker                        |
| **kubernetes4**               | Ubuntu 24.04 | 4C/4T          | 7.7Gi          | 98G (60% used)  | Worker                        |
| **kubernetes5**               | Ubuntu 24.04 | 2C/4T          | 7.7Gi          | 98G (45% used)  | Worker                        |
| **kubernetes6**               | Ubuntu 24.04 | 2C/4T          | 15Gi           | 98G (50% used)  | Worker                        |
| **kubernetes7**               | Ubuntu 24.04 | 2C/4T          | 7.7Gi          | 98G (46% used)  | Decommissioned 2026-10-17    |
| kubernetes8-debian            | Debian 13    | 4C/4T          | 3.8Gi          | 289G (2% used)  | Worker                        |
| **server-236** (HP-1)         | Ubuntu 24.04 | not re-audited | not re-audited | not re-audited  | Control plane #2, registry |
| **server-252** (`k3s-master`) | Ubuntu 20.04 | 2C/2T          | 3.0Gi (dyn)    | 124G (5% used)  | Control plane #3, Hyper-V VM |

_This is a dated hardware snapshot, not a current health check. The `kubernetes7` row records the node before its 2026-10-17 decommissioning. Control-plane rows were added on 2026-09-20. `server-252` is a Hyper-V guest on the Lenovo ThinkCentre, an 8 GB host that runs Podman. The guest uses Dynamic Memory. Its log reported `Balloon floor reached`; the recorded recommendation was a 3 GB minimum and 6 GB maximum rather than a fixed 4 GB. HP-1 hardware was not re-audited in that snapshot. HP-1 hosts `server-236`._

### Network infrastructure

| Device          | Model                  | IP Address    | Management             | Credentials               |
| --------------- | ---------------------- | ------------- | ---------------------- | ------------------------- |
| **Core Switch** | Netgear ProSafe GS716T | 192.168.0.99  | Web GUI                | `32558068`                |
| **QNAP NAS**    | NASECDE55 (ARMv7l)     | 192.168.0.128 | SSH (`admin`/`558068`) | Tailscale: `100.70.79.12` |

### Physical port map (GS716T), validated with LLDP

| Port    | Connected Device                            | MAC Address         | Role                                  | Status                                                                            |
| :------ | :------------------------------------------ | :------------------ | :------------------------------------ | :-------------------------------------------------------------------------------- |
| **g1**  | Vodafone Router                             | `02:10:18:1C:F8:CC` | Uplink (Transit)                      | Active |
| **g2**  | kubernetes6                                 | `90:1B:0E:56:D7:BB` | K3s Worker                            | Verified with LLDP |
| **g3**  | kubernetes5                                 | `44:8A:5B:2C:B8:83` | K3s Worker                            | Verified with LLDP |
| **g4**  | kubernetes1                                 | `90:1B:0E:89:B9:66` | K3s Worker                            | Verified with LLDP |
| **g5**  | kubernetes4                                 | `64:00:6A:62:72:DC` | K3s Worker                            | Verified with LLDP |
| **g6**  | kubernetes2                                 | `40:B0:76:0F:3C:72` | K3s Worker                            | Verified with LLDP |
| **g8**  | NUC (master)                                 | `C0:3F:D5:6D:45:85` | K3s master                            | Verified with LLDP |
| **g16** | HP-1 (`DESKTOP-32DRFM7`), host of `server-236` | `c8:d3:ff:6a:72:2e` | Control plane #2 and local registry | Moved from g9 on 2026-10-04 during NIC troubleshooting |
| **g10** | kubernetes7                                 | `6C:C2:17:E9:A4:E5` | K3s worker                            | Historical LLDP record; node decommissioned 2026-10-17 |
| **g11** | HP-2                                        | `FC:3F:DB:86:1A:81` | Trusted host                          | Active |
| **g12** | kubernetes8-debian                          | `00:14:0B:45:02:83` | K3s worker                            | Verified with LLDP |
| **g15** | kubernetes3                                 | `40:8D:5C:AA:D9:1F` | K3s worker                            | Verified with LLDP |

_The QNAP MAC appeared on g1, the router uplink, in this LLDP snapshot. This suggests the NAS connects to the router directly._

---

## Kubernetes cluster health

### Pod distribution snapshot

The capture date is not recorded. It predates the decommissioning of `kubernetes7` on 2026-10-17, so treat its node placement and resource readings as historical.

| Namespace      | Pod Name               | Node                            | CPU  | Memory |
| -------------- | ---------------------- | ------------------------------- | ---- | ------ |
| **iiqstack**   | `db-0`                 | `kubernetes1`                   | 42m  | 2.1Gi  |
| **iiqstack**   | `iiq-55d965997c-7vjd8` | `kubernetes2`                   | 28m  | 1.8Gi  |
| **iiqstack**   | `iiq-55d965997c-mp268` | `kubernetes3`                   | 26m  | 1.8Gi  |
| **iiqstack**   | `db-mysql-0`           | `kubernetes6`                   | 22m  | 840Mi  |
| **iiqstack**   | `activemq-0`           | `kubernetes3`                   | 12m  | 256Mi  |
| **ai**         | `ollama-*`             | `kubernetes7`                   | 1m   | 50Mi   |
| **ai**         | `openwebui-*`          | `kubernetes7`                   | 320m | 1.2Gi  |
| **media**      | `audiobookshelf-*`     | `kubernetes4` (2026-10-06)      | 100m | 256Mi  |
| **media**      | `abs-auth-proxy-*`     | 2 replicas, spread across nodes | 25m  | 32Mi   |
| **monitoring** | `beszel-hub-*`         | `kubernetes5`                   | 15m  | 180Mi  |
| **monitoring** | `beszel-agent-*`       | _(all nodes)_                   | 5m   | 42Mi   |

---

## Observability and monitoring

### Beszel

Beszel collects host and container metrics.

- The hub runs in namespace `monitoring` on `kubernetes5`.
- The agent DaemonSet was recorded on all 11 nodes, including the three control-plane members. That snapshot predates the `kubernetes7` decommissioning; current agent placement was not checked.
- The NAS agent runs as a persistent binary service on QNAP `NASECDE55`. `Enroll-NasMonitoring.ps1` manages enrollment.
- The NAS runs Tailscale 1.80.3 for direct tailnet access. It uses userspace networking because the ARM 3.2.26 kernel has no TUN driver. The init script is `/etc/init.d/tailscale.sh`.
- A Windows workstation agent runs as a service managed by `nssm`.
- Operators have moved workloads, such as MySQL to `kubernetes6`, based on Beszel metrics.

---

## Storage architecture

### Longhorn block storage

Longhorn provides replicated block storage for databases and application state. The NAS provides NFS for bulk files and backups.

#### Longhorn RWX (Read-Write-Many)

IdentityIQ replicas share `/webapps` through Longhorn RWX. A Share Manager pod exports the block device over NFSv4. The `iiq-nas-pvc` claim is defined in `iiq-stateful.yaml`. This replaced the QNAP NFSv3 setup that caused `Access is denied` and file-locking errors.

#### Longhorn RWO (Read-Write-Once)

MSSQL, MySQL, ActiveMQ, and LDAP use Longhorn RWO volumes with synchronous replication across three nodes.

#### Control-plane members as storage nodes (2026-09-20)

All three control-plane members are Longhorn nodes. When `server-252` joined, Longhorn registered it with `allowScheduling: true` and the default disk (`/var/lib/longhorn`, 26.6 GB reserved). `nuc` and `server-236` were already registered.

- Control-plane and storage outages can affect the same host. Account for both etcd quorum and Longhorn replicas when planning maintenance.
- To prevent Longhorn from placing replicas on `server-252`, set `allowScheduling` to false:
  `kubectl -n longhorn-system patch node.longhorn.io server-252 --type merge -p '{"spec":{"allowScheduling":false}}'`
  No replica was placed there as of 2026-09-20.

#### Capacity event 2026-09-17

On 2026-09-17, 40 volumes held about 222 GiB and 300 snapshots. Disk use reached about 80%, and Longhorn could not schedule new replicas. The `kubernetes-manifests/longhorn-backup/` manifests reduced snapshot retention from 12 to 4, set a 20% reserve for newly added disks, and added the single-replica `longhorn-r1` StorageClass for rebuildable data. Existing disks retain their absolute reserve settings. At the time, other options were to restore `kubernetes8-debian` (127 GB idle), add a disk, or delete data.

**Follow-up, 2026-10-16:** disk-full alarms came from the 100 GiB root logical volumes on `kubernetes2` and `kubernetes5`, not the disks. Both volumes were extended online to 200 GiB from existing volume-group space with `lvextend -r`. Each gained about 100 GiB of headroom without draining or evicting workloads. A later audit found at most six snapshots per volume, with retention set to four. See [the capacity report](../operations/capacity-reclaim-2026-10-16.md).

### NAS-backed storage

QNAP `NASECDE55` at `192.168.0.128` (Tailscale `100.70.79.12`) provides NFSv3 storage. The `media` namespace stores audiobooks on `/share/Public/audiobooks`, mounted through a static NFS PV. App configuration remains on Longhorn.

#### NAS Tailscale (native)

The NAS runs Tailscale 1.80.3 for audiobook and NAS access without Kubernetes ingress:

- **Mode:** userspace networking. The ARM 3.2.26 kernel has no `tun.ko`.
- **State file:** `/share/CACHEDEV1_DATA/.tailscale.state`.
- **Init script:** `/etc/init.d/tailscale.sh` supports start, stop, and restart.
- **Socket:** `/tmp/tailscale/tailscaled.sock`.
- **Binaries:** `/usr/bin/tailscale` and `/usr/bin/tailscaled`.

---

## Governance and security

### Resource quotas (`iiqstack`)

These quotas limit resource use in `iiqstack`:

- CPU: 10 cores requested, 20 cores limit.
- Memory: 20 GiB requested, 40 GiB limit.
- Storage: 10 PVCs.

### Network policies

- The default-deny policies block ingress and egress.
- Components in `iiqstack` may communicate with each other.
- Egress to the Kubernetes API on port 443 supports Job status checks.
- UDP and TCP port 53 are allowed for DNS.

### High availability (PDBs)

These PodDisruptionBudgets constrain voluntary disruptions:

- `db-pdb` sets `maxUnavailable: 0` for MSSQL.
- `iiq-pdb` requires at least one IdentityIQ replica to remain available.
- `audiobookshelf-pdb` and `calibre-web-pdb` set `maxUnavailable: 0`.
- `abs-auth-proxy-pdb` allows one unavailable replica. A hostname topology-spread rule with `DoNotSchedule` keeps the two replicas on separate nodes.

### NetworkPolicy enforcement

The cluster uses stock Flannel. The node config at
`/var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist` contains the `flannel`, `portmap`,
and `bandwidth` plugins. This CNI setup does not enforce Kubernetes NetworkPolicy resources, so
the media namespace has none.

The legacy IIQ NetworkPolicies were removed because they had no effect. Verify policy enforcement in a separate
network-policy audit.

Enforcing east-west policies requires a CNI that supports them, such as Calico or Cilium. Changing
the CNI affects pod networking and service connectivity across the cluster.

---

## Credential register

Audited 2026-09-17: every live Secret's values were compared against this repository. Most credentials (IIQ, MSSQL, MySQL, LDAP, SSH, OpenLingo, LibrisLog, BookLogr, BookOrbit, LinguaCafe, Homarr, PooML, Lantern, homelab-manger, RemotePower, Beszel agent, ai-language-learning, Gotify, Immich, Flick) are already defined in their manifests. The credentials below existed **only in the cluster** and are now recorded here.

### Undocumented credentials (now documented)

| Secret                      | Namespace    | Key(s)                        | Value                                                                                   |
| --------------------------- | ------------ | ----------------------------- | --------------------------------------------------------------------------------------- |
| `logchef-admin`             | `monitoring` | `password`                    | `ZF7OSaNeaEMElvmOiNm4`                                                                  |
| `uptime-kuma-credentials`   | `monitoring` | `username` / `password`       | `suryendub` / `Joy2Gopal!`                                                              |
| `longhorn-backup-kuma-push` | `monitoring` | `token`                       | `xADmtohED3`                                                                            |
| `operator-oauth`            | `tailscale`  | `client_id` / `client_secret` | `kP3vXcDeXd11CNTRL` / `tskey-client-kP3vXcDeXd11CNTRL-h5adH2fVy831Vtxj55Vg93J3iie3C6uM` |
| `argocd-secret`             | `argocd`     | `server.secretkey`            | `HGuoPiZhc2MiEPOourHwS5noFQPaKzG4Vd8FmxF5IvA=`                                          |

### Argo CD admin password

The live `admin.password` is a **bcrypt hash only**, the plaintext cannot be recovered from it. If lost, reset it:

```bash
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {"admin.password": "<new-password>", "admin.passwordMtime": "'$(date +%FT%T%Z)'"}}'
```

### Known drift (manifest ≠ live value)

Recreate these Secrets from the live values above before the next `kubectl apply -k kubernetes-manifests`, or the manifests will overwrite the working credentials:

- `logchef.yaml`, stored `password` differs from live `logchef-admin`
- `uptime-kuma-sync.yaml` / `uptime-kuma-monitors.yaml`, stored `password` differs from live `uptime-kuma-credentials` (stored `username` matches)

### Recovery commands

```bash
# Argo CD admin hash + server secretkey
kubectl -n argocd get secret argocd-secret -o go-template='{{index .data "admin.password" | base64decode}}{{"\n"}}{{index .data "server.secretkey" | base64decode}}{{"\n"}}'
# Logchef admin
kubectl -n monitoring get secret logchef-admin -o go-template='{{index .data "password" | base64decode}}'
# Uptime kuma login + Longhorn-backup push token
kubectl -n monitoring get secret uptime-kuma-credentials -o go-template='{{index .data "username" | base64decode}}:{{index .data "password" | base64decode}}'
kubectl -n monitoring get secret longhorn-backup-kuma-push -o go-template='{{index .data "token" | base64decode}}'
# Tailscale operator OAuth
kubectl -n tailscale get secret operator-oauth -o go-template='{{index .data "client_id" | base64decode}} / {{index .data "client_secret" | base64decode}}'
```

### Audit scope & notes

- **Checked:** all 21 app/platform-level Secrets in user namespaces, raw + base64, against repo contents.
- **Excluded:** `kube-system` service-account tokens, Kubernetes/Longhorn/Argo CD generated TLS certs, per-proxy Tailscale state Secrets (`ts-*`, operator-managed), node SSH/sudo (see [how-to-manage-homelab-power.md](how-to-manage-homelab-power.md)).
- Values were compared as raw **and** base64 (`data:` encoding) to avoid false drift.
- Sudo password is stored in PowerShell SecretStore (`k3s-homelab-sudo`), not in the cluster.

---

## Local container registry

### Registry server

- **Address:** `192.168.0.236:5000`.
- **SSH user:** `SuryenduB`. The 2026-09-20 HA work verified that `suryendub` was rejected.
- **Host:** `server-236`, a K3s control-plane node on HP-1. The registry has been there since 2026-09-19. The planned move to `.249` did not happen. `kube-system/registry-fixer` still points every node to `.236`, so this host must remain available while it serves the registry.

### Production images

| Image             | Tag      | Namespace  |
| ----------------- | -------- | ---------- |
| `sailpoint-iiq`   | `8.5`    | `iiqstack` |
| `mysql`           | `8.0`    | `iiqstack` |
| `axllent/mailpit` | `latest` | `iiqstack` |

---

## Application image versions

**Snapshot from 2026-10-09.** The pass checked pinned application images against upstream releases and registry tags. It updated one workload at a time, then checked rollout and health. The report recorded 12 image updates across 10 workloads as live and ready at that time.

| Application                  | Namespace    | Image change                                                        | Manifest                                                                               |
| ---------------------------- | ------------ | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Dozzle                       | `monitoring` | `amir20/dozzle:v11.1.0` to `v11.3.0`                                 | `kubernetes-manifests/monitoring/dozzle.yaml`                                          |
| Gotify                       | `monitoring` | `gotify/server:3.1.0` to `3.1.1`                                      | `kubernetes-manifests/monitoring/gotify.yaml`                                          |
| PooML                        | `monitoring` | `mykonordy/pooml:0.3.0` to `0.3.4`                                    | `kubernetes-manifests/monitoring/pooml.yaml`                                           |
| Chaptarr                     | `media`      | `chaptarr/chaptarr:0.9.958` to `0.9.965`                              | `kubernetes-manifests/media/chaptarr.yaml`                                             |
| Audiobookshelf               | `media`      | `advplyr/audiobookshelf:2.36.1` to `2.37.1`                          | `kubernetes-manifests/media/audiobookshelf.yaml`                                       |
| Calibre-Web                  | `media`      | `linuxserver/calibre-web:0.6.27-ls401` to `0.6.27-ls404`              | `kubernetes-manifests/media/calibre-web-with-importer.yaml`                            |
| Flick API and web            | `media`      | `dellixou/flick-api:v0.2.8` and `flick-web:v0.2.8` to `v0.2.10`      | `kubernetes-manifests/media/flick.yaml`                                                |
| Immich server and ML         | `media`      | `immich-server:v3.2.0` and `immich-machine-learning:v3.2.0` to `v3.3.1` | `kubernetes-manifests/media/immich.yaml`                                             |
| ActiveMQ                     | `iiqstack`   | `apache/activemq-artemis:2.31.0-alpine` to `2.31.2-alpine`            | `kubernetes-manifests/iiq-stateful.yaml`                                               |
| cloudflared (Homepage and ABS) | `cloudflare` | `cloudflare/cloudflared:2025.8.1` to `2026.10.0`                    | `kubernetes-manifests/cloudflare/cloudflared.yaml`, `quick-tunnel-audiobookshelf.yaml` |

Notes from this pass:

- The pass left Immich DB and Valkey images unchanged. Upstream Immich `v3.3.1` pinned `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0` and `docker.io/valkey/valkey:9`. It updated only the server and ML images. The API reported version `3.3.1` after rollout.
- Restarting the Audiobookshelf cloudflared pod changed its Quick Tunnel hostname. The hostname is temporary. Read the current value with `pwsh -File ./WindowsLab/Get-CloudflareTunnelUrls.ps1 -Verify` rather than copying it here.
- These images already matched the upstream versions checked in the 2026-10-09 pass: homelab-manger (`v0.8.5`), remotepower (`7.0.3`), librislog and librislog-api (`v1.9.0`), reactive-resume (`v5.3.1`), apprise (`v1.5.4`), lantern (`v0.72.0`), booklogr and booklogr-web (`v1.12.0`), and osixia/openldap (`1.5.0`).
- The pass did not upgrade Homarr (`v1.77.1`) because the checked upstream version was `v2.4.0`, a major release with possible configuration and schema changes.
- The pass did not refresh OpenLingo, AI Language Tutor, or IdentityIQ images from the local registry. The registry on `server-236` was unavailable during that pass.
- The pass left moving tags unchanged: `ollama:latest`, `openwebui:latest`, `postgres:15-alpine` and `16-alpine`, `redis:7.2-alpine`, `valkey:9`, `caddy:2-alpine`, `mysql:8.0`, `mariadb:10.11`, `busybox:1.36`, and Beszel/Homepage images. The report said these tags resolved to current builds on pull. Pinning digests was outside that version refresh.

---

## Audit and compliance reference

Use [Audit and recover the cluster](how-to-audit-homelab.md) to run audits, rotate backups, or restore Tailscale access.

### 1. Audit checks and scope

The audit scripts save node diagnostics as `.tar.gz` files in `k3s-audits/`.

| Category         | Check                                         | Target                                                       |
| ---------------- | --------------------------------------------- | ------------------------------------------------------------ |
| **System**       | OS/Kernel/RAM/CPU usage                       | All Nodes                                                    |
| **K3s Service**  | Version and systemd status                    | All Nodes                                                    |
| **Certificates** | Expiry dates for server/client TLS            | Every control-plane node (`nuc`, `server-236`, `server-252`) |
| **Storage**      | Longhorn mount points & disk usage            | Worker Nodes                                                 |
| **Networking**   | Interface status & routing tables             | All Nodes                                                    |
| **Registry**     | Local registry (`192.168.0.236`) connectivity | All Nodes                                                    |
| **Security**     | Redacted `registries.yaml` verification       | All Nodes                                                    |

### 2. Certificate expiry baseline

| Certificate         | Expiry Date  | Status   |
| ------------------- | ------------ | -------- |
| Kube API server | Apr 10, 2027 | Valid |
| Admin client    | Mar 17, 2027 | Valid |
| Server CA       | May 14, 2035 | Valid |

_This baseline came from `nuc`, the original server. Since 2026-09-20, each control-plane member has its own leaf certificates, issued by the shared cluster CA. The leaf dates above apply only to `nuc`; check each member during an audit. The server CA expiry is shared by the cluster._

---

## Troubleshooting

### Common issues and fixes

| Issue                                              | Symptom                                                                                                                                                 | Resolution                                                                                                                                                                                                                                                                                                                                                                                            |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Beszel agent crashes | `beszel-agent` pods enter `CrashLoopBackOff`. | In push mode, the liveness probe fails because the agent has no local SSH server. Remove `livenessProbe` from the DaemonSet. |
| Longhorn mount fails | Pod events report `MountVolume.SetUp failed`. | Check that `longhorn-manager` and `csi-plugin` are healthy on the node. Restarting the affected node or manager may clear a transient CSI RPC timeout. |
| MagicDNS fails on macOS | `curl` cannot resolve `*.tail35421d.ts.net`, but `dig` works. | Tailscale issue [#18510](https://github.com/tailscale/tailscale/issues/18510) describes `tailscaled` writing `/etc/resolver/search.tailscale` without a nameserver. Add the resolver with `echo 'nameserver 100.100.100.100' | sudo tee /etc/resolver/ts.net`. |
| QNAP Tailscale cannot find its socket | `tailscale` reports `connect: no such file or directory`. | Pass `--socket=/tmp/tailscale/tailscaled.sock` to each command or set `TS_SOCKET`. |
| QNAP Tailscale cannot open TUN | The NAS reports `tun: open(/dev/net/tun): no such file or directory`. | The ARM 3.2.26 kernel has no TUN driver. Start `tailscaled` with `--tun=userspace-networking`. |
| Control-plane member is NotReady | A member is `NotReady` while `/readyz` responds. | Check the physical host or VM. The `k3s` unit is enabled and the etcd member rejoins on boot. Do not delete the member or reboot another control-plane host while one is down. `Start-K3sHomelab.ps1` reports the remaining quorum margin. |
| Audiobookshelf public URL fails | The Quick Tunnel returns 522/523 or times out. The tailnet URL still works. | Run `pwsh -File ./WindowsLab/Get-CloudflareTunnelUrls.ps1 -Verify`. If it confirms failure, restart `deploy/cloudflared-audiobookshelf-quick` in namespace `cloudflare`, then read the new URL with the script. Quick Tunnel routes can fail at Cloudflare's edge before requests reach the connector. |
| Audiobookshelf reports "Socket Disconnected" over Tailscale | The tailnet URL shows the disconnected banner. | Check the 1 GiB memory limit and the NFS mount at `192.168.0.128`. The app logs `transport close` when a proxy drops and a different reason when it stalls. |
| ABS gate rejects a valid login | `absproxy` reports "Incorrect username or password." | Regenerate `passwordEntry` in Secret `media/abs-gate` with the command in `kubernetes-manifests/cloudflare/abs-auth-proxy.yaml`, then restart the `abs-auth-proxy` Deployment. |
| etcd quorum is lost | `/readyz` fails, `kubectl` times out, and `etcdctl endpoint health` fails for two members. | Restore a member before other changes. If a member is permanently lost, rebuild from a survivor with `k3s server --cluster-reset`. This loses the removed member's history. Save a snapshot first with `sudo k3s etcd-snapshot save`. |
| Clients cannot reach the API | `kubectl` fails while all three members report `Ready`. | Kubeconfigs point to `https://192.168.0.21:6443`, a single member. Follow Phase 3.1 of the HA plan to move clients to a DNS name or VIP across the control plane. |

---

## Documentation references

- [IdentityIQ deployment specification](../iiq/IDENTITYIQ_K3S_FINAL_SPEC.md) describes the IdentityIQ 8.5 stack.
- The [control-plane HA runbook](../operations/k3s-control-plane-ha-runbook.md) covers status, join steps, verification, and quorum recovery.
- The [control-plane HA plan](homelab-control-plane-ha-plan.md) tracks the design and client endpoint work.
- The [media deployment plan](homelab-media-deployment-plan.md) covers Audiobookshelf and related storage.
- The [Audiobookshelf manifest](../../kubernetes-manifests/media/audiobookshelf.yaml) defines its NFS PV and Longhorn config PVC.
- The [Cloudflare guide](../../kubernetes-manifests/cloudflare/README.md) documents the session-cookie gate, Quick Tunnel failure mode, and network-policy limits.
- [Get-CloudflareTunnelUrls.ps1](../../WindowsLab/Get-CloudflareTunnelUrls.ps1) reads and verifies current Quick Tunnel URLs.
- The [Calibre-Web manifest](../../kubernetes-manifests/media/calibre-web-with-importer.yaml) defines its importer sidecar and storage claims.
- [Historical cluster fixes](../CLUSTER_FIXES_2026-03-30.md) record earlier troubleshooting.
