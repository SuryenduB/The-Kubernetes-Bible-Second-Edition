import { db } from "/app/lib/db";
import { user } from "/app/lib/db/schema";
import { getUserPromptTemplate } from "/app/lib/actions/prompts";
import { getTargetLanguage } from "/app/lib/actions/preferences";
import { getNativeLanguage } from "/app/lib/actions/profile";
import { langCodeToName, interpolateTemplate, SRS_REFERENCE } from "/app/lib/prompts";
import { EXERCISE_SYNTAX } from "/app/lib/content/exercise-syntax";
import { and, eq } from "drizzle-orm";
import { userMemory } from "/app/lib/db/schema";

async function main() {
  const [firstUser] = await db.select().from(user).limit(1);
  if (!firstUser) {
    console.error("No user found in DB");
    return;
  }
  const userId = firstUser.id;
  console.log(`Using user ID: ${userId} (${firstUser.email})`);

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
    { role: "user", content: "I want to create a new translated article" }
  ];

  console.log("Calling NVIDIA NIM API...");
  const response = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
    method: "POST",
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
      stream: false, // Let's get the full response instead of streaming for easy debugging
    })
  });

  console.log(`NIM API Status: ${response.status}`);
  if (!response.ok) {
    const errorText = await response.text();
    console.error(`Error: ${errorText}`);
    return;
  }

  const result = await response.json();
  console.log("NIM API Response:");
  console.log(JSON.stringify(result, null, 2));
}

main().catch(console.error);
