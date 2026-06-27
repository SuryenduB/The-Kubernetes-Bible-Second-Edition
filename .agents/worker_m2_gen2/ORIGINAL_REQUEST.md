## 2026-06-14T19:53:14Z

You are the Worker subagent. Your mission is to implement the backend message-mapping fix to resolve the 500 Internal Server Error when calling the `/api/chat` endpoint.

Please perform the following actions:
1. Open the file `openlingo-debug/app/api/chat/route.ts` and modify the POST handler. Map the incoming `messages` array so that each message is transformed into a standard OpenAI-compatible format with `role` and `content` string fields. If a message contains a `parts` array (Vercel AI SDK structure), extract all text parts and concatenate them as the `content` field.
2. Build the Docker image for the OpenLingo application using the script `k3s-build.sh` at the root of the workspace.
   - Inspect the current deployment image first: `kubectl get deployment openlingo -n openlingo -o jsonpath='{.spec.template.spec.containers[0].image}'`.
   - Build and push the new image. Use a tag like `192.168.0.236:5000/openlingo:v5-frontend-fix` (or similar, depending on what the current image is).
3. Apply the updated image to the `openlingo` deployment in namespace `openlingo`:
   `kubectl set image deployment/openlingo openlingo=192.168.0.236:5000/openlingo:v5-frontend-fix -n openlingo`
   Then check the status of the rollout:
   `kubectl rollout status deployment/openlingo -n openlingo`
4. Confirm that the pod is successfully running and active (`1/1 Ready` status) and check the backend logs for any startup errors.
5. Document all code changes and build/deploy steps in a detailed report `handoff.md` (and `changes.md`) in your working directory `.agents/worker_m2_gen2/`.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Working Directory: /Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/.agents/worker_m2_gen2/
