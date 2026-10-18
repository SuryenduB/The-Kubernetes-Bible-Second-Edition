# Homelab simplification cull progress

Started 2026-10-18 from tag `cull-start`.

| Phase | Item | Decision | Reason / evidence | Resources and storage | Commit | Validation |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `argocd/argocd-initial-admin-secret` | REMOVE | Bootstrap secret from 2025-05-26; no owner, manifest, or Application dependency. | Secret only; no storage or exposure. | This commit | Deleted; Argo CD server remains 1/1, nodes Ready, Kustomize succeeds. |
| 1 | legacy `default` IIQ/phpLDAPadmin Services and proxies | REMOVE | Exact `default/iiq` and `default/phpldapadmin` Services were already absent; their surviving `*-tailscale` aliases selected no workloads. Active Services are in `iiqstack`. | Deleted `default/iiq-tailscale`, `default/phpldapadmin-tailscale`, and both Tailscale proxy StatefulSets; no storage. | This commit | Proxy deletion verified; active `iiqstack` deployments remain 1/1; Kustomize succeeds. |

## Baseline

- All ten nodes were Ready. `server-252` was already cordoned and its Longhorn node setting was already `allowScheduling: false`.
- Embedded-etcd pre-cull snapshot completed on `nuc`: `pre-cull-nuc-1792283844`.
- One pre-existing detached/unknown Longhorn volume was recorded in `baseline.md`; it is not a cull regression.
