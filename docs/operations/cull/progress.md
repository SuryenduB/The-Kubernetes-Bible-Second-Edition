# Homelab simplification cull progress

Started 2026-10-18 from tag `cull-start`.

| Phase | Item | Decision | Reason / evidence | Resources and storage | Commit | Validation |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `argocd/argocd-initial-admin-secret` | REMOVE | Bootstrap secret from 2025-05-26; no owner, manifest, or Application dependency. | Secret only; no storage or exposure. | This commit | Deleted; Argo CD server remains 1/1, nodes Ready, Kustomize succeeds. |
| 1 | legacy `default` IIQ/phpLDAPadmin Services and proxies | REMOVE | Exact `default/iiq` and `default/phpldapadmin` Services were already absent; their surviving `*-tailscale` aliases selected no workloads. Active Services are in `iiqstack`. | Deleted `default/iiq-tailscale`, `default/phpldapadmin-tailscale`, and both Tailscale proxy StatefulSets; no storage. | This commit | Proxy deletion verified; active `iiqstack` deployments remain 1/1; Kustomize succeeds. |
| 1 | duplicate `argocd-1` and `openwebui-1` proxies | REMOVE | The canonical annotated Services `argocd/argocd-server` and `ai/openwebui` already expose hostnames `argocd` and `openwebui`. | Deleted alias Services and `ts-argocd-server-tailscale-*` / `ts-openwebui-tailscale-*`; no storage. | This commit | Alias proxies absent; canonical workloads remain 1/1; Kustomize succeeds. |
| 1 | `iiq-counter` | KEEP | Live IIQ runs `/entrypoint.sh`; the image entrypoint resolves `counter` and assigns `-Diiq.hostname=iiq$COUNTER`. The live pod resolves and reaches `counter.iiqstack.svc.cluster.local:12345`. | None; counter Service, Deployment, monitor, and proxy retained because they are required for a safe IIQ restart. | This commit | IIQ remains 1/1; runtime TCP check succeeded. |
| 1 | `pgweb` | REMOVE | Standalone PostgreSQL explorer with no configured database or PVC. Its only retained-app dependency was a permissive OpenLingo DB NetworkPolicy rule. | Deleted `media` Deployment/Service and Tailscale proxy; removed its NetworkPolicy peer, Homepage tile, manifest, and docs; no storage. | This commit | No pgweb resources or proxy remain; OpenLingo 1/1; Kustomize succeeds. |

## Baseline

- All ten nodes were Ready. `server-252` was already cordoned and its Longhorn node setting was already `allowScheduling: false`.
- Embedded-etcd pre-cull snapshot completed on `nuc`: `pre-cull-nuc-1792283844`.
- One pre-existing detached/unknown Longhorn volume was recorded in `baseline.md`; it is not a cull regression.
