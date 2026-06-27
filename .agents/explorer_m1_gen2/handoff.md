# Handoff Report — OpenLingo 500 Internal Server Error Investigation

## 1. Observation

### A. Backend Route Definition
*   **File Path**: `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/app/api/chat/route.ts`
*   **Code Segment** (Lines 11-15, 54-73):
    ```typescript
    export async function POST(req: Request) {
      // 1. Authenticate
      const session = await requireSession();
      const { messages, language: lang } = await req.json();
      ...
        const response = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
          method: "POST",
          signal: controller.signal,
          headers: {
            "Authorization": `Bearer ${process.env.LLM_PROXY_API_KEY}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            model: "deepseek-ai/deepseek-v4-pro",
            messages: [
              { role: "system", content: systemPrompt },
              ...messages
            ],
            temperature: 1,
            top_p: 0.95,
            max_tokens: 4096,
            stream: true,
            chat_template_kwargs: { thinking: false }
          })
        });
    ```
*   **NIM API Failure Handling** (Lines 77-81):
    ```typescript
        if (!response.ok) {
          const errorBody = await response.text();
          console.error(`[AI] NIM API Failure: ${response.status} ${errorBody}`);
          return new Response(JSON.stringify({ error: "AI Engine error" }), { status: 500 });
        }
    ```

### B. Global Fetch Interceptor
*   **File Path**: `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/lib/nvidia-fix.ts`
*   **Remapping logic**:
    ```typescript
              // MAP dummy models -> REAL NVIDIA NIM IDs
              if (body.model === "gpt-4o" || body.model === "deepseek-ai/deepseek-v4-pro") {
                 body.model = "minimaxai/minimax-m3";
                 if ('chat_template_kwargs' in body) {
                   delete body.chat_template_kwargs;
                 }
                 console.log("[NIM-FORCE] Payload: Minimax M3 (remapped)");
              }
    ```

### C. Live Backend Kubernetes Pod Logs
*   **Command**: `kubectl logs openlingo-545ffdb4d5-xnt88 -n openlingo --tail=100`
*   **Verbatim Error Output**:
    ```
    [AI] Dispatching to NVIDIA NIM: deepseek-ai/deepseek-v4-pro
    [NIM-FORCE] Intercepting https://integrate.api.nvidia.com/v1/chat/completions -> https://integrate.api.nvidia.com/v1/chat/completions
    [NIM-FORCE] Payload: Minimax M3 (remapped)
    [AI] NIM API Failure: 400 {"message":"Failed to deserialize the JSON body into the target type: missing field `content` at line 1 column 12343","type":"Bad Request","code":400}
    ```

### D. Frontend SDK Messages Structure
*   **File Path**: `/node_modules/ai/src/ui/ui-messages.ts` (inside container `openlingo-545ffdb4d5-xnt88`)
*   **UIMessage Interface Definition**:
    ```typescript
    export interface UIMessage<
      METADATA = unknown,
      DATA_PARTS extends UIDataTypes = UIDataTypes,
      TOOLS extends UITools = UITools,
    > {
      id: string;
      role: 'system' | 'user' | 'assistant';
      metadata?: METADATA;
      parts: Array<UIMessagePart<DATA_PARTS, TOOLS>>;
    }
    ```
*   *Note*: The `UIMessage` interface used by `@ai-sdk/react` (`ai: 6.0.86`) does **not** contain a `content` field. It encapsulates text/files/tool calls in the `parts` array.

### E. Programmatic Verification Script
*   **File Path**: `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/.agents/challenger_m3/verify.js`
*   **Payload Shape** (Lines 63-66, 82-85):
    ```javascript
        body: JSON.stringify({
          messages: [{ role: "user", content: "Hi" }],
          language: "en",
        }),
    ```

---

## 2. Logic Chain

1. **API Error Response (from Observation A & C)**: When the frontend UI triggers a chat request, the backend Next.js API route returns a `500 Internal Server Error`. The logs reveal this 500 error is caused by a `400 Bad Request` returned from the intercepted NVIDIA NIM/Minimax completions endpoint.
2. **Missing Field Validation Error (from Observation C)**: The upstream API returns a validation error stating: `Failed to deserialize the JSON body into the target type: missing field 'content'`. This shows that the LLM endpoint expects every message object in the `messages` array to contain a `content` string field.
3. **Discrepancy in Message Formats (from Observation D & E)**:
    *   In the programmatic verification script (`verify.js`), the request payload is manually constructed as `[{ role: "user", content: "Hi" }]` which explicitly defines a `content` field. This works because it conforms to the LLM API's expected message schema.
    *   In the frontend UI request using `@ai-sdk/react`, the client-side uses `UIMessage` objects (from `ai` version `6.0.86`) which represent the message text inside a `parts` array (e.g. `{ id: "...", role: "user", parts: [{ type: "text", text: "..." }] }`) and do **not** define a top-level `content` field.
4. **Direct Splat Passing (from Observation A)**: The backend API route (`/api/chat/route.ts`) takes the incoming frontend `messages` list and splats it directly into the request body for the completions API (`...messages`) without filtering or conversion.
5. **Conclusion**: As a result, the backend forwards the `UIMessage` objects (which are missing the `content` field) directly to the LLM API. The LLM API fails to deserialize the JSON due to the missing `content` field, returns `400 Bad Request`, and the Next.js backend bubbles this up as a `500 Internal Server Error` to the frontend UI.

---

## 3. Caveats

*   **Database Conversions**: Since there are no chat conversations currently saved in the `chat_conversation` table (`0 rows` returned), we could not inspect pre-existing history in the database. However, this is expected since the initial message itself fails.
*   **Other models**: We assume all models handled through this endpoint (including the remapped Minimax M3) enforce standard OpenAI schema validation requiring the `content` field.

---

## 4. Conclusion

The root cause of the 500 error is a serialization mismatch:
*   The frontend client sends newer Vercel AI SDK `UIMessage` formats (which use `parts` and lack the `content` property).
*   The backend API route directly forwards these messages to the upstream OpenAI-compatible LLM endpoint.
*   The upstream endpoint rejects the request with a `400 Bad Request` due to the missing `content` field.
*   The backend API route converts the 400 response into a `500 Internal Server Error`.

### Proposed Fix:
Map the incoming messages in `/app/api/chat/route.ts` to standard `{ role, content }` objects by extracting text from the `parts` array:

```typescript
  const { messages, language: lang } = await req.json();

  const mappedMessages = messages.map((m: any) => {
    let content = m.content || "";
    if (m.parts && Array.isArray(m.parts)) {
      content = m.parts
        .filter((part: any) => part.type === "text")
        .map((part: any) => part.text)
        .join("\n");
    }
    return {
      role: m.role,
      content: content,
    };
  });
```
And then use `mappedMessages` in the fetch request:
```typescript
        body: JSON.stringify({
          model: "deepseek-ai/deepseek-v4-pro",
          messages: [
            { role: "system", content: systemPrompt },
            ...mappedMessages
          ],
          ...
```

---

## 5. Verification Method

To verify the root cause:
1. Run the existing programmatic verification script:
   ```bash
   kubectl exec -n openlingo openlingo-545ffdb4d5-xnt88 -- bun run /tmp/verify.js
   ```
   *Expected result*: Success (succeeds because it explicitly uses the `content` field format).
2. Modify the verification script or write a new test request (`/tmp/verify-fail.js`) that mimics the frontend's `@ai-sdk/react` payload structure:
   ```javascript
   // messages payload mimicking the frontend UI structure
   const messages = [{
     role: "user",
     parts: [{ type: "text", text: "Hi" }]
   }];
   ```
   Run this script targeting the backend `/api/chat` route.
   *Expected result*: Fails with a `500 Internal Server Error` and logs the identical `missing field 'content'` error in the backend container.
