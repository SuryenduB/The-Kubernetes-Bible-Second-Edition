# 🧪 K3s Homelab Documentation

## 📅 Last Update Date

<2026-03-18>

---

## 🗺️ Architecture Diagram

![Homelab Architecture](homelab_architecture.png)

---

## 🚀 Application Access & URLs

| App Name      | Access URL                                | Description                     | Status  |
| :------------ | :---------------------------------------- | :------------------------------ | :------ |
| **OpenWebUI** | [http://openwebui.local](http://openwebui.local) | AI Chat Interface (Llama3/Phi3) | ✅ UP   |
| **IdentityIQ**| [http://identityiq.example.com/identityiq](http://identityiq.example.com/identityiq) | SailPoint Identity Governance   | ✅ READY|
| **phpLDAPadmin**| [http://phpldapadmin.example.com](http://phpldapadmin.example.com) | LDAP Directory Management       | ✅ UP   |
| **MailHog**   | [http://192.168.0.21:30266](http://192.168.0.21:30266) | Local Email Testing Server      | ✅ UP   |
| **ArgoCD**    | [https://argocd.example.com](https://argocd.example.com) | GitOps Cluster Management       | ✅ UP   |

> **📡 DNS Note:** To access these `.local` or `.example.com` domains from your browser, ensure your local `hosts` file (or DNS server) maps these hostnames to any of your node IPs (e.g., `192.168.0.21`).

---

## 🖥️ System Overview

| Hostname     | Chassis        | OS Version           | Kernel                  | Architecture | Hardware Vendor        | Hardware Model                  | Firmware Version                        | Firmware Date      | Firmware Age     |
|--------------|----------------|----------------------|-------------------------|--------------|-----------------------|----------------------------------|-----------------------------------------|--------------------|------------------|
| NUC          | desktop 🖥️     | Ubuntu 24.04.2 LTS   | 6.14.0-37-generic       | x86-64       | Intel Corporation     | DCP847SKE                        | GKPPT10H.86A.0047.2013.1118.1714        | Mon 2013-11-18     | 11y 5m 3w        |
| kubernetes1  | desktop 🖥️     | Ubuntu 24.04.2 LTS   | 6.8.0-78-generic        | x86-64       | FUJITSU               | ESPRIMO Q520                      | V4.6.5.4 R1.47.0 for D3223-C1x          | Mon 2019-08-26     | 5y 8m 2w 1d      |
| kubernetes2  | desktop 🖥️     | Ubuntu 24.04.2 LTS   | 6.8.0-90-generic        | x86-64       | ITMediaConsult AG     | Pentino_H-Series A-4_M_H310-1     | 3202                                    | Sat 2021-07-10     | 3y 10m           |
| kubernetes3  | laptop 💻      | Ubuntu 24.04.2 LTS   | 6.8.0-78-generic        | x86-64       | GIGABYTE              | GB-BSi3-6100                      | F4                                      | Tue 2015-12-08     | 9y 5m 2d         |
| kubernetes4  |                | Ubuntu 24.04.2 LTS   | 6.8.0-78-generic        | x86-64       | Dell Inc.             | OptiPlex 9020                    | A25                                     | 05/30/2019         | 6y 1m 1w         |
| kubernetes5  | desktop 🖥️     | Ubuntu 24.04.2 LTS   | 6.11.0-26-generic       | x86-64       | Acer                  | Aspire XC-605                    | P11-A2                                  | 11/08/2013         | 12y 4m           |
| kubernetes6  | desktop 🖥️     | Ubuntu 24.04.2 LTS   | 6.8.0-90-generic        | x86-64       | FUJITSU               | ESPRIMO Q520                     | V4.6.5.4 R1.46.0 for D3223-C1x          | 08/29/2018         | 7y 6m            |

---

### 🖥️ CPU & Performance Overview

| Hostname     | CPU Model                                      | Cores | Threads | AVX | AI Tier |
|--------------|------------------------------------------------|------:|--------:|:---:|:-------:|
| NUC          | Intel(R) Celeron(R) CPU 847E @ 1.10GHz         |     2 |       2 |  -  | -       |
| kubernetes1  | Intel(R) Core(TM) i5-4590T CPU @ 2.00GHz       |     4 |       4 | ✅  | Tier 1  |
| kubernetes2  | Intel(R) Core(TM) i3-8100 CPU @ 3.60GHz        |     4 |       4 | ✅  | Tier 1  |
| kubernetes3  | Intel(R) Core(TM) i3-6100U CPU @ 2.30GHz       |     2 |       4 | ✅  | Tier 1  |
| kubernetes4  | Intel(R) Core(TM) i5-4590S CPU @ 3.00GHz       |     4 |       4 | ✅  | Tier 2  |
| kubernetes5  | Intel(R) Core(TM) i3-4130 CPU @ 3.40GHz        |     2 |       4 | ✅  | Tier 2  |
| kubernetes6  | Intel(R) Core(TM) i3-4350T CPU @ 3.10GHz       |     2 |       4 | ✅  | Tier 1  |

---

### 🚀 K3s Cluster Health (Balanced)

| Node Name    | Role                 | CPU (%) | Memory (%) | Status |
|--------------|----------------------|--------:|-----------:|--------|
| nuc          | control-plane,master | 14%     | 25%        | Ready  |
| kubernetes1  | worker               | 9%      | 13%        | Ready  |
| kubernetes2  | worker               | 2%      | 7%         | Ready  |
| kubernetes3  | worker               | 3%      | 8%         | Ready  |
| kubernetes4  | worker               | 2%      | 23%        | Ready  |
| kubernetes5  | worker               | 1%      | 20%        | Ready  |
| kubernetes6  | worker               | 5%      | 4%         | Ready  |

---

### 💾 Storage Inventory (100% NAS-Backed)

| Hostname     | Root Disk | Size     | Type | Usage (%) |
|--------------|-----------|----------|------|----------:|
| **NASECDE55**| **NAS**   | **423G** | nfs  | **12%**   |

---

## 🛠️ Installed Add-ons

| Add-on         | Description           | Status |
|----------------|-----------------------|--------|
| **Traefik v39**| Ingress Controller    | ✅ UP   |
| **NFS NAS**    | **Default Storage**   | ✅ UP   |
| **MetalLB**    | LoadBalancer          | ✅ UP   |

---

## 🔁 Backup & Recovery

| Tool      | Status | Schedule/Command                     |
|-----------|--------|--------------------------------------|
| **Cron**  | ✅ Active| Daily at 2:00 AM (to NAS)            |
| **Manual**| ✅ Ready | `sudo /usr/local/bin/k3s-backup-to-nas.sh` |

---

## 📚 Useful Commands

\`\`\`bash
# Start Cluster Routine
Start-K3sHomelab

# Systematic Shutdown
Stop-K3sHomelab
\`\`\`
