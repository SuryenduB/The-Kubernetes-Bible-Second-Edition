# Pre-cull baseline

Captured 2026-10-18 against `https://192.168.0.21:6443` before the first removal. The raw commands used were `kubectl get nodes`, `kubectl get deploy,sts,ds -A -o wide`, and `kubectl -n longhorn-system get volumes.longhorn.io`.

## Cluster

All ten nodes were `Ready`: `kubernetes1`, `kubernetes2`, `kubernetes3`, `kubernetes4`, `kubernetes5`, `kubernetes6`, `kubernetes8-debian`, `nuc`, `server-236`, and `server-252`. The three control-plane/etcd members were `nuc`, `server-236`, and `server-252`; `server-252` was intentionally `SchedulingDisabled`.

## Ready retained-workload baseline

The following retained workload groups were ready: Argo CD; Ollama/Open WebUI; LinguaCafe/MariaDB/Redis; Homepage; Audiobookshelf/abs-auth-proxy; Calibre-Web; Chaptarr; Immich; Flick; Reactive Resume; Beszel; Uptime Kuma/kuma-auth-proxy; Gotify; Dozzle; RemotePower; IdentityIQ with LDAP, ActiveMQ, MSSQL, Mailpit and SSH; cluster networking/storage components; Cloudflare tunnel workloads; and the Tailscale operator/proxies.

The scheduled-to-remove workload groups were also ready at baseline and are tracked individually in `progress.md` as removals proceed.

## Longhorn

40 Longhorn volumes existed. All attached volumes were `healthy`. `pvc-1a05dbf3-c9eb-48d3-8b02-9a39645a884e` was already `detached` with `unknown` robustness, so it is explicitly a pre-existing condition rather than a cull regression. No other volume was faulted.

## Recovery checkpoint

On `nuc`, `sudo k3s etcd-snapshot save --name pre-cull` completed successfully, creating `pre-cull-nuc-1792283844`.
