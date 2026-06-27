import { createOpenAI } from "@ai-sdk/openai";
import { streamText } from "ai";
import "/app/lib/nvidia-fix";

async function main() {
  const originalFetch = global.fetch;
  global.fetch = async (url: any, options: any) => {
    console.log("Global fetch intercepted!");
    if (options?.body) {
      console.log("BODY STRING:");
      console.log(options.body);
    }
    return originalFetch(url, options);
  };

  const nvidiaProvider = createOpenAI({
    baseURL: "https://integrate.api.nvidia.com/v1",
    apiKey: process.env.LLM_PROXY_API_KEY,
  });

  const chatModel = nvidiaProvider.chat("gpt-4o");

  try {
    const result = streamText({
      model: chatModel,
      messages: [{ role: "user", content: "Hi" }],
    });
    console.log("Reading text stream...");
    for await (const textPart of result.textStream) {
      process.stdout.write(textPart);
    }
    console.log("\nStream complete!");
  } catch (error) {
    console.error("Stream error:", error);
  }
}

main().catch(console.error);
