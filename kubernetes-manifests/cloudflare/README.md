# Cloudflare Tunnel -> Homepage + Audiobookshelf

Publishes selected in-cluster web UIs publicly via Cloudflare Tunnel.

**Status (verified 2026-10-06):** both Quick Tunnels LIVE from `nuc`, HTTP 200.

| Service | URL | Origin |
|---|---|---|
| Homepage | `https://ensemble-hip-lens-capable.trycloudflare.com` | `http://homepage.homepage.svc:80` |
| Audiobookshelf | `https://yeah-quarter-pads-guitars.trycloudflare.com` | `http://audiobookshelf.media.svc:80` |

Quick Tunnel URLs change on every pod restart — read the current ones with:

```bash
kubectl -n cloudflare logs -l app=cloudflared-homepage-quick --tail=20      | grep trycloudflare
kubectl -n cloudflare logs -l app=cloudflared-audiobookshelf-quick --tail=20 | grep trycloudflare
```

## Files

| File | Purpose |
|---|---|
| `cloudflared.yaml` | Namespace, ServiceAccount, empty Role, ConfigMap (both origins), Homepage Quick Tunnel |
| `quick-tunnel-audiobookshelf.yaml` | Audiobookshelf Quick Tunnel (separate Deployment: `--url` bakes in one origin) |
| `permanent-tunnel-homepage.yaml` | Token-based tunnel for a real domain, both origins, 2 replicas — dormant until a token is set |

## Security posture

**Published (browser-facing UIs only):** Homepage, Audiobookshelf.

**Never publish here:** `iiq`, `db`, `db-mysql`, `ssh`, every `postgres`/`redis`/
`mariadb` Service, the K3s API (6443) and Longhorn. Those stay on Tailscale/LAN.
A tunnel origin is public internet — anything with a login screen becomes an
attack surface.

A Quick Tunnel has **no authentication**: whoever has the URL reaches the
service's own login form. Fine for sharing, not for a permanent URL. For that use
the permanent tunnel plus **CF Access** (email OTP or Google) in front.

## How it works

- `--http-host-header <svc>` rewrites the Host header the origin sees, so
  Homepage's `HOMEPAGE_ALLOWED_HOSTS` and Audiobookshelf's virtual-host check
  pass without knowing the random `*.trycloudflare.com` hostname in advance.
- Metrics are enabled on `:2000`; the readiness/liveness probes use cloudflared's
  own `/ready`, so the pod is only Ready once it is actually registered.
- Long-running audio streams are unaffected: cloudflared buffers origin
  requests, and the permanent tunnel raises `keepAliveTimeout` to 90s.

## Pod hardening (kubernetes-specialist review 2026-10-06)

Applied to every connector, against that skill's MUST-DO/MUST-NOT list:

- `image: cloudflare/cloudflared:2025.8.1` — pinned, never `:latest`.
- `securityContext`: `runAsNonRoot` (uid 65532), `seccompProfile: RuntimeDefault`,
  `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`,
  `capabilities: drop ["ALL"]`, `emptyDir` `/tmp` for writes.
- Resource requests **and** limits on every container.
- Readiness + liveness probes on `/ready`.
- `serviceAccountName: cloudflared` with `automountServiceAccountToken: false` and
  an intentionally empty Role — cloudflared only dials outbound to Cloudflare's
  edge and needs no Kubernetes API access.
- Placement: `nodeAffinity` on `node-role.kubernetes.io/control-plane` (not
  `kubernetes.io/hostname`, which the control-plane VMs do not carry), plus
  tolerations for both the legacy `master` and current `control-plane` NoSchedule
  taints. This keeps the tunnel off `kubernetes7` (failing disk).

Permanent tunnel runs 2 replicas: it is the only public entry point, so it must
survive a single node loss.

## Option B: Permanent Tunnel (needs token + own domain)

1. Dashboard: Networking -> Tunnels -> Create Tunnel, copy the token from
   `cloudflared tunnel run --token eyJhIjoi....`
2. `kubectl -n cloudflare create secret generic cloudflared-token \
      --from-literal=token='<PASTE>' --dry-run=client -o yaml | kubectl apply -f -`
   (homelab convention allows a plaintext secret; the Secret block in the manifest
   is only a fallback)
3. Set both hostnames in the ConfigMap ingress of `permanent-tunnel-homepage.yaml`
   (`home.example.com`, `audio.example.com`) to match your domain, then apply it.
4. Put CF Access in front of both hostnames.

Neither file is wired into the top-level `kustomization.yaml` on purpose: the
quick tunnels are ephemeral and the permanent one sleeps until a real token is
set.