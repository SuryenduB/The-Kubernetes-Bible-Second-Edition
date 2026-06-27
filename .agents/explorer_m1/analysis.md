# OpenLingo DeepSeek Pro V4 Connectivity Diagnostics Report

This report documents the diagnostic steps, commands run, output, and root cause analysis for the chat connectivity issues in the OpenLingo application deployed in the Kubernetes cluster.

---

## 1. Kubernetes Resource Map

The OpenLingo application and its components were located in the cluster across two namespaces: `openlingo` (active application) and `ai-language-learning` (legacy Express backend).

### Namespace: `openlingo`
*   **Pods**:
    *   `openlingo-6d58596c8d-xhw8t` (Running, image: `192.168.0.236:5000/openlingo:v4-timeout-fix`) - Main Next.js frontend/backend pod.
    *   `openlingo-db-0` (Running, image: `postgres:16-alpine`) - StatefulSet database pod.
*   **Deployments**:
    *   `deployment.apps/openlingo` - Configured with 1 replica, securityContexts (non-root runAsUser 1000), and env loading.
*   **Services**:
    *   `service/openlingo` (ClusterIP, Port 80 -> ContainerPort 3000) - Exposing the application service, annotated for Tailscale integration.
    *   `service/openlingo-db` (ClusterIP, Port 5432) - Exposing the Postgres database inside the namespace.
*   **Ingress**:
    *   `ingress.networking.k8s.io/openlingo` (Class: `traefik`) - Host: `openlingo.example.com`, routing prefix `/` to `openlingo` service on port 80.
*   **Secrets**:
    *   `secret/openlingo-secrets` (Opaque, 9 keys) - DB credentials, OAuth details, and LLM configuration keys.

### Namespace: `ai-language-learning`
*   **Pods**:
    *   `ai-lang-backend-788f778fcd-4ft7b` (Running, image: `192.168.0.236:5000/ai-language-learning:latest`) - Express JS server.
    *   `ai-postgres-755549c4f9-v5xqt` (Running, image: `postgres:15-alpine`) - Database pod.
*   **Services**:
    *   `service/ai-lang-backend` (ClusterIP, Port 80 -> ContainerPort 3000)
    *   `service/ai-postgres` (ClusterIP, Port 5432)
*   **Secrets**:
    *   `secret/ai-lang-secrets` - Express backend secrets.

---

## 2. Secrets and Environment Variables

The deployments are configured to inject LLM variables from secrets.

### Next.js OpenLingo Secret (`openlingo-secrets`):
*   `LLM_PROXY_URL`: `https://integrate.api.nvidia.com/v1` (Decoded)
*   `LLM_PROXY_API_KEY`: `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` (Decoded)
*   `OPENAI_API_KEY`: `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` (Decoded)

### Express AI Secret (`ai-lang-secrets`):
*   `OPENAI_BASE_URL`: `https://integrate.api.nvidia.com/v1`
*   `OPENAI_MODEL`: `moonshotai/kimi-k2.6`
*   `OPENROUTER_API_KEY`: `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`

Both components are pointing directly to the **NVIDIA NIM API** (`https://integrate.api.nvidia.com/v1`) using the exact same Bearer API token.

---

## 3. Source Code Analysis

The Next.js application in `openlingo-debug` constructs model requests as follows:

### A. Model Mapping (`openlingo-debug/lib/ai/models.ts`)
The Vercel AI SDK OpenAI provider is configured with the Nvidia base URL:
```typescript
const nvidiaProvider = createOpenAI({
  baseURL: "https://integrate.api.nvidia.com/v1",
  apiKey: process.env.LLM_PROXY_API_KEY,
});
```
The model metadata maps `deepseek-ai/deepseek-v4-pro` to an internal ID `gpt-4o` to bypass auto-detection limitations:
```typescript
{
  id: "deepseek-ai/deepseek-v4-pro",
  label: "DeepSeek V4 Pro (NVIDIA)",
  provider: "nvidia",
  internalId: "gpt-4o", // Interceptor swaps this to DeepSeek
}
```

### B. Global Fetch Interceptor (`openlingo-debug/lib/nvidia-fix.ts`)
A global interceptor hooks into the `fetch` function before the OpenAI provider evaluates it. When a request targeting NVIDIA NIM or OpenAI is detected, it rewrites the payload:
*   If the requested model is `gpt-4o`, it replaces it with `deepseek-ai/deepseek-v4-pro` and sets `chat_template_kwargs: { thinking: false }`.
*   It deletes OpenAI-specific keys (`tools`, `tool_choice`, `response_format`) to prevent NVIDIA NIM schema validation errors.
*   It enforces the `Authorization` header with the Bearer proxy key.
*   It directs the call to `https://integrate.api.nvidia.com/v1/chat/completions`.

### C. Chat Route Proxy (`openlingo-debug/app/api/chat/route.ts`)
A dedicated API route implements a proxy. It runs a `fetch` directly to `https://integrate.api.nvidia.com/v1/chat/completions` using an `AbortController` to timeout after `60000` ms (60 seconds). Because this URL matches `integrate.api.nvidia.com`, it also passes through the global interceptor to clean payload keys and enforce headers.

---

## 4. Diagnostic Commands and Evidence

The following commands were run to isolate and verify the issue:

### Step A: Pod Log Inspection
Command run:
```bash
kubectl logs -n openlingo <pod-name> --tail=500
```
Verbatim logs of the Next.js container:
```
[NIM-FORCE] Global interceptor and model mapper active
[AI] Direct NIM Proxy: Model=deepseek-ai/deepseek-v4-pro
[NIM-FORCE] Intercepting https://integrate.api.nvidia.com/v1/chat/completions -> https://integrate.api.nvidia.com/v1/chat/completions
⨯ [Error [TimeoutError]: The operation timed out.] {
  code: 23,
  INDEX_SIZE_ERR: 1,
  DOMSTRING_SIZE_ERR: 2,
  ...
  TIMEOUT_ERR: 23,
  ...
}
```
**Observation**: The application experiences a client-side timeout during the API request.

---

### Step B: DNS and Credential Verification
To verify the host's connectivity to the API and check if the API key is active and valid, we queried the models endpoint:
```bash
curl -i https://integrate.api.nvidia.com/v1/models \
  -H "Authorization: Bearer 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"
```
**Output**:
```http
HTTP/2 200 OK
date: Sun, 14 Jun 2026 16:55:41 GMT
...
[
  {"id":"deepseek-ai/deepseek-v4-flash","object":"model","created":735790403,"owned_by":"deepseek-ai"},
  {"id":"deepseek-ai/deepseek-v4-pro","object":"model","created":735790403,"owned_by":"deepseek-ai"},
  {"id":"minimaxai/minimax-m3","object":"model","created":735790403,"owned_by":"minimaxai"},
  {"id":"moonshotai/kimi-k2.6","object":"model","created":735790403,"owned_by":"moonshotai"}
]
```
**Observation**: DNS resolution is functional and the API key is valid. The list shows that `deepseek-ai/deepseek-v4-pro` and `deepseek-ai/deepseek-v4-flash` are in the list of models authorized for this account.

---

### Step C: Multi-Model Completion Validation
To isolate if the issue was model-specific, we ran direct POST completions requests to the completions endpoint using different models.

#### 1. DeepSeek Pro V4 (`deepseek-ai/deepseek-v4-pro`)
```bash
curl -i -m 10 https://integrate.api.nvidia.com/v1/chat/completions \
  -H "Authorization: Bearer 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" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ai/deepseek-v4-pro",
    "messages": [{"role": "user", "content": "hello"}],
    "max_tokens": 10,
    "stream": true
  }'
```
**Output**:
```
curl: (28) Operation timed out after 10010 milliseconds with 0 bytes received
```

#### 2. DeepSeek Flash V4 (`deepseek-ai/deepseek-v4-flash`)
```bash
curl -i -m 10 https://integrate.api.nvidia.com/v1/chat/completions \
  -H "Authorization: Bearer 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" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ai/deepseek-v4-flash",
    "messages": [{"role": "user", "content": "hello"}],
    "max_tokens": 10,
    "stream": true
  }'
```
**Output**:
```
curl: (28) Operation timed out after 10004 milliseconds with 0 bytes received
```

#### 3. Minimax M3 (`minimaxai/minimax-m3`)
```bash
curl -i -m 10 https://integrate.api.nvidia.com/v1/chat/completions \
  -H "Authorization: Bearer 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" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "minimaxai/minimax-m3",
    "messages": [{"role": "user", "content": "hello"}],
    "max_tokens": 10,
    "stream": true
  }'
```
**Output**:
```http
HTTP/2 200 OK
date: Sun, 14 Jun 2026 16:56:58 GMT
content-type: text/event-stream
nvcf-status: fulfilled

data: {"id":"chatcmpl-fdec0a21-4949-4313-9476-6b08acad1316","choices":[{"index":0,"delta":{"content":"Hello","role":"assistant"}}], ...}
```

#### 4. Moonshot Kimi (`moonshotai/kimi-k2.6`)
```bash
curl -i -m 10 https://integrate.api.nvidia.com/v1/chat/completions \
  -H "Authorization: Bearer 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" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "moonshotai/kimi-k2.6",
    "messages": [{"role": "user", "content": "hello"}],
    "max_tokens": 10,
    "stream": true
  }'
```
**Output**:
```http
HTTP/2 200 OK
date: Sun, 14 Jun 2026 16:57:44 GMT
content-type: text/event-stream; charset=utf-8
nvcf-status: fulfilled

data: {"id":"chatcmpl-aefddad14236647d","choices":[{"index":0,"delta":{"role":"assistant","content":" Hello! How can I help you today?"}}], ...}
```

---

## 5. Root Cause Summary

The connectivity and chat failure is **model-specific and located entirely on the server/routing side of the NVIDIA NIM platform** for the DeepSeek V4 family. 

*   **Verified working**: DNS, TLS connection, API Key Authentication, `/v1/models` listing, and completions for other models (`minimaxai/minimax-m3`, `moonshotai/kimi-k2.6`) return HTTP 200 OK immediately.
*   **Verified failing**: Calling either `deepseek-ai/deepseek-v4-pro` or `deepseek-ai/deepseek-v4-flash` via completions results in a persistent gateway/server-side hang, eventually causing client-side timeouts.

Since the client request is properly formatted (and even includes parameter bypasses like `thinking: false`), the issue must be resolved on the NVIDIA NIM host infrastructure. The temporary workaround is to map the application to another model ID that is fully operational (e.g., `minimaxai/minimax-m3`).
