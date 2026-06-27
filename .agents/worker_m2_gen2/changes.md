# Changes

## Modified Files
- `openlingo-debug/app/api/chat/route.ts`:
  - Updated the POST handler to map the incoming messages to a standard OpenAI format.
  - Handled the Vercel AI SDK structure where messages may contain a `parts` array instead of a `content` string, extracting and concatenating all text parts.
