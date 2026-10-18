# Homelab simplification cull progress

Started 2026-10-18 from tag `cull-start`.

| Phase | Item | Decision | Reason / evidence | Resources and storage | Commit | Validation |
| --- | --- | --- | --- | --- | --- | --- |

## Baseline

- All ten nodes were Ready. `server-252` was already cordoned and its Longhorn node setting was already `allowScheduling: false`.
- Embedded-etcd pre-cull snapshot completed on `nuc`: `pre-cull-nuc-1792283844`.
- One pre-existing detached/unknown Longhorn volume was recorded in `baseline.md`; it is not a cull regression.
