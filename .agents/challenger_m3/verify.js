const BASE_URL = "http://localhost:3000";

async function main() {
  const email = `verify-${Date.now()}@example.com`;
  const password = "Password123!";
  const name = "Verifier User";

  console.log(`[TEST] Using email: ${email}`);

  // 1. Try signing up
  // Better Auth email signup URL is /api/auth/sign-up/email
  const signupUrl = `${BASE_URL}/api/auth/sign-up/email`;
  console.log(`[TEST] Sending POST to ${signupUrl}...`);
  const res = await fetch(signupUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, name }),
  });

  console.log(`[TEST] Signup status: ${res.status}`);
  const headers = [...res.headers.entries()];
  console.log("[TEST] Signup response headers:", headers);

  let body = await res.text();
  console.log(`[TEST] Signup response body:`, body);

  if (!res.ok) {
    throw new Error(`Signup failed with status ${res.status}: ${body}`);
  }

  // Retrieve the session cookie
  // Better Auth sets the session cookie upon signup/signin.
  const setCookieHeaders = res.headers.getSetCookie();
  console.log("[TEST] Set-Cookie headers:", setCookieHeaders);

  const sessionCookie = setCookieHeaders.find(cookie => cookie.includes("openlingo.session_token"));
  if (!sessionCookie) {
    throw new Error("Could not find openlingo.session_token in Set-Cookie headers!");
  }
  const cookieVal = sessionCookie.split(";")[0];
  console.log(`[TEST] Found session cookie: ${cookieVal}`);

  // 2. Query the chat endpoint
  // We will first try /api/chat/stream as requested by the user.
  // If it fails with 404, we will fall back to /api/chat.
  const urlsToTry = [
    `${BASE_URL}/api/chat/stream`,
    `${BASE_URL}/api/chat`
  ];

  let chatRes = null;
  let chosenUrl = "";

  for (const url of urlsToTry) {
    console.log(`[TEST] Attempting chat request to ${url}...`);
    try {
      const tempRes = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Cookie": cookieVal,
        },
        body: JSON.stringify({
          messages: [{ role: "user", content: "Hi" }],
          language: "en",
        }),
      });

      console.log(`[TEST] Response status from ${url}: ${tempRes.status}`);
      if (tempRes.status === 404) {
        console.log(`[TEST] Got 404 from ${url}, trying next endpoint...`);
        continue;
      }

      chatRes = tempRes;
      chosenUrl = url;
      break;
    } catch (err) {
      console.log(`[TEST] Error fetching from ${url}: ${err.message}`);
    }
  }

  if (!chatRes) {
    throw new Error("Could not reach any chat endpoint successfully.");
  }

  console.log(`[TEST] Successfully chose chat endpoint: ${chosenUrl}`);
  console.log("[TEST] Chat response headers:", [...chatRes.headers.entries()]);

  if (!chatRes.ok) {
    const errorText = await chatRes.text();
    console.error(`[TEST] Chat request failed: ${errorText}`);
    throw new Error(`Chat request failed with status ${chatRes.status}`);
  }

  console.log("[TEST] Reading stream chunks...");
  const reader = chatRes.body?.getReader();
  if (!reader) {
    throw new Error("Response body is not readable/streamable");
  }

  const decoder = new TextDecoder();
  let done = false;
  let chunkCount = 0;
  let accumulatedText = "";

  while (!done) {
    const { value, done: doneReading } = await reader.read();
    done = doneReading;
    if (value) {
      chunkCount++;
      const decodedChunk = decoder.decode(value, { stream: !done });
      accumulatedText += decodedChunk;
      console.log(`[CHUNK ${chunkCount}] (len: ${decodedChunk.length}) -> ${JSON.stringify(decodedChunk)}`);
    }
  }

  console.log(`\n[TEST] Received a total of ${chunkCount} chunks.`);
  console.log(`[TEST] Accumulated response preview: ${accumulatedText.slice(0, 300)}...`);

  if (chunkCount === 0 || accumulatedText.trim().length === 0) {
    throw new Error("Verification failed: Received empty response from chat stream!");
  }

  console.log("\n[TEST] VERIFICATION SUCCESSFUL!");
}

main().catch(err => {
  console.error("[TEST] Error in verification script:", err);
  process.exit(1);
});
