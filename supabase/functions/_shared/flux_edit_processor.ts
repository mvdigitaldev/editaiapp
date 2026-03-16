import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { releaseReservedCredits } from "./credits.ts";

const BFL_API_URL = "https://api.bfl.ai/v1/flux-2-pro";
const OPENAI_API_URL = "https://api.openai.com/v1";
const RETRY_STATUSES = [429, 500, 502, 503];

async function fetchWithRetry(
  url: string,
  options: RequestInit,
  maxAttempts = 3,
  baseDelayMs = 1000
): Promise<Response> {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const res = await fetch(url, options);
    if (res.ok || !RETRY_STATUSES.includes(res.status)) return res;
    if (attempt < maxAttempts - 1) {
      const delay = baseDelayMs * Math.pow(2, attempt);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw new Error(`Failed after ${maxAttempts} attempts`);
}
const EDIT_INPUTS_BUCKET = "edit-inputs";
const MAX_TOTAL_BYTES = 20 * 1024 * 1024;
const MAX_IMAGE_BYTES = 2 * 1024 * 1024;

async function openaiChat(model: string, system: string, user: string): Promise<string> {
  const res = await fetchWithRetry(
    `${OPENAI_API_URL}/chat/completions`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${Deno.env.get("OPENAI_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
      model,
      temperature: 0,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  },
  3,
  1000
  );
  if (!res.ok) throw new Error(`OpenAI error: ${res.status}`);
  const data = await res.json();
  return data.choices[0]?.message?.content?.trim() ?? "";
}

export async function optimizePromptMultiRef(
  userPrompt: string,
  imageCount: number,
  supabase: SupabaseClient,
  openaiKey: string
): Promise<{ improvedPrompt: string; intent: string; avgSimilarity: number; matchedIds: string[] }> {
  const translated = await openaiChat(
    "gpt-4o-mini",
    "Translate the user request to English. Output only the translated text.",
    userPrompt
  );

  const intent = await openaiChat(
    "gpt-4o-mini",
    `Classify the editing intent into ONE of the following categories:
- multi_reference_composite
- subject_removal
- lighting_adjustment
- color_grading
- typography
- composition
- general_edit
Output only the category name.`,
    translated
  );

  const imageContext = `Multi-reference: combining ${imageCount} reference images into one cohesive scene.`;
  const expandedQuery = `
User editing request: ${translated}
Image context: ${imageContext}
Intent category: ${intent}
Focus on relevant FLUX official documentation, especially:
- multi-reference image editing
- replacement strategy for negative prompts
- structured prompting
- subject + action + style + context`;

  const embRes = await fetchWithRetry(
    `${OPENAI_API_URL}/embeddings`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ input: expandedQuery, model: "text-embedding-3-small" }),
    },
    3,
    1000
  );
  if (!embRes.ok) throw new Error("Embedding generation failed");
  const embData = await embRes.json();
  const queryEmbedding = embData.data?.[0]?.embedding;
  if (!queryEmbedding) throw new Error("Embedding generation failed");

  const { data: matchedDocs, error: rpcError } = await supabase.rpc("match_flux_docs", {
    query_embedding: queryEmbedding,
    match_threshold: 0.35,
    match_count: 8,
  });
  if (rpcError) throw new Error(`RPC Error: ${rpcError.message}`);

  const contextString =
    matchedDocs?.length > 0
      ? matchedDocs.map((d: { content: string }) => d.content).join("\n\n---\n\n").slice(0, 4000)
      : "";
  const avgSimilarity =
    matchedDocs?.length > 0
      ? matchedDocs.reduce((acc: number, d: { similarity: number }) => acc + d.similarity, 0) / matchedDocs.length
      : 0;
  const matchedIds = matchedDocs?.map((d: { id: string }) => String(d.id)) ?? [];

  if (avgSimilarity < 0.5 && translated.split(/\s+/).length <= 15) {
    const minimalPrompt = await openaiChat(
      "gpt-4o-mini",
      "Output ONLY a short English phrase (10-30 words) that describes this multi-reference edit. Keep it concise.",
      `User request: ${translated}`
    );
    return { improvedPrompt: minimalPrompt || translated, intent, avgSimilarity, matchedIds };
  }

  const improvedPrompt = await openaiChat(
    "gpt-4o-mini",
    `You are a professional FLUX multi-reference image editing prompt optimizer.
STRICT RULES:
- OUTPUT ONLY the final improved English prompt.
- This is MULTI-REFERENCE editing: combine reference images (clothing, accessories, objects) into a cohesive scene.
- Describe how each input should be used in the final composition.
- Keep prompts concise when the request is simple. Do NOT over-describe.
- NEVER use negative prompts.
- Use positive visual replacement strategy.
- Follow: Subject + Action + Style + Context.
- Reference the FLUX Fashion Editorial Example: model wearing outfit, positioned in scene, combining items from references.`,
    `
Original editing request:
${translated}

Image context:
${imageContext}

Detected intent:
${intent}

Relevant FLUX documentation:
${contextString}
`
  );

  return { improvedPrompt, intent, avgSimilarity, matchedIds };
}

export interface FluxEditJobPayload {
  edit_id: string;
  user_id: string;
  reservation_id: string;
  storage_paths: string[];
  user_prompt: string;
  width: number;
  height: number;
  operation_type: string;
}

export async function processFluxEditJob(
  supabase: SupabaseClient,
  payload: FluxEditJobPayload
): Promise<{ taskId: string } | { error: string }> {
  const { edit_id, user_id, reservation_id, storage_paths, user_prompt, width, height } = payload;
  const outW = Math.floor(width) & ~15;
  const outH = Math.floor(height) & ~15;

  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  const bflApiKey = Deno.env.get("BFL_API_KEY");
  if (!openaiKey || !bflApiKey) {
    return { error: "Configuração indisponível" };
  }

  const normalizedImages: string[] = [];
  let totalBytes = 0;

  for (let i = 0; i < storage_paths.length; i++) {
    const path = storage_paths[i] as string;
    const { data: bytes, error: downloadErr } = await supabase.storage
      .from(EDIT_INPUTS_BUCKET)
      .download(path);

    if (downloadErr || !bytes) {
      console.error("[flux-edit-worker] Erro ao baixar:", path, downloadErr);
      await releaseReservedCredits(supabase, reservation_id, "storage_download_error");
      await supabase.from("edits").update({ status: "failed" }).eq("id", edit_id);
      return { error: `Imagem ${i + 1} não encontrada` };
    }

    const size = bytes.size;
    totalBytes += size;
    if (size > MAX_IMAGE_BYTES || totalBytes > MAX_TOTAL_BYTES) {
      await releaseReservedCredits(supabase, reservation_id, "payload_too_large");
      await supabase.from("edits").update({ status: "failed" }).eq("id", edit_id);
      return { error: "Imagem muito grande" };
    }

    const arr = new Uint8Array(size);
    arr.set(new Uint8Array(await bytes.arrayBuffer()));
    let outStr = "";
    for (let j = 0; j < arr.length; j++) outStr += String.fromCharCode(arr[j]);
    normalizedImages.push(btoa(outStr));
  }

  // Cliente já faz resize e compressão; worker apenas converte bytes → base64 para BFL
  const resizedImages = normalizedImages;

  const { improvedPrompt, intent, avgSimilarity, matchedIds } = await optimizePromptMultiRef(
    user_prompt.trim(),
    resizedImages.length,
    supabase,
    openaiKey
  );

  try {
    await supabase.from("prompt_optimization_logs").insert({
      user_id: user_id,
      original_prompt: user_prompt.trim(),
      improved_prompt: improvedPrompt,
      avg_similarity: avgSimilarity,
      matched_chunk_ids: matchedIds,
      metadata: {
        model: "gpt-4o-mini",
        source: "flux-edit-worker",
        rag_match_count: matchedIds.length,
        intent,
        image_count: resizedImages.length,
      },
    });
  } catch (_) {}

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const webhookUrl = `${supabaseUrl}/functions/v1/flux-webhook`;
  const bflBody: Record<string, unknown> = {
    prompt: improvedPrompt,
    width: outW,
    height: outH,
    output_format: "jpeg" as const,
    webhook_url: webhookUrl,
  };
  resizedImages.forEach((base64, i) => {
    bflBody[i === 0 ? "input_image" : `input_image_${i + 1}`] = base64;
  });

  const initRes = await fetchWithRetry(
    BFL_API_URL,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "x-key": bflApiKey,
      },
      body: JSON.stringify(bflBody),
    },
    3,
    2000
  );

  if (!initRes.ok) {
    const errText = await initRes.text();
    await releaseReservedCredits(supabase, reservation_id, "bfl_init_error");
    await supabase.from("edits").update({ status: "failed" }).eq("id", edit_id);
    return { error: errText || "Erro BFL" };
  }

  const initData = (await initRes.json()) as { id?: string };
  const taskId = initData.id;
  if (!taskId) {
    await releaseReservedCredits(supabase, reservation_id, "missing_task_id");
    await supabase.from("edits").update({ status: "failed" }).eq("id", edit_id);
    return { error: "Resposta inválida da API" };
  }

  await supabase.from("edits").update({ task_id: taskId }).eq("id", edit_id);
  const { error: insertError } = await supabase.from("flux_tasks").insert({
    task_id: taskId,
    user_id: user_id,
    edit_id: edit_id,
    status: "pending",
  });

  if (insertError) {
    await releaseReservedCredits(supabase, reservation_id, "flux_task_insert_error");
    await supabase.from("edits").update({ status: "failed" }).eq("id", edit_id);
    return { error: "Falha ao registrar tarefa" };
  }

  return { taskId };
}
