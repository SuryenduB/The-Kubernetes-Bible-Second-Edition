import { db } from "/app/lib/db";
import { user } from "/app/lib/db/schema";
import { getUserPromptTemplate } from "/app/lib/actions/prompts";
import { getTargetLanguage } from "/app/lib/actions/preferences";
import { getNativeLanguage } from "/app/lib/actions/profile";
import { langCodeToName, interpolateTemplate, SRS_REFERENCE } from "/app/lib/prompts";
import { EXERCISE_SYNTAX } from "/app/lib/content/exercise-syntax";
import { and, eq } from "drizzle-orm";
import { userMemory } from "/app/lib/db/schema";
import { streamText, convertToModelMessages, stepCountIs } from "ai";
import { getModelsForUser, createTools } from "/app/lib/ai";
import { createOpenAI } from "@ai-sdk/openai";

async function main() {
  const [firstUser] = await db.select().from(user).limit(1);
  if (!firstUser) {
    console.error("No user found in DB");
    return;
  }
  const userId = firstUser.id;
  const language = (await getTargetLanguage(userId)) || "de";
  const target_language = langCodeToName[language] || language;

  const [chatTemplate, memoryRow, nativeLang] = await Promise.all([
    getUserPromptTemplate(userId, "chat-system"),
    db
      .select()
      .from(userMemory)
      .where(
        and(
          eq(userMemory.userId, userId),
          eq(userMemory.key, "memory"),
        ),
      )
      .limit(1)
      .then((rows) => rows[0]),
    getNativeLanguage(userId),
  ]);

  const systemPrompt = interpolateTemplate(chatTemplate, {
    current_date: new Date().toISOString().split('T')[0],
    target_language,
    target_language_code: language,
    native_language: nativeLang ? (langCodeToName[nativeLang] || nativeLang) : "English",
    memory: memoryRow?.value ?? "",
    exercise_syntax: EXERCISE_SYNTAX,
    srs_reference: SRS_REFERENCE,
  });

  const messages = [
    {
      id: "msg-1",
      role: "user" as const,
      content: "Hi",
      parts: [{ type: "text" as const, text: "Hi" }]
    }
  ];

  console.log("Calling streamText...");
  try {
    const nvidiaProvider = createOpenAI({
      baseURL: "https://integrate.api.nvidia.com/v1",
      apiKey: process.env.LLM_PROXY_API_KEY,
    });
    
    // Use .chat instead of direct provider call to target /chat/completions instead of /responses
    const chatModel = nvidiaProvider.chat("gpt-4o");

    const result = streamText({
      model: chatModel,
      system: systemPrompt,
      messages: await convertToModelMessages(messages),
      tools: createTools(userId, language),
      stopWhen: stepCountIs(7),
    });

    console.log("Reading text stream...");
    for await (const textPart of result.textStream) {
      process.stdout.write(textPart);
    }
    console.log("\nSuccess!");
  } catch (error) {
    console.error("StreamText Error:", error);
  }
}

main().catch(console.error);
