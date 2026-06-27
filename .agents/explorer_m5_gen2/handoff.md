# Handoff Report: OpenLingo Article Translation & Console Hang Issue

## 1. Observation
- **Observation 1 (API Route Bypass)**: In `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/app/api/chat/route.ts` (lines 70-89), a raw `fetch` call is made instead of Vercel AI SDK `streamText`:
  ```typescript
  const response = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
    method: "POST",
    signal: controller.signal,
    headers: {
      "Authorization": `Bearer \${process.env.LLM_PROXY_API_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: "deepseek-ai/deepseek-v4-pro",
      messages: [
        { role: "system", content: systemPrompt },
        ...formattedMessages
      ],
      temperature: 1,
      top_p: 0.95,
      max_tokens: 4096,
      stream: true,
      chat_template_kwargs: { thinking: false }
    })
  });
  ```
  This is returned to the client directly via `new Response(response.body, ...)` as `text/event-stream`.
- **Observation 2 (Vercel AI SDK Client)**: In `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/components/chat/chat-view.tsx` (lines 62-88), `useChat` from `@ai-sdk/react` is used:
  ```typescript
  const { messages, sendMessage, status } = useChat({
    transport,
    id: chatId,
    messages: initialMessages,
    onFinish: async ({ messages: allMessages, isError, isAbort }) => { ... }
  });
  ```
- **Observation 3 (Incorrect API Path)**: In `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/lib/ai/models.ts` (line 59), the provider instance is invoked directly:
  ```typescript
  return nvidiaProvider(modelInfo.internalId);
  ```
  Where `nvidiaProvider` is created via `@ai-sdk/openai`:
  ```typescript
  const nvidiaProvider = createOpenAI({
    baseURL: "https://integrate.api.nvidia.com/v1",
    apiKey: process.env.LLM_PROXY_API_KEY,
  });
  ```
  This causes Vercel AI SDK to resolve `"gpt-4o"` (mapped internally) using the new OpenAI Responses API (`/v1/responses` endpoint).
- **Observation 4 (Duplicate Auth Headers)**: In `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/lib/nvidia-fix.ts` (lines 48-54), the Authorization header is set case-sensitively:
  ```typescript
  if (options?.headers) {
     const apiKey = process.env.LLM_PROXY_API_KEY;
     if (apiKey) {
       options.headers["Authorization"] = `Bearer \${apiKey}`;
     }
  }
  ```
  Meanwhile, the `@ai-sdk/openai` provider sends options headers as an object with lowercase `"authorization"` (Observation 5).
- **Observation 5 (Test Execution Output)**:
  Running the `test-streamtext.ts` script inside the pod yielded the following headers:
  ```
  Headers keys: [ "authorization", "content-type", "user-agent" ]
    authorization: Bearer nvapi-St...
  ```
  The request failed with `403 Forbidden` and response body:
  ```json
  {"status":403,"title":"Forbidden","detail":"Authorization failed"}
  ```
- **Observation 6 (Hallucinated Gemini Model)**: In `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/lib/article/translate.ts` (line 113), the model is specified as:
  ```typescript
  model: "gemini-3-flash-preview",
  ```

---

## 2. Logic Chain
1. The client-side UI (`chat-view.tsx`, Observation 2) uses Vercel AI SDK's `useChat` hook, which expects a streaming response in the Vercel AI SDK Data Stream protocol format.
2. The server-side route (`route.ts`, Observation 1) is currently configured with a manual `fetch` that bypasses Vercel AI SDK and returns a raw OpenAI `text/event-stream`.
3. Due to this format mismatch, the client-side parser receives the raw stream but cannot parse it, resulting in the UI showing an empty assistant message and hanging.
4. Additionally, since the backend route uses a raw `fetch` and does not define the `tools` parameter in the request body, the LLM can never call the `readArticle` tool to translate the article.
5. The direct `fetch` bypass was implemented because the original `streamText` backend route failed with a 500 Internal Server Error.
6. The 500 error occurred because:
   - The provider callable maps model `"gpt-4o"` to the Responses API endpoint `/v1/responses` (Observation 3).
   - NVIDIA NIM does not support `/v1/responses` (Observation 5).
   - The global interceptor (`nvidia-fix.ts`) intercepts the request and tries to force `/v1/chat/completions`, but it maps the `Authorization` header case-sensitively (Observation 4).
   - This leaves both lowercase `authorization` and uppercase `Authorization` in the final request headers, causing NVIDIA NIM to reject the request with `403 Forbidden` (Observation 5).
7. If the background translation job is eventually triggered, it will fail/hang because the Gemini model is set to the non-existent `"gemini-3-flash-preview"` (Observation 6).

---

## 3. Caveats
- Since this is a read-only investigation, the fix has not been applied to the code repository, and its actual runtime effect has only been simulated and verified via debug scripts run inside the pod container.

---

## 4. Conclusion
The console hang and empty response occur because the chat endpoint returns a raw OpenAI stream instead of the Vercel AI SDK Data Stream protocol, and the tools are not registered on the raw fetch request. Bypassing Vercel AI SDK was an incorrect workaround for a 500 error, which itself was caused by (a) Vercel AI SDK resolving the model to the `/responses` endpoint, and (b) duplicate case-sensitive authorization headers in the global fetch interceptor.

---

## 5. Verification Method
1. Revert `app/api/chat/route.ts` to use Vercel AI SDK's `streamText`.
2. Update `lib/ai/models.ts` to call `nvidiaProvider.chat(...)` instead of `nvidiaProvider(...)`.
3. Update `lib/nvidia-fix.ts` to perform a case-insensitive cleanup of `"authorization"` keys before assigning the bearer token.
4. Update `lib/article/translate.ts` to use a valid Gemini model (e.g. `"gemini-2.5-flash"`).
5. Send a chat request to `POST /api/chat` using `curl` with the active session token:
   ```bash
   curl -i -X POST http://100.93.223.48/api/chat \
     -H "Content-Type: application/json" \
     -H "Cookie: openlingo.session_token=E1bHzSZDLAFltH4RtzbumnAKE3Kn67PQ" \
     -d '{"messages": [{"id": "msg-1", "role": "user", "parts": [{"type": "text", "text": "Hi"}]}], "language": "de"}'
   ```
6. Verify that the response returns HTTP `200 OK` and streams in the Vercel AI SDK Data Stream protocol (e.g. starting with `0:"..."` frames) without any authorization errors in the backend logs.
