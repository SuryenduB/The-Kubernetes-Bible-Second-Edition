# K3s Control-Plane HA Runbook

## Status (2026-09-20): EXECUTED

The single-server limitation below is **closed**. The cluster now runs a three-member
embedded-etcd control plane:

```text
nuc           192.168.0.21   server + embedded etcd   (primary API endpoint, joined: original)
server-236    192.168.0.236  server + embedded etcd   (joined: 2026-09-19)
server-252    192.168.0.252  server + embedded etcd   (joined: 2026-09-20)
```

Evidence recorded when `server-252` joined:

```bash
# etcdctl member list -> three started members (nuc-, server-236-, server-252-<hash>)
# kubectl get nodes   -> nuc, server-236, server-252 all Ready with "control-plane,etcd,master"
# endpoint health     -> all three https://<server>:2379 = true
```

Quorum was then proven by stopping one member and re-checking the API:

```bash
# on server-252
sudo systemctl stop k3s
# from nuc, while server-252 was down: 'ok' (the API stayed up on 2 of 3 members)
k3s kubectl get --raw=/readyz
# recovery
sudo systemctl start k3s      # member returned to "started", node Ready, EtcdIsVoter=True
```

> ⚠️ **Follow-up incident (same day):** the `server-252` VM then went offline at the
> **hypervisor level** (~15 min after joining) - no ICMP, ports 22/6443/2379/8472 closed.
> The cluster was unaffected because quorum is 2 of 3 (`/readyz` stayed `ok`; `.21`/`.236`
> endpoint health `true`, `.252` `false`), and **no Longhorn replica had been placed on it**,
> so no volume was affected. The member is retained (not removed) and the guest's `k3s` unit
> is enabled, so starting the VM restores the third master automatically. Full analysis,
> hardening advice and the `/tmp` cleanup still owed on the guest are in
> [`docs/homelab/homelab-control-plane-ha-plan.md`](../homelab/homelab-control-plane-ha-plan.md)
> ("Follow-up incident").

### Historical limitation (2026-09-06, now resolved)

`nuc` (`192.168.0.21`) was the only K3s server, so powering off NUC made
`192.168.0.21:6443` unavailable; Kubernetes manifests could not change that. Host-level
K3s installation plus the server token were required, and the hosts were not reachable at
the time. See `docs/homelab/homelab-control-plane-ha-plan.md` for the original analysis.

### Outstanding gap (client-side endpoint)

The control plane tolerates the loss of any one server, but **clients still point at a
single address**: kubeconfigs, WindowsLab scripts and monitors use
`https://192.168.0.21:6443`. Losing `nuc` therefore still breaks client access until the
endpoint becomes a VIP/DNS name spanning all three servers (plan §Phase 3.1).

## Target topology (achieved)

Three K3s servers with embedded etcd:

```text
nuc           192.168.0.21   server + embedded etcd
server-236    192.168.0.236  server + embedded etcd
server-252    192.168.0.252  server + embedded etcd
```

No existing Ubuntu worker (`kubernetes1`-`8`) needed promotion - dedicated hosts were used
instead (`.236` = HP-1, `.252` = Hyper-V VM `k3s-master`). Keep an odd number of servers:
three tolerate one server failure; five tolerate two. Do not run an even-numbered control
plane merely to use more machines - a **two**-member etcd cluster tolerates *zero* failures.

> ⚠️ Powering off control-plane members is now quorum-sensitive: any two of the three must
> stay up. `WindowsLab/homelab-nodes.json` therefore lists all three in `survivors` (minimal
> mode) and `neverCordon` (never drained), and `WindowsLab/shutdown_homelab.ps1` powers the
> control plane off last, after the workers, with the primary endpoint (`nuc`) last of all.

## Preconditions

Before changing a host:

1. Confirm all three machines have stable addresses and synchronized clocks.
2. Back up K3s datastore state and validate that the backup can be read.
3. Record the installed K3s version on NUC and use the same version on new servers.
4. Confirm TCP 6443, 2379, and 2380 are allowed between server nodes.
5. Confirm the server token is available on NUC or in the protected backup; never
   commit it to Git or paste it into logs.
6. Confirm Longhorn has healthy replicas before taking a node out of service.

## Migration outline

Take an etcd snapshot first, then join the new server with the existing server URL and
token, pinned to the cluster's version:

```bash
# on the existing server (nuc)
sudo k3s etcd-snapshot save --name pre-join-<host>

# on the new server (as root)
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.34.6+k3s1' sh -s - server \
  --server https://192.168.0.21:6443 \
  --token '<read from protected secret storage>' \
  --node-ip <new-server-ip> --node-external-ip <new-server-ip> \
  --flannel-iface eth0 --node-name server-<last-octet>
```

Repeat for each additional server. Verify the etcd member list and `kubectl get nodes`
before proceeding to the next one. Then configure clients and Uptime Kuma to use a stable
load-balanced API endpoint or a DNS name backed by the three server addresses. Do not
point clients at a single server IP as the long-term endpoint.

After each host joins, validate:

```bash
kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose'
kubectl -n kube-system get pods -o wide
kubectl -n longhorn-system get nodes.longhorn.io
```

Note: K3s no longer sets the legacy `node-role.kubernetes.io/master` label on a fresh
join (v1.34 sets `control-plane` + `etcd`). It is applied explicitly for parity with the
older members:

```bash
kubectl label node server-<last-octet> node-role.kubernetes.io/master=true --overwrite
```

Only after the new servers are healthy should NUC be rebooted as a controlled
failure test. During the test, verify the API endpoint, Longhorn attachment,
Uptime Kuma, and each application monitor. Restore NUC and confirm etcd returns
to a healthy three-member quorum.

## Session history

When this runbook was first written (2026-09-06), the migration was not executed because
the available kubeconfig provided Kubernetes API access but no host SSH/console access to
install K3s or retrieve the protected server token. Attempting to change this through
Kubernetes resources alone would not create a second control plane and could leave the
cluster unrecoverable.

- 2026-09-19: `server-236` joined (NUC's SQLite datastore was migrated to embedded etcd -
  `/var/lib/rancher/k3s/server/db/state.db.migrated` - so NUC now bootstraps etcd with no
  extra server flags).
- 2026-09-20: `server-252` joined, completing quorum. Membership, node roles, endpoint
  health and a one-member-loss API test were all verified (see Status above).

Still open: the client-side endpoint (a VIP/DNS name for `:6443`) and the fact that
`.236`'s Docker registry and `server-252`'s Longhorn disk make two of the three control-plane
hosts carry non-control-plane duties - see the open items in
[`docs/homelab/homelab-control-plane-ha-plan.md`](../homelab/homelab-control-plane-ha-plan.md).
