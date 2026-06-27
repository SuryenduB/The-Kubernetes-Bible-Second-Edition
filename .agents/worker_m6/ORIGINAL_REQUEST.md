## 2026-06-15T20:03:30Z

You are a teamwork_preview_worker. Your task is to implement the backend fixes for OpenLingo to resolve the article translation and console hang issue.

Please perform the following steps:
1. Recover state and initialize your BRIEFING.md and progress.md in your working directory.
2. Apply the following code fixes:
   - In `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/lib/ai/models.ts`:
     Change line 59 from `return nvidiaProvider(modelInfo.internalId);` to `return nvidiaProvider.chat(modelInfo.internalId);`.
   - In `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/lib/nvidia-fix.ts`:
     - Case-insensitively delete duplicate `"authorization"` keys from `options.headers` before setting the lowercase `"authorization"` key.
     - Inspect why `body.tools` and `body.tool_choice` are deleted in the interceptor. Verify if tool calling works with NVIDIA NIM when these deletions are removed. If they are needed for one model but not another, adjust dynamically. Note that the `readArticle` tool MUST be available to the LLM for article translation to work.
   - In `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/app/api/chat/route.ts`:
     - Revert the route to use Vercel AI SDK's `streamText` and register `tools`. Ensure the stream is returned in the Vercel AI SDK Data Stream protocol format so that the client's `useChat` hook can parse it without hanging.
   - In `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/lib/article/translate.ts`:
     - Update the model `"gemini-3-flash-preview"` at line 113 to `"gemini-2.5-flash"`.
3. Verify compilation:
   - Run a test build or lint command to ensure no syntax/compilation issues exist in Next.js.
4. Rebuild the image and deploy to Kubernetes:
   - Build and push the new image tag (e.g. `192.168.0.236:5000/openlingo:v6-translation-fix`) using `./k3s-build.sh ./openlingo-debug 192.168.0.236:5000/openlingo:v6-translation-fix` at the project root directory `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition`.
   - Roll out the new image to the K8s deployment: `kubectl set image deployment/openlingo openlingo=192.168.0.236:5000/openlingo:v6-translation-fix -n openlingo`.
   - Wait for rollout to complete: `kubectl rollout status deployment/openlingo -n openlingo`.
   - Check pod status and logs to ensure the server starts up correctly.
5. Document all changes in `changes.md` and complete your handoff report at `handoff.md`.
6. Send a message to 'parent' with the results and the path to your handoff report.
