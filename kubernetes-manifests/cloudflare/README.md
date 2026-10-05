# Cloudflare Tunnel -> Homepage

Publishes the in-cluster `homepage/homepage` Service publicly via Cloudflare Tunnel.

**Status (verified 2026-10-06):** Quick Tunnel LIVE at
`https://specialized-dpi-repair-vault.trycloudflare.com` (HTTP 200).
`deploy/cloudflared-homepage-quick` 1/1 Running in ns `cloudflare`.
Homepage itself: `deploy/homepage` 1/1 Running in ns `homepage`,
also reachable on the Tailnet via the Tailscale operator.

## Option A: Quick Tunnel (LIVE NOW, no token)

Ephemeral `*.trycloudflare.com` URL, no Cloudflare account needed.
URL changes on every pod restart. No uptime SLA — demo/sharing use.

```bash
kubectl apply -f quick-tunnel-homepage.yaml
kubectl -n cloudflare logs -l app=cloudflared-homepage-quick --tail=20  # find URL
curl -s -o /dev/null -w '%{http_code}\n' <URL>  # expect 200
```

Live URL (2026-10-05): `https://specialized-dpi-repair-vault.trycloudflare.com` -> HTTP 200 verified.

How it works:
- `cloudflared tunnel --url http://homepage.homepage.svc:80`
- `--http-host-header=homepage.homepage.svc` rewrites the Host header so
  Homepage's `HOMEPAGE_ALLOWED_HOSTS` check passes without knowing the
  random trycloudflare hostname in advance.

## Option B: Permanent Tunnel (needs token + own domain)

1. Dashboard: Networking -> Tunnels -> Create Tunnel, copy token from
   `cloudflared tunnel run --token eyJhIjoi....`
2. `kubectl -n cloudflare create secret generic cloudflared-token \
     --from-literal=token='<PASTE>' --dry-run=client -o yaml | kubectl apply -f -`
   (or paste into `permanent-tunnel-homepage.yaml` Secret, homelab allows plaintext).
3. In dashboard Routes tab add Published Application route:
   `home.example.com -> http://homepage.homepage.svc:80`
   (update `home.example.com` in the ConfigMap ingress to match).
4. `kubectl apply -f permanent-tunnel-homepage.yaml`

Note: NOT wired into top-level `kustomization.yaml` on purpose —
Quick Tunnel is ephemeral/demo, Permanent has a placeholder token that sleeps
until a real token is set.

Caveats:
- Homepage `siteMonitor` URLs point at Tailnet/cluster DNS names, so status
  indicators may show down over the public internet — cosmetic only.
- Homepage validates `Host` against `HOMEPAGE_ALLOWED_HOSTS`; the manifests
  use `--http-host-header=homepage.homepage.svc` (quick) /
  `httpHostHeader: homepage.homepage.svc` (permanent) so no Homepage change
  is needed.
