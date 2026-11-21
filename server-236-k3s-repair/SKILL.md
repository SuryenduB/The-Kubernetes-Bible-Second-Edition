---
name: server-236-k3s-repair
description: Repair server-236 when its k3s service sticks in `activating`, the node stays NotReady, or the journal repeats etcd "cluster ID mismatch". Covers the 0-byte `k3s.service.env` fork, stale etcd member row, archive-and-rejoin, quorum verification, and rollback. Use for server-236 control-plane/etcd recovery, not for generic worker or Longhorn issues.
---

# server-236 k3s repair

Repair one specific failure: `server-236` boots, SSH and its registry work, but k3s
never becomes `active` and the node stays `NotReady`.

The whole procedure turns on one word:

**Lineage.** etcd cluster IDs never change for a data directory. If `server-236`
reports a different `local-member-cluster-id` from `nuc`, it is a **fork**, not a
network problem. Fix the lineage, not the firewall.

Two supporting words:

- **Env** — a 0-byte `/etc/systemd/system/k3s.service.env` means the bare
  `k3s server` unit got no `K3S_URL` and bootstrapped its own single-node etcd.
  This is the usual 2026-11 root cause.
- **Row** — the live cluster can still hold a `started` member row for the old
  `server-236` at the same peer address. A fresh join conflicts with that row
  until it is removed.

## When to use

- `kubectl get nodes` shows `server-236 NotReady`.
- `systemctl is-active k3s` on `server-236` is `activating`, never `active`.
- Journal repeats `request cluster ID mismatch` or
  `request sent was ignored by remote peer due to cluster ID mismatch`.
- `/etc/systemd/system/k3s.service.env` is empty or missing `K3S_URL`.

## Not for

- Worker-node `NotReady`, Longhorn attach/mount failures, NFS backupstore
  incidents, or cluster-wide storage storms.
- A member that already reports the **same** cluster ID as `nuc` — investigate
  networking, certificates, and kubelet before touching etcd state.
- `server-252` recovery: same shape, but apply the runbook and the registry's
  SSH user rules separately.
- Rebooting or cordoning the other control-plane members. Never leave one
  member running while the other two reboot.

## Guardrails

| Invariant | Why |
| :-- | :-- |
| Node IP and SSH user come from `WindowsLab/homelab-nodes.json` | `server-236` uses `SuryenduB`; lowercase `suryendub` is rejected |
| Sudo password comes from SecretStore `k3s-homelab-sudo` | Never commit it or paste it into a command |
| Archive the stale `db` directory; never `rm -rf` it | It is the rollback point (873 MB was the real size) |
| Snapshot etcd on `nuc` before membership changes | Cheap insurance before `member remove` |
| Remove the stale member row only while `nuc` and `server-252` are both healthy | Quorum must stay 2/2 |
| Put `K3S_TOKEN_FILE` in the env file, not a literal token | The token hash already matches; the secret stays in its file |
| Keep `K3S_URL=https://192.168.0.21:6443` in the env file permanently | An empty env file is what forked the member in the first place |
| Use `/usr/local/bin/etcdctl` on `nuc` with certs in `/var/lib/rancher/k3s/server/tls/etcd/` | It is the documented ground truth for membership |

Run privileged remote commands with the sudo password piped ahead of the script,
so it never lands in the command line:

```bash
PW=$(pwsh -NoProfile -Command 'Get-Secret -Name k3s-homelab-sudo -AsPlainText')
{ echo "$PW"; cat <<'REMOTE'
  # ... root commands here ...
REMOTE
} | ssh -o BatchMode=yes -o ConnectTimeout=5 SuryenduB@192.168.0.236 'sudo -S -p "" bash -s'
```

Use the same pattern with `suryendub@192.168.0.21` for `nuc`.

## Procedure

### 1. Prove the fork

**Done when** the env file size, journal cluster IDs, and token hashes are
recorded and the live member list is in hand.

```bash
ssh -o BatchMode=yes SuryenduB@192.168.0.236 'systemctl is-active k3s; stat -c "%s bytes" /etc/systemd/system/k3s.service.env; ss -lntp | grep -E ":(10250|6443)"'
ssh -o BatchMode=yes SuryenduB@192.168.0.236 'journalctl -u k3s --since "-30 min" --no-pager | grep -E "cluster ID mismatch" | tail -5'
# compare token hashes: identical means K3S_TOKEN_FILE is safe
ssh -o BatchMode=yes SuryenduB@192.168.0.236 'sha256sum /var/lib/rancher/k3s/server/token'
ssh -o BatchMode=yes suryendub@192.168.0.21   'sudo sha256sum /var/lib/rancher/k3s/server/token'
```

The fork signature is `activating`, a 0-byte env file, closed port `10250`, and
`local-member-cluster-id` differing from the live `ccb62f2762529097`.

Live membership (on `nuc`, with the cert variables):

```bash
C="--cacert /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt --cert /var/lib/rancher/k3s/server/tls/etcd/server-client.crt --key /var/lib/rancher/k3s/server/tls/etcd/server-client.key"
/usr/local/bin/etcdctl --endpoints https://127.0.0.1:2379 $C member list -w table
/usr/local/bin/etcdctl --endpoints https://192.168.0.21:2379,https://192.168.0.252:2379 $C endpoint health -w table
```

Note the stale `server-236-dc51ed1a` row's ID and verify both survivors are
`true`. If either is unhealthy, stop: restore quorum first.

### 2. Prepare the survivors

**Done when** an etcd snapshot exists and the fork is stopped with its data archived.

On `nuc`: `sudo k3s etcd-snapshot save --name pre-rejoin-server-236-<date>`.

On `server-236`, via the privileged pattern above:

```bash
systemctl stop k3s
STAMP=$(date +%Y%m%d-%H%M%S)
mv /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/server/db-backup-$STAMP
printf 'K3S_URL=https://192.168.0.21:6443\nK3S_TOKEN_FILE=/var/lib/rancher/k3s/server/token\n' > /etc/systemd/system/k3s.service.env
chmod 600 /etc/systemd/system/k3s.service.env
```

Check `df -h /` has at least 200 MB headroom before the `mv`. A prior archive was
873 MB. The local registry is a Docker container and stays up while k3s is stopped.

### 3. Drop the stale row, then start the member

**Done when** the old row is gone from `nuc` and `server-236` reports `active`.

On `nuc`, remove only the noted stale ID (example `7b665c83784e699e`):

```bash
/usr/local/bin/etcdctl --endpoints https://127.0.0.1:2379 $C member remove <old-id>
```

Back on `server-236`: `systemctl daemon-reload && systemctl start k3s`.

First boot logs often show `Polling for API server readiness` with post-start
hooks failing; that is warm-up. Wait ~45 s before judging.

### 4. Verify the repair

**Done when all of these hold** — partial success is not success:

```bash
ssh -o BatchMode=yes SuryenduB@192.168.0.236 'systemctl is-active k3s'   # active
kubectl get nodes | grep server-236                                      # Ready
kubectl get --raw /readyz                                                # ok
journalctl -u k3s --since "-5 min" | grep "cluster ID mismatch"          # no new entries
curl -fsS http://192.168.0.236:5000/v2/                                  # registry still up
```

On `nuc`, re-run the member list and endpoint health: three rows `started`, one
lineage, a **new** member ID for `server-236`, and all three endpoints `true`.

Expect the fresh kubelet to reap pods stuck `Terminating` and to reduce
`ContainerCreating` counts. Longhorn volumes and other app-level problems are a
separate follow-up; do not fold them into this repair.

## Rollback

The archived `db-backup-<stamp>` is the rollback point. If the join fails, stop
k3s and restore that directory rather than deleting it. Keep the archive for at
least a week. Do not restore an old empty env file: that recreates the fork.
