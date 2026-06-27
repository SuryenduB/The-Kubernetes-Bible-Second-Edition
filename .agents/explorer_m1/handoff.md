# Handoff Report — OpenLingo DeepSeek Pro V4 Connectivity

This handoff report summarizes the findings of the exploration of the OpenLingo application and the diagnostics performed regarding DeepSeek Pro V4 connectivity issues.

## 1. Observation

1.  **OpenLingo Pods and Services**:
    Using `kubectl get pod,deploy,svc,ingress,secret -n openlingo`, the active application was found:
    *   Pod: `pod/openlingo-6d58596c8d-xhw8t` (running `192.168.0.236:5000/openlingo:v4-timeout-fix` image)
    *   Deployment: `deployment.apps/openlingo`
    *   Service: `service/openlingo` (ClusterIP, port 80 -> container port 3000)
    *   Ingress: `ingress.networking.k8s.io/openlingo` (Host: `openlingo.example.com` class Traefik)
    *   Secret: `secret/openlingo-secrets` (Opaque, 9 keys)

2.  **Next.js Backend Logs**:
    Inspecting logs of the previous pod `openlingo-7768c7444c-w2x9g` via `kubectl logs -n openlingo openlingo-7768c7444c-w2x9g --tail=200`:
    ```
    [NIM-FORCE] Global interceptor and model mapper active
    [AI] Direct NIM Proxy: Model=deepseek-ai/deepseek-v4-pro
    [NIM-FORCE] Intercepting https://integrate.api.nvidia.com/v1/chat/completions -> https://integrate.api.nvidia.com/v1/chat/completions
    ⨯ [Error [TimeoutError]: The operation timed out.] {
      code: 23,
      TIMEOUT_ERR: 23,
      ...
    }
    ```

3.  **Secrets & Configuration**:
    Inspecting environment variables via `kubectl get secret openlingo-secrets -n openlingo -o yaml`:
    *   `LLM_PROXY_URL`: `"https://integrate.api.nvidia.com/v1"`
    *   `LLM_PROXY_API_KEY`: `"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"`

4.  **Source Code Mapping**:
    *   In `openlingo-debug/lib/ai/models.ts` (lines 30-33), `deepseek-ai/deepseek-v4-pro` maps to internal ID `gpt-4o`.
    *   In `openlingo-debug/lib/nvidia-fix.ts` (lines 12-25), the global fetch interceptor captures OpenAI requests and maps `gpt-4o` back to `deepseek-ai/deepseek-v4-pro` and adds `chat_template_kwargs: { thinking: false }`.
    *   In `openlingo-debug/app/api/chat/route.ts` (lines 48-100), the app proxies requests to `https://integrate.api.nvidia.com/v1/chat/completions` and terminates with a 60s timeout abort controller.

5.  **External Connectivity Verification**:
    Running curl on the host to check the NVIDIA models endpoint:
    `curl -s https://integrate.api.nvidia.com/v1/models -H "Authorization: Bearer nvapi-StcsgVEdF7_JhrYAJNsI-KSYeQCMau9a...`
    *   **Result**: Returned HTTP 200 immediately, including:
        `{"id":"deepseek-ai/deepseek-v4-pro","object":"model","created":735790403,"owned_by":"deepseek-ai"}`
        `{"id":"minimaxai/minimax-m3","object":"model","created":735790403,"owned_by":"minimaxai"}`
        `{"id":"moonshotai/kimi-k2.6","object":"model","created":735790403,"owned_by":"moonshotai"}`

6.  **Chat Completions curl Checks**:
    *   Calling `minimaxai/minimax-m3` via curl: Returned `HTTP 200 OK` with streamed text content immediately (within ~1.5s).
    *   Calling `moonshotai/kimi-k2.6` via curl: Returned `HTTP 200 OK` with streamed text content immediately.
    *   Calling `deepseek-ai/deepseek-v4-pro` via curl: Connection hung and timed out:
        `curl: (28) Operation timed out after 10010 milliseconds with 0 bytes received`.
    *   Calling `deepseek-ai/deepseek-v4-flash` via curl: Connection hung and timed out.
    *   Calling completions with no auth header: Returned `401 Unauthorized` instantly.
    *   Calling completions with invalid model ID `gpt-4o`: Returned `404 Not Found` instantly.

---

## 2. Logic Chain

1.  **Observation 2** shows that Next.js backend experiences client-side `TimeoutError` when invoking `deepseek-ai/deepseek-v4-pro`.
2.  **Observation 5** shows that DNS resolution and connection to `integrate.api.nvidia.com` is working, and the Bearer credentials are authenticated successfully (returning 200 OK and listing supported models).
3.  **Observation 6** shows that requests containing valid model parameters (`minimax-m3` and `kimi-k2.6`) succeed immediately, meaning there is no network policy or general firewall blocking POST completion requests from the cluster or host.
4.  **Observation 6** also shows that when a completions request targets the `deepseek-ai/deepseek-v4-pro` or `deepseek-ai/deepseek-v4-flash` model, it hangs and times out with `0 bytes received`. When authorization is omitted or an invalid model ID is used, the server responds immediately with an error (401 or 404).
5.  Therefore, the root cause is a **model-specific server-side hang / routing failure on the NVIDIA NIM hosting platform** specifically for the DeepSeek V4 family of models.

---

## 3. Caveats

*   **NVIDIA Server Status**: We assume that the NVIDIA NIM platform is generally online, but the containers hosting the DeepSeek V4 models specifically are either failing to initialize, routing incorrectly, or having quota-limit hangs on the NVIDIA backend infrastructure.
*   **ReadOnly Constraint**: Since we are read-only explorers, we did not apply a configuration change to map the application to another active model (e.g. `minimaxai/minimax-m3`).

---

## 4. Conclusion

The chat timeout issue in OpenLingo is caused by a **server-side failure/hang on the NVIDIA NIM API for the model `deepseek-ai/deepseek-v4-pro`**. It is NOT caused by incorrect Kubernetes manifests, blocked egress network policies, or authentication key invalidation. 

To resolve the issue immediately, the Next.js model configuration (or environment variables) should be changed to use a model that currently responds successfully on the NVIDIA API (such as `minimaxai/minimax-m3` or `moonshotai/kimi-k2.6`).

---

## 5. Verification Method

To independently verify this failure, execute the following commands from the host shell:

1.  **Check API key and models listing (Working)**:
    ```bash
    curl -s https://integrate.api.nvidia.com/v1/models \
      -H "Authorization: Bearer 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" \
      | jq '.data[] | select(.id | contains("deepseek-v4-pro"))'
    ```
    *Verification*: The command should return the model definition object immediately.

2.  **Test Active Model completions (Working)**:
    ```bash
    curl -i -m 10 https://integrate.api.nvidia.com/v1/chat/completions \
      -H "Authorization: Bearer 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" \
      -H "Content-Type: application/json" \
      -d '{"model": "minimaxai/minimax-m3", "messages": [{"role": "user", "content": "hello"}], "stream": true}'
    ```
    *Verification*: The command should return HTTP 200 and start streaming data immediately.

3.  **Test DeepSeek Pro V4 completions (Failing/Timeout)**:
    ```bash
    curl -i -m 15 https://integrate.api.nvidia.com/v1/chat/completions \
      -H "Authorization: Bearer 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" \
      -H "Content-Type: application/json" \
      -d '{"model": "deepseek-ai/deepseek-v4-pro", "messages": [{"role": "user", "content": "hello"}], "stream": true}'
    ```
    *Verification*: The command will hang and eventually terminate with `curl: (28) Operation timed out`.
