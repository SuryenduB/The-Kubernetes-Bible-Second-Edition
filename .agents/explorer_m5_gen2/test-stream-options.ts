async function main() {
  const apiKey = process.env.LLM_PROXY_API_KEY;
  
  console.log("Calling NVIDIA NIM API with stream_options...");
  const response = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: "minimaxai/minimax-m3",
      messages: [
        { role: "user", content: "Hi" }
      ],
      stream: true,
      stream_options: { include_usage: true }
    })
  });

  console.log(`Status with stream_options: ${response.status}`);
  if (!response.ok) {
    console.log("Response headers:", [...response.headers.entries()]);
    console.log("Response body:", await response.text());
  }

  console.log("\nCalling NVIDIA NIM API WITHOUT stream_options...");
  const response2 = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: "minimaxai/minimax-m3",
      messages: [
        { role: "user", content: "Hi" }
      ],
      stream: true
    })
  });

  console.log(`Status WITHOUT stream_options: ${response2.status}`);
  if (!response2.ok) {
    console.log("Response body:", await response2.text());
  }
}

main().catch(console.error);
