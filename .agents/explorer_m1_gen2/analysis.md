# OpenLingo Chat Endpoint Diagnostics Report

## Executive Summary
This report summarizes the investigation into the 500 Internal Server Error occurring on the `POST /api/chat` endpoint of the deployed OpenLingo application. We have isolated the root cause to a format mismatch between the frontend client messages payload (Vercel AI SDK UI v4/v6 format using `parts` instead of `content`) and the OpenAI-compatible request structure expected by the upstream NVIDIA NIM / Minimax M3 completions API.

---

## 1. Codebase Architecture

### Next.js Chat API Route (`app/api/chat/route.ts`)
The endpoint is defined at `/Users/macbookpro/Documents/The-Kubernetes-Bible-Second-Edition/openlingo-debug/app/api/chat/route.ts`. 
It parses the request body:
```typescript
const { messages, language: lang } = await req.json();
```
And forwards the `messages` array directly:
```typescript
body: JSON.stringify({
  model: "deepseek-ai/deepseek-v4-pro",
  messages: [
    { role: "system", content: systemPrompt },
    ...messages
  ],
  ...
})
```

### Global Fetch Interceptor (`lib/nvidia-fix.ts`)
Intercepts the request, maps `deepseek-ai/deepseek-v4-pro` to `minimaxai/minimax-m3`, and removes OpenAI-specific attributes (`tools`, `tool_choice`, `response_format`), forwarding the modified request to the Nvidia completions endpoint.

---

## 2. Payload Comparison

We compared the payload structure of the frontend UI request with the programmatic verification script request.

### A. Programmatic Verification Payload (`verify.js`)
Found in `.agents/challenger_m3/verify.js`:
```json
{
  "messages": [
    {
      "role": "user",
      "content": "Hi"
    }
  ],
  "language": "en"
}
```
*   **Result**: Returns HTTP 200 OK.
*   **Reason**: Explicitly includes the `"content"` field, satisfying standard LLM completions schema.

### B. Frontend UI Payload (`@ai-sdk/react`)
Uses `@ai-sdk/react` (`ai: 6.0.86`) where messages are modeled using `parts` instead of a top-level string `content`:
```json
{
  "messages": [
    {
      "id": "ui-message-id",
      "role": "user",
      "parts": [
        {
          "type": "text",
          "text": "Hi"
        }
      ]
    }
  ],
  "language": "en"
}
```
*   **Result**: Returns HTTP 500 Internal Server Error.
*   **Reason**: The backend directly splats this message array into the LLM request. The target LLM API rejects the payload with a 400 Bad Request because the `"content"` field is missing.

---

## 3. Logs and Diagnostic Evidence

Inspection of container logs from the running Kubernetes pod `openlingo-545ffdb4d5-xnt88` shows:
```
[AI] NIM API Failure: 400 {"message":"Failed to deserialize the JSON body into the target type: missing field `content` at line 1 column 12343","type":"Bad Request","code":400}
```
This confirms that the deserializer of the target LLM API fails to parse the JSON due to the missing required `"content"` field.

---

## 4. Remediation Steps

To fix this issue, the backend route handler `/app/api/chat/route.ts` must map the client messages array to standard OpenAI-compatible format before sending it to the completions API:

```typescript
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

Using `mappedMessages` resolves the issue by ensuring all message objects passed to the completions API contain the required `"content"` string field.
