---
name: nvidia-nim-strict-parameters
description: Resolve empty response arrays from NVIDIA NIM when calling completion endpoints
---

# NVIDIA NIM API Strict Parameters Skill

When calling **any model** (e.g., \`minimaxai/minimax-m3\`, \`meta/llama-3.1-8b-instruct\`) via the **NVIDIA NIM API** (\`https://integrate.api.nvidia.com/v1/chat/completions\`) using an OpenAI-compatible client, you must be aware of a strict, silent failure behavior on certain NIM containers.

## The Problem
If you send a standard chat completion request that omits explicit token or temperature parameters, the NVIDIA NIM API will **not** throw an HTTP 400 error. Instead, it will silently return an empty \`choices\` array:
\`{"id":"","choices":[],"created":0,"model":"","object":"chat.completion"}\`

This will cause downstream clients to crash (e.g., \`TypeError: Cannot read properties of undefined (reading 'message')\`) when trying to access the completion text.

## The Solution
Whenever writing code or debugging API calls targeted at the NVIDIA NIM platform, you **must explicitly include** the following parameters in the payload:
- \`max_tokens\` (e.g., 8192)
- \`temperature\` (e.g., 1.0 or lower)
- \`top_p\` (e.g., 0.95)

**Example Payload:**
```json
{
  "model": "<INSERT_ANY_NVIDIA_NIM_MODEL_HERE>",
  "messages": [{"role":"user", "content":"Hello!"}],
  "max_tokens": 8192,
  "temperature": 1.0,
  "top_p": 0.95
}
```
If you encounter \`choices[0]\` undefined errors on NVIDIA APIs, immediately check if these parameters are missing.
