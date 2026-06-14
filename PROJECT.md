# Project: OpenLingo Kubernetes Debugging

## Architecture
- **OpenLingo Application**: A language learning platform deployed in Kubernetes.
- **Frontend/Backend**: Web server backend routing calls to DeepSeek API for inference.
- **External AI API**: DeepSeek Pro V4.
- **Data Flow**: User sends a chat message -> Webserver/backend receives -> Webserver/backend sends request to DeepSeek API -> DeepSeek returns response -> Webserver/backend returns response to User.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|-------------|--------|
| 1 | Exploration & Diagnostics | Inspect pods, logs, env, and connection issues | none | DONE |
| 2 | Code/Manifest Fixes | Apply changes to fix DeepSeek integration | M1 | DONE |
| 3 | E2E & Verification | Run curl and verify inference works | M2 | DONE |
| 4 | Forensic Audit | Verify compliance and no cheating | M3 | DONE |

## Interface Contracts
### Web Backend ↔ DeepSeek Pro V4
- **Endpoint**: API URL configured in environment variables.
- **Auth**: API Key/token configured in secrets/configmaps.
- **Request Format**: JSON payload for chat completion.
- **Response Format**: JSON containing the AI assistant message.
