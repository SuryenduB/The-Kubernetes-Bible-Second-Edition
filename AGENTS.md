# AGENTS.md

This repo is two things: Packt "Kubernetes Bible 2e" chapter examples (`Chapter01/`–`Chapter21/`) plus a live 9–11-node K3s homelab (`kubernetes-manifests/`, `WindowsLab/`, `terraform/`, `docs/`). Chapters are standalone examples — don't treat the repo as one buildable app. There is no root build/test/lint; root `package-lock.json` is empty.

## Manifests: `kubernetes-manifests/`

- Deploy: `kubectl apply -k ./kubernetes-manifests` (top-level `kustomization.yaml` aggregates all apps). Per-app: `kubectl apply -f <file>` or `kubectl apply -k ./kubernetes-manifests/media|monitoring|longhorn-backup`.
- Full app/namespace map lives in `kubernetes-manifests/README.md` — read it before adding workloads.
- Tailscale exposure goes on the **Service**, never Ingress (see `k3s-tailscale-proxy/SKILL.md`): `tailscale.com/expose: "true"`, `tailscale.com/proxy-class: "tailscale-proxy"`, `tailscale.com/hostname: "<name>"`.
- Storage: Longhorn default; `longhorn-r1` single-replica class for rebuildable data; NFS `nfs-nas` on Synology `192.168.0.128` for media/Ollama models. Static NFS PVs use explicit `claimRef` — don't remove it.
- Secrets with plaintext creds are intentionally checked in (homelab scope). Replace `REPLACE_ME` before applying; never "fix" this by deleting secrets.

## Homelab power: `WindowsLab/`

- `WindowsLab/homelab-nodes.json` is the single source of truth for nodes/SSH users/safety flags. Never hardcode node lists.
- `kubernetes7` has `neverPowerOff: true` (broken power switch — unrecoverable). `nuc`/`server-236`/`server-252` are `neverCordon` (control plane/etcd + local registry host).
- SSH usernames are case-sensitive: `suryendub` on Ubuntu workers/`nuc`, `SuryenduB` (capital S) on `server-236`/`server-252`.
- Bring-up: `pwsh -File WindowsLab/Start-K3sHomelab.ps1 -DryRun` first, then `-RepairStorage`; watch `kubectl get nodes -w` then `kubectl get pods -A`. Shutdown must run detached: `pwsh -File WindowsLab/shutdown_homelab.ps1 -Force > shutdown.log 2>&1 < /dev/null &`. Rehearse with `-DryRun`, check creds with `-VerifyCredentials -Force`.
- Health check: `Test-K3sClusterHealth.ps1` at repo root. Runbooks: `docs/homelab/how-to-manage-homelab-power.md`, `docs/operations/`.

## Building images without local Docker

Mac has no local `docker`; build in-cluster via `k3s-build <src-dir> <registry/image:tag>` (see `k3s-build.sh`, `k3s-dind-build/SKILL.md`). Private registry is insecure `192.168.0.236:5000` (co-hosted on `server-236`, pinned by `registry-fixer.yaml`).

## Sub-app: `openlingo-debug/`

Separate Next.js 16 / Bun app (Postgres + Drizzle). Commands run there, not at root: `bun install`, `bun run db:up && bun run db:migrate && bun run db:seed`, `bun run dev`. Per-session rules (agent-browser tool, test login `testing@openlingo.dev` / `0P3NL1NG0`) live in `openlingo-debug/AGENTS.md`.

## Do not commit

`.gitignore` excludes `skills/`, `.gdrive-sync/`, `*-service-account.json` / `*-sa-key.json`, `**/gcloud/**`, `uptime-kuma-credentials.env`, `cred.xml`, tfstate/backups, and logs. Keep homelab creds out of new files outside the existing manifest pattern.
