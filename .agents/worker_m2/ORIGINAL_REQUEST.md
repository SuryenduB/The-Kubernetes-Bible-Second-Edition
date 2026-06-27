## 2026-06-14T18:58:36Z
Implement the fix for OpenLingo connectivity by mapping DeepSeek Pro V4 calls to the working Minimax M3 model.
Specifically:
1. Modify `openlingo-debug/lib/nvidia-fix.ts` so that both `gpt-4o` and `deepseek-ai/deepseek-v4-pro` requests are remapped to `minimaxai/minimax-m3`. Ensure that `chat_template_kwargs` is handled correctly.
2. Modify `openlingo-debug/lib/constants.ts` to change `DEFAULT_AI_MODEL` to `minimaxai/minimax-m3`.
3. Build the new docker image using `k3s-build.sh` script:
   `./k3s-build.sh ./openlingo-debug 192.168.0.236:5000/openlingo:v4-timeout-fix`
4. Deploy the changes to the cluster. Run `kubectl rollout restart deployment openlingo -n openlingo` and wait for the pod to be fully Ready.
5. Verify that the new pod is running, and get its logs to verify it initializes correctly.
6. Write a summary of your changes to `changes.md` and `handoff.md` in your working directory `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/.agents/worker_m2/`.
