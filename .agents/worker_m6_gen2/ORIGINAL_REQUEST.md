## 2026-06-15T20:56:46Z
You are a teamwork_preview_worker. Your task is to implement the backend fixes and the local programmatic verification script for OpenLingo to address the Victory Audit findings.

Please perform the following steps:
1. Recover state and initialize your BRIEFING.md and progress.md in your working directory.
2. Read the Explorer's findings and proposed code changes at:
   `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/.agents/explorer_m5_gen3/analysis.md`
3. Apply the proposed fixes in `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/lib/nvidia-fix.ts`:
   - Map both `gpt-4o` (and `deepseek-ai/deepseek-v4-pro`) and `gpt-4o-mini` (and `minimaxai/minimax-m3`) to `meta/llama-3.1-8b-instruct`.
   - Ensure strict parameters `max_tokens` (default 4096), `temperature` (default 0.7), and `top_p` (default 0.95) are injected if missing from the JSON payload.
   - Clean duplicate case-sensitive authorization headers dynamically using the normalized approach.
4. Implement the local programmatic verification script at `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/scripts/verify-local-env.ts` exactly as planned by the Explorer.
5. Verify local compilation:
   - Run a test Next.js build (`bun run build` with dummy environment vars) to ensure there are no compilation/TypeScript errors.
6. Rebuild and redeploy the container to Kubernetes:
   - Build/push: `./k3s-build.sh ./openlingo-debug 192.168.0.236:5000/openlingo:v7-llama-fix` (run at the project root `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition`).
   - Rollout: `kubectl set image deployment/openlingo openlingo=192.168.0.236:5000/openlingo:v7-llama-fix -n openlingo`.
   - Rollout status: `kubectl rollout status deployment/openlingo -n openlingo`.
   - Check pod status and log messages to ensure startup succeeded.
7. Document all modifications, scripts added, and command output in `changes.md` and your handoff report `handoff.md`.
8. Send a message to 'parent' with the results and the path to your handoff report.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your working directory is: `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/.agents/worker_m6_gen2/`
