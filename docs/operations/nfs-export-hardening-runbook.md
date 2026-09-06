# NFS Export Hardening Runbook — QNAP NASECDE55

**Status**: ⚠️ OPEN — exports are currently `*(rw,no_root_squash)` (world-accessible on LAN)  
**Risk**: Any host that reaches 192.168.0.128 via LAN can mount and write to the Longhorn backup store or the Public share as root.  
**Required**: Restrict to K3s node IPs 192.168.0.19–.26 (kubernetes1–kubernetes8-debian) + 192.168.0.21 (nuc).

---

## Current (insecure) state

From `/var/lib/nfs/etab` on NUC (verified 2026-09-06):

```
/share/CACHEDEV1_DATA/longhorn  *(rw,sync,no_subtree_check,no_root_squash,insecure)
/share/Public                   *(rw,sync,no_subtree_check,no_root_squash,insecure)
```

The `*` wildcard means any LAN host can mount and write as root.

---

## Target (hardened) state

Restrict each share to the 9 K3s node IPs only:

| IP | Node |
|----|------|
| 192.168.0.19 | kubernetes1 |
| 192.168.0.20 | kubernetes2 |
| 192.168.0.21 | nuc (control-plane) |
| 192.168.0.22 | kubernetes3 |
| 192.168.0.23 | kubernetes4 |
| 192.168.0.24 | kubernetes5 |
| 192.168.0.25 | kubernetes6 |
| 192.168.0.26 | kubernetes7 |
| 192.168.0.27 | kubernetes8-debian |

**Expected `/etc/exports` after change:**

```
/share/CACHEDEV1_DATA/longhorn  192.168.0.19(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.20(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.21(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.22(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.23(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.24(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.25(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.26(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.27(rw,sync,no_subtree_check,no_root_squash,insecure)
/share/Public                   192.168.0.19(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.20(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.21(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.22(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.23(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.24(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.25(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.26(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.27(rw,sync,no_subtree_check,no_root_squash,insecure)
```

---

## How to apply via QNAP Web UI (recommended — UI keeps QTS state consistent)

> ⚠️ QTS Web UI "Apply" **restarts nfsd** (observed 2026-09-06). Clients get
> `input/output error` for ~90 s. Schedule during a backup maintenance window
> (e.g. after 04:30 UTC when backup-daily-check has finished).

1. Open **Control Panel → Privilege → Shared Folders**.
2. Click the folder row → **Edit Shared Folder Permissions**.
3. Switch to **NFS host access** tab.
4. For each of the two shares (`longhorn` and `Public`):
   - Delete the existing `*` (wildcard) rule.
   - Add one rule per node IP (see table above):  
     - **Host**: `192.168.0.19` … `192.168.0.27`  
     - **Access**: `Read/Write`  
     - Ensure the row **checkbox is ticked** (unticked rows are silently ignored — confirmed 2026-09-06).
5. Click **Apply**.

### Alternative: QNAP CLI (SSH as admin)

SSH to `admin@192.168.0.128` and run:

```bash
# Back up current exports first
cat /etc/exports > /tmp/exports.bak && echo "Backed up to /tmp/exports.bak"

# Write the hardened exports file
cat > /etc/exports << 'EOF'
/share/CACHEDEV1_DATA/longhorn  192.168.0.19(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.20(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.21(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.22(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.23(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.24(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.25(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.26(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.27(rw,sync,no_subtree_check,no_root_squash,insecure)
/share/Public  192.168.0.19(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.20(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.21(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.22(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.23(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.24(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.25(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.26(rw,sync,no_subtree_check,no_root_squash,insecure) 192.168.0.27(rw,sync,no_subtree_check,no_root_squash,insecure)
EOF

# Reload exports (graceful — no nfsd restart)
exportfs -ra && echo "Exports reloaded"

# Verify
exportfs -v
```

> ⚠️ QTS may overwrite `/etc/exports` on the next NFS settings save via UI.
> After any Web UI NFS change, **re-verify** with `cat /etc/exports` via SSH.
> The CLI approach is therefore fragile on QNAP; prefer the Web UI approach
> so QTS's own database stays in sync.

---

## Verification (run from NUC after applying)

```bash
# From NUC (192.168.0.21) — should still work
showmount -e 192.168.0.128

# From NUC — manual mount test (must succeed)
mkdir -p /tmp/nfs-test && \
  mount -t nfs4 192.168.0.128:/longhorn /tmp/nfs-test && \
  ls /tmp/nfs-test/backupstore/ && \
  umount /tmp/nfs-test && \
  echo "longhorn mount OK"

# Check /var/lib/nfs/etab on NUC — no wildcard should appear
grep '\*' /var/lib/nfs/etab && echo "WARN: wildcard still present" || echo "OK: no wildcard"

# Verify Longhorn backup target is still reachable
kubectl -n longhorn-system get backuptargets.longhorn.io -o jsonpath='{.items[*].status.available}'
# Expected: true
```

---

## Impact on macOS workstation

The macOS MacBook (192.168.0.x — varies by DHCP) **will lose NFS access** to
the `longhorn` and `Public` shares after this change. That is the intended
outcome — the Mac never needed direct NFS access; it uses Tailscale + SSH
(or SAMBA which is unaffected). Verify Tailscale-only operations remain intact.

---

## Audit confirmation

After applying, record in `Backup_Strategy.md §6 Open items`:

```markdown
- [x] Harden NFS exports: restricted `longhorn` and `Public` to node IPs
      192.168.0.19–.27. Applied YYYY-MM-DD. Verified via showmount + kubectl.
```
