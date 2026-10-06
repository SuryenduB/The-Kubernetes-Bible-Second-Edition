# Cloudflare Tunnel -> Homepage + Audiobookshelf

Publishes selected in-cluster web UIs publicly via Cloudflare Tunnel.

**Status (2026-10-06):** both Quick Tunnels LIVE from `nuc`. The Homepage one has
been continuously healthy; the Audiobookshelf one is **intermittently unreachable
at the edge** (~15 min of 522/523/timeouts, then self-recovers, reproduced before
and after a connector restart) — see
[Known failure mode](#known-failure-mode-silent-edge-route-rot). Quick Tunnels are
not reliable enough to be anyone's daily access path.

| Service | URL | Origin |
|---|---|---|
| Homepage | `https://ensemble-hip-lens-capable.trycloudflare.com` | `http://homepage.homepage.svc:80` |
| Audiobookshelf | `https://louis-ecological-tulsa-plug.trycloudflare.com` | `http://audiobookshelf.media.svc:80` |

**Daily use goes to the tailnet URL, not these:**
`http://audiobookshelf.tail35421d.ts.net` held a websocket for **275s+** and then
for a second **150s** run end-to-end, against the same pod, with no connector, no
untrusted edge and no rotating hostname. A Cloudflare socket on the same pod held
60s, failed its upgrade, and failed outright (522/523/000) during the same
sessions. The Quick Tunnel is for sharing a link, not for watching/listening.

Quick Tunnel URLs change on every pod restart — read the current ones with:

```bash
kubectl -n cloudflare logs -l app=cloudflared-homepage-quick --tail=20      | grep trycloudflare
kubectl -n cloudflare logs -l app=cloudflared-audiobookshelf-quick --tail=20 | grep trycloudflare
```

## Files

| File | Purpose |
|---|---|
| `cloudflared.yaml` | Namespace, ServiceAccount, empty Role, ConfigMap (both origins), Homepage Quick Tunnel |
| `quick-tunnel-audiobookshelf.yaml` | Audiobookshelf Quick Tunnel (separate Deployment: `--url` bakes in one origin). Origin is `abs-auth-proxy.media.svc`, not ABS directly |
| `abs-gate.py` | The gate application source — a stdlib-only login form plus HMAC-signed session cookies |
| `render-abs-auth-proxy.py` | Renders `abs-auth-proxy.yaml` from `abs-gate.py` + `abs-auth-proxy.tmpl`. `--check` fails if the committed manifest is stale (use in CI) |
| `abs-auth-proxy.tmpl` | Manifest skeleton, with a placeholder for the gate source |
| `abs-auth-proxy.yaml` | **Generated** — the applied manifest. Do not hand-edit; edit `abs-gate.py` or the template and re-render |
| `permanent-tunnel-homepage.yaml` | Token-based tunnel for a real domain, both origins, 2 replicas — dormant until a token is set, **and unusable until a domain is owned** |

### Changing the gate

```bash
cd kubernetes-manifests/cloudflare
$EDITOR abs-gate.py                       # edit the source
python3 render-abs-auth-proxy.py          # regenerate the manifest
kubectl apply -f abs-auth-proxy.yaml
```

The rendered Deployment carries a `kubernetes-specialist/gate-sha256` pod
annotation derived from `abs-gate.py`. This matters because **Kubernetes does not
restart pods when a mounted ConfigMap changes** — without the hash, a gate fix
would apply successfully and then sit inert in the cluster until some unrelated
restart. The hash makes `kubectl apply` roll the pods. `render-abs-auth-proxy.py
--check` exits non-zero when the committed manifest no longer matches its
sources, which is the CI hook.

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
  own `/ready`. That only reflects the **connector's local view** — see the known
  failure mode below for what it cannot see.
- `--url` mode accepts the origin-request knobs that the permanent tunnel sets in
  its ConfigMap: `--proxy-keepalive-timeout` defaults to **1m30s** (same as the
  permanent tunnel's `keepAliveTimeout: 90s`) and `--proxy-keepalive-connections`
  defaults to **100**. So the Quick Tunnel is *not* missing websocket tuning; when
  it drops a socket it is because the edge has lost the route to the connector,
  not because of an idle keepalive.

## Known failure mode: silent edge-route rot

`trycloudflare.com` Quick Tunnels can stop serving traffic while every signal you
would normally check still says healthy. Measured on 2026-10-06:

```
abs  HTTP=200 200 200 000 000 000 000 000   <- Audiobookshelf, dies within ~15s
hp   HTTP=200 200 200 200 200 200 200 200   <- Homepage, same node, same image
```

- The edge answers `522`/`523`, or times out with no response at all, while the
  Homepage connector on the same node (`nuc`), same image, same QUIC transport
  keeps serving — node, cluster, connector image and origin are all healthy.
  It is per-tunnel, not per-node.
- From a second, unrelated network the same URL returned `522` too.
- It is intermittent and **self-recovers**: one burst ran ~15 min, then the URL
  answered `200` for a 140s sampling window with no intervention. A connector
  `rollout restart` also clears it (fresh tunnel, new URL) — and the replacement
  rotted again within ~4 min.
- The connector was `Running 1/1`, `restarts=0`, `creationTimestamp` 10h old and
  metricically clean: `cloudflared_tunnel_request_errors 0`,
  `cloudflared_tunnel_ha_connections 1`, `cloudflared_tunnel_total_requests 85`
  (78x `200`). The failing requests **never reach the connector**, so they cannot
  be counted, logged or probed from inside the pod.
- `cloudflared tunnel --help` shows `--retries` (default 5) retries
  connection/protocol errors only — cloudflared never noticed one, and the pod
  log held a single `Registered tunnel connection` line for its whole 10h life.
  It does not re-register, so **it does not self-heal**.

Symptom for Audiobookshelf users: its web client is
`transports: ["websocket"]` with `upgrade: false` (no polling fallback), so when
this rot hits, the browser shows the *Socket Disconnected* banner and
socket.io reconnects in a loop. Audiobookshelf's own log looks like:

```
[SocketAuthority] Socket Connected to /audiobookshelf/socket.io 8-AW...
[SocketAuthority] Socket 8-AW... disconnected from client "<user>" after 35922ms (Reason: transport close)
```

What it is *not*: an idle-timeout, a keepalive, or an unhealthy connector — see
§How it works for the keepalive defaults that rule that out.

`--region <name>` is **not** a usable workaround: `--region fra` makes cloudflared
fail its own SRV lookup and crash-loop
(`Could not lookup srv records on _fra-v2-origintunneld._tcp.argotunnel.com`).
One clue worth knowing: the healthy Homepage connector registered to edge `fra21`,
while both broken Audiobookshelf connectors registered to `txl01`.

Detect it with the repo's own tooling — it probes each discovered URL through the
edge and exits non-zero when one is dead:

```bash
pwsh -File Get-CloudflareTunnelUrls.ps1 -Verify
pwsh -File Get-CloudflareTunnelUrls.ps1 -Watch -Verify -IntervalSeconds 60
```

Repair by restarting that one connector. The URL then changes and the old one
stays dead, which is exactly why the Quick Tunnel is not viable for daily use:

```bash
kubectl -n cloudflare rollout restart deploy/cloudflared-audiobookshelf-quick
```

The real fix for a stable, monitorable, authenticated public URL is
[Option B](#option-b-permanent-tunnel-needs-token--own-domain): a named tunnel
keeps a fixed hostname, runs 2 replicas and survives this failure mode.

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

## Public Audiobookshelf without owning a domain

**Constraint:** no domain is owned, and CF Access is unusable because it keys off
a hostname in a Cloudflare-managed zone. A named tunnel (`Option B`) is therefore
unavailable too, for the same reason — not a pricing issue. Cloudflare's free tier
would cover both; the blocker is the absent domain, not the cost.

**Why there is still a public path at all:** the tailnet URL is the daily path,
but a corporate iPhone cannot install a VPN client, so the tailnet cannot serve it.

**The gate is in git** — `abs-auth-proxy.yaml`: nginx in front of
`audiobookshelf.media.svc` plus an `abs-gate` sidecar that serves a login form
and issues a signed session cookie. Per-IP rate limits (`10r/s` for the app,
`1r/s` for the login form), connection caps, and the websocket headers
Audiobookshelf requires. The Quick Tunnel points at that proxy, not at
Audiobookshelf, so the public URL yields a login page rather than an open one.

```
browser --TLS--> CF edge --http--> nginx (auth_request + limit_req) --> ABS
                              \-> abs-gate (login form, session cookie)
```

**Why a cookie and not HTTP Basic auth.** Basic auth was tried first and Chrome
re-challenged endlessly, including in incognito — the public endpoint is HTTP/2
at the edge and Chrome drops Basic credentials on reused h2 connections. A
cookie means one login per session and no browser-native prompt. The gate is
stateless (HMAC-signed cookie, no session store), so both replicas are
independent and a restart logs nobody out.

**Why not CF Access or a cookie-based IdP (Authelia).** Both key off a hostname
in a domain you control. `trycloudflare.com` is on the Public Suffix List, so a
cookie domain cannot be configured there at all, and the same constraint rules
out Audiobookshelf's native OIDC with Google as the provider. This is why the
gate is self-contained.

**Rotate the proxy password** — regenerate the PBKDF2 entry in the Secret
(`media/abs-gate`):

```bash
# 1. generate a new entry for the chosen password
python3 -c "import hashlib,os;p=b'NEWPASS';s=os.urandom(16);\
  d=hashlib.pbkdf2_hmac('sha256',p,s,200000);\
  print(f'pbkdf2_sha256$200000${s.hex()}${d.hex()}')"
# 2. patch the secret, then restart
kubectl -n media patch secret abs-gate \
  -p '{"stringData":{"passwordEntry":"pbkdf2_sha256$200000$<salt>$<hash>"}}'
kubectl -n media rollout restart deploy/abs-auth-proxy
```

Rotating `sessionSecret` instead logs out every device without changing the
password.

**No third action is required — there is nothing to disable in Audiobookshelf.**
Earlier revisions of this file claimed public registration had to be switched
off in the app. That was wrong: Audiobookshelf has no self-service signup, so
there is no such setting and no registration endpoint to abuse. Verified on the
running instance (2.36.1):

| Check | Result |
|---|---|
| `/register`, `/audiobookshelf/register` | 404 |
| `/api/auth/register`, `/api/register`, `/api/auth/signup` | 401 (ordinary auth guard, not a signup path) |
| `sign up` / `register` / `create account` in the login page HTML | none |
| Accounts in `/config/absdatabase.sqlite` | 1 — `SuryenduB`, type `root`, active |

Per the upstream docs the only account types are Root, Admin, User and Guest,
and "Admins can create new users through the server settings" — so the gate is
the only way in, which is what makes the two-layer design sufficient.

**Replicas and node failure.** `abs-auth-proxy` runs 2 replicas with
`topologySpreadConstraints` on `kubernetes.io/hostname` and
`whenUnsatisfiable: DoNotSchedule`, so the scheduler cannot place both on one
node — without it "replicas: 2" can silently provide no availability at all.
Verified landing on distinct nodes.

The Quick Tunnel is deliberately **1 replica**. A second replica would be a
second *ephemeral hostname*, and only one of them could ever be the URL written
here, so two replicas would guarantee a stale link in this document. Fixing that
properly needs a stable hostname, which means owning a domain (see Option B).

**NetworkPolicy is intentionally absent.** The cluster's CNI is stock Flannel
(`/var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist` contains
exactly the `flannel`, `portmap` and `bandwidth` plugins) and has **no
NetworkPolicy enforcement**, so policy objects would be accepted by the API
server and then do nothing. Inert manifests that look like segmentation are worse
than documented absence of it. This also means the `iiqstack` NetworkPolicies may
be equally ineffective and are worth a separate look.

Replacing the CNI (Calico, Cilium) to gain east-west policy is a far larger
change than adding YAML — it can affect pod networking, routing and service
connectivity across every other workload. Treat it as a deliberate future
project, not a prerequisite for this deployment.

**Known limits of this design:** one shared credential is weaker than per-user
identity, and the Quick Tunnel hostname still rotates and can rot (see the
failure mode above). Repair remains `kubectl -n cloudflare rollout restart
deploy/cloudflared-audiobookshelf-quick`.

**Troubleshooting the gate.** The nginx access log records `up=$upstream_status`,
which distinguishes the gate from Audiobookshelf: `401 up=-` is the gate
rejecting a request (no session cookie) and `401 up=401` is Audiobookshelf
rejecting one (bad ABS password). The gate's own log lines are prefixed
`abs-gate`:

```bash
kubectl -n media logs -l app=abs-auth-proxy -c nginx --tail=50
kubectl -n media logs -l app=abs-auth-proxy -c gate --tail=50
```

Two paths deliberately return 401 to the browser: the gate's own (rendered as
the login form, and it is what you see when you are not logged in) and
Audiobookshelf's (its login form). They are distinguished by which service
produced it, not by the status code.

### An ungated path that existed, and was removed

A live-only Service named `audiobookshelf-nodeport` (NodePort 30652) selected
`app: audiobookshelf` directly, **bypassing this gate entirely**, and answered
`HTTP 200` with no credentials from anywhere on the LAN. It was not in the repo,
which is how it survived a manifest review. It has been deleted.

Recorded here because the same shape recurs: any Service whose `selector`
targets the `audiobookshelf` pod is an alternate entrance that does not pass
through this proxy. Check with:

```bash
kubectl -n media get svc -o json \
  | python3 -c "import json,sys; print([(i['metadata']['name'],i['spec']['type'],i['spec'].get('selector')) for i in json.load(sys.stdin)['items']])"
```

`audiobookshelf` and `abs-auth-proxy` are the only two Services that should
select anything ABS-related, and both are ClusterIP.

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