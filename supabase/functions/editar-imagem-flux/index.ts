import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  createEditAndReserveCredits,
  releaseReservedCredits,
} from "../_shared/credits.ts";
const BFL_API_URL = "https://api.bfl.ai/v1/flux-2-pro";
const OPENAI_API_URL = "https://api.openai.com/v1";
const EDIT_INPUTS_BUCKET = "edit-inputs";
const FLUX_IMAGENS_BUCKET = "flux-imagens";
const MAX_IMAGE_BYTES = 2 * 1024 * 1024;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  user_prompt: string;
  storage_path: string;
  width?: number;
  height?: number;
}

interface AsyncWebhookResponse {
  id: string;
  status?: string;
  webhook_url?: string;
}

function jsonResponse(data: object, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

async function openaiChat(model: string, system: string, user: string): Promise<string> {
  const res = await fetch(`${OPENAI_API_URL}/chat/completions`, {
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
  });
  if (!res.ok) throw new Error(`OpenAI error: ${res.status}`);
  const data = await res.json();
  return data.choices[0]?.message?.content?.trim() ?? "";
}

async function openaiVision(
  imageBase64: string,
  prompt: string,
  openaiKey: string
): Promise<string> {
  const dataUrl = imageBase64.startsWith("data:") ? imageBase64 : `data:image/jpeg;base64,${imageBase64}`;
  const res = await fetch(`${OPENAI_API_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openaiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0,
      max_tokens: 200,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: dataUrl } },
          ],
        },
      ],
    }),
  });
  if (!res.ok) throw new Error(`OpenAI Vision error: ${res.status}`);
  const data = await res.json();
  return data.choices[0]?.message?.content?.trim() ?? "";
}

async function generateImageContext(imageBase64: string, openaiKey: string): Promise<string> {
  const prompt = `Describe this image in 1-2 sentences in English. Focus on: subject, setting, colors, objects, people if any. Output only the description, no preamble. Example: "A green bicycle wheel on a street with buildings in the background."`;
  return openaiVision(imageBase64, prompt, openaiKey);
}

async function optimizePrompt(
  userPrompt: string,
  imageContext: string | undefined,
  supabase: ReturnType<typeof createClient>,
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
- subject_removal
- lighting_adjustment
- color_grading
- typography
- composition
- general_edit

Output only the category name.`,
    translated
  );

  const expandedQuery = `
User editing request:
${translated}

Image context:
${imageContext || "Unknown image context."}

Intent category: ${intent}

Focus on relevant FLUX official documentation, especially:
- replacement strategy for negative prompts
- structured prompting
- subject + action + style + context
`;

  const embRes = await fetch(`${OPENAI_API_URL}/embeddings`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openaiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      input: expandedQuery,
      model: "text-embedding-3-small",
    }),
  });
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

  // Bypass: quando RAG retorna docs irrelevantes e o pedido é curto, usar prompt minimal
  if (avgSimilarity < 0.5 && translated.split(/\s+/).length <= 15) {
    const minimalPrompt = await openaiChat(
      "gpt-4o-mini",
      "Output ONLY a short English phrase (10-30 words) that describes this edit: 'Same scene, with: [user request]'. Do NOT describe the full scene.",
      `User request: ${translated}`
    );
    return {
      improvedPrompt: minimalPrompt || translated,
      intent,
      avgSimilarity,
      matchedIds,
    };
  }

  const improvedPrompt = await openaiChat(
    "gpt-4o-mini",
    `You are a FLUX image editing prompt optimizer.

STRICT RULES:
- OUTPUT ONLY the final improved English prompt.
- This is IMAGE EDITING: describe ONLY the change to apply. The input image already provides the scene.
- For simple edits (add/remove/change one thing): keep prompt SHORT (10-50 words). Do NOT re-describe clothing, background, or objects.
- PRESERVE the original scene. ONLY modify what the user requested.
- NEVER use negative prompts.
- Use positive visual replacement strategy.
- If the user asks for a minimal change (e.g. "add pregnant belly"), output something like: "Same woman, same pose and setting, with a visibly pregnant belly" — NOT a full scene description.`,
    `
Original editing request:
${translated}

Image context:
${imageContext || "Preserve the existing scene."}

Detected intent:
${intent}

Relevant FLUX documentation:
${contextString}
`
  );

  return { improvedPrompt, intent, avgSimilarity, matchedIds };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "MÃ©todo nÃ£o permitido" }, 405);
  }

  try {
    const body = (await req.json()) as Partial<RequestBody>;
    const { user_prompt, storage_path, width, height } = body;

    if (!user_prompt || typeof user_prompt !== "string" || user_prompt.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'user_prompt' é obrigatório e não pode estar vazio" },
        422
      );
    }

    if (!storage_path || typeof storage_path !== "string" || storage_path.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'storage_path' é obrigatório" },
        422
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ success: false, error: "Autenticação obrigatória" }, 401);
    }
    const authClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await authClient.auth.getUser();
    const userId = user?.id ?? null;
    if (!userId) {
      return jsonResponse({ success: false, error: "Autenticação obrigatória" }, 401);
    }

    if (!storage_path.startsWith(`${userId}/`)) {
      return jsonResponse({ success: false, error: "Path inválido: não pertence ao usuário" }, 403);
    }

    const { data: bytes, error: downloadErr } = await supabase.storage
      .from(EDIT_INPUTS_BUCKET)
      .download(storage_path);

    if (downloadErr || !bytes) {
      console.error("[editar-imagem-flux] Erro ao baixar:", storage_path, downloadErr);
      return jsonResponse({ success: false, error: "Imagem não encontrada ou inacessível" }, 422);
    }

    if (bytes.size > MAX_IMAGE_BYTES) {
      return jsonResponse({ success: false, error: "Imagem muito grande. Máximo: 2 MB." }, 422);
    }

    const arr = new Uint8Array(bytes.size);
    arr.set(new Uint8Array(await bytes.arrayBuffer()));
    let outStr = "";
    for (let j = 0; j < arr.length; j++) outStr += String.fromCharCode(arr[j]);
    const resizedBase64 = btoa(outStr);

    let resizedWidth = typeof width === "number" ? Math.floor(width) & ~15 : 1024;
    let resizedHeight = typeof height === "number" ? Math.floor(height) & ~15 : 1024;
    if (resizedWidth < 64 || resizedHeight < 64) {
      resizedWidth = 1024;
      resizedHeight = 1024;
    }

    const bflApiKey = Deno.env.get("BFL_API_KEY");
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!bflApiKey || !openaiKey) {
      return jsonResponse({ success: false, error: "Configuração do serviço indisponível" }, 500);
    }

    let imageContext: string;
    try {
      imageContext = await generateImageContext(resizedBase64, openaiKey);
      if (!imageContext || imageContext.length < 10) {
        imageContext = "Unknown image context.";
      }
    } catch (visionErr) {
      console.error("[editar-imagem-flux] Vision error:", visionErr);
      return jsonResponse(
        { success: false, error: "Falha ao analisar a imagem. Verifique se o formato Ã© vÃ¡lido (JPEG/PNG)." },
        502
      );
    }

    const { improvedPrompt, intent, avgSimilarity, matchedIds } = await optimizePrompt(
      user_prompt.trim(),
      imageContext,
      supabase,
      openaiKey
    );

    try {
      await supabase.from("prompt_optimization_logs").insert({
        user_id: userId,
        original_prompt: user_prompt.trim(),
        improved_prompt: improvedPrompt,
        avg_similarity: avgSimilarity,
        matched_chunk_ids: matchedIds,
        metadata: {
          model: "gpt-4o-mini",
          source: "editar-imagem-flux",
          rag_match_count: matchedIds.length,
          intent,
          image_context_used: true,
          image_context_auto_generated: true,
        },
      });
    } catch (logErr) {
      console.warn("[editar-imagem-flux] Falha ao logar em prompt_optimization_logs:", logErr);
    }

    const fileSizeBytes = Math.ceil((resizedBase64.length * 3) / 4);
    let editId: string;
    let reservationId = "";
    try {
      const result = await createEditAndReserveCredits(
        supabase,
        userId,
        "edit_image",
        7,
        improvedPrompt,
        null,
        {
          imageMetadata: {
            file_size: fileSizeBytes,
            mime_type: "image/jpeg",
            width: resizedWidth,
            height: resizedHeight,
          },
          promptTextOriginal: user_prompt.trim(),
        }
      );
      editId = result.editId;
      reservationId = result.reservationId;
    } catch (creditErr) {
      const err = creditErr as Error & { status?: number };
      if (err.status === 402) {
        return jsonResponse({ success: false, error: "CrÃ©ditos insuficientes" }, 402);
      }
      throw creditErr;
    }

    // Persistir imagem original em flux-imagens para slider antes/depois
    try {
      const originalPath = `originals/${editId}.jpeg`;
      const { error: uploadOriginalErr } = await supabase.storage
        .from(FLUX_IMAGENS_BUCKET)
        .upload(originalPath, await bytes.arrayBuffer(), {
          contentType: "image/jpeg",
          upsert: true,
        });
      if (!uploadOriginalErr) {
        const { data: urlData } = supabase.storage.from(FLUX_IMAGENS_BUCKET).getPublicUrl(originalPath);
        await supabase.from("edits").update({ original_image_url: urlData.publicUrl }).eq("id", editId);
      } else {
        console.warn("[editar-imagem-flux] Falha ao persistir original (continuando):", uploadOriginalErr);
      }
    } catch (origErr) {
      console.warn("[editar-imagem-flux] Erro ao persistir original (continuando):", origErr);
    }

    const webhookUrl = `${supabaseUrl}/functions/v1/flux-webhook`;
    const bflBody = {
      prompt: improvedPrompt,
      input_image: resizedBase64,
      width: resizedWidth,
      height: resizedHeight,
      output_format: "jpeg" as const,
      webhook_url: webhookUrl,
    };

    const initRes = await fetch(BFL_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "x-key": bflApiKey,
      },
      body: JSON.stringify(bflBody),
    });

    if (!initRes.ok) {
      const errText = await initRes.text();
      let errMsg = "Erro ao iniciar ediÃ§Ã£o na BFL";
      if (initRes.status === 401) errMsg = "API key BFL invÃ¡lida";
      else if (initRes.status === 402) errMsg = "CrÃ©ditos insuficientes na conta BFL";
      else if (initRes.status === 422) errMsg = "Dados invÃ¡lidos: " + (errText || "verifique prompt e imagem");
      else if (initRes.status === 429) errMsg = "Rate limit excedido, tente novamente em breve";
      console.error("[editar-imagem-flux] BFL init error:", initRes.status, errText);
      await releaseReservedCredits(supabase, reservationId, "bfl_init_error");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse({ success: false, error: errMsg }, initRes.status >= 500 ? 502 : initRes.status);
    }

    const initData = (await initRes.json()) as AsyncWebhookResponse;
    const taskId = initData.id;

    if (!taskId) {
      console.error("[editar-imagem-flux] Resposta BFL sem id:", initData);
      await releaseReservedCredits(supabase, reservationId, "missing_task_id");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse({ success: false, error: "Resposta invÃ¡lida da API" }, 502);
    }

    await supabase.from("edits").update({ task_id: taskId }).eq("id", editId);

    const { error: insertError } = await supabase.from("flux_tasks").insert({
      task_id: taskId,
      user_id: userId,
      edit_id: editId,
      status: "pending",
    });

    if (insertError) {
      console.error("[editar-imagem-flux] Erro ao inserir flux_tasks:", insertError);
      await releaseReservedCredits(supabase, reservationId, "flux_task_insert_error");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse(
        { success: false, error: "Falha ao registrar tarefa" },
        500
      );
    }
    console.log("[editar-imagem-flux] Tarefa criada:", { taskId, editId, webhookUrl });
    return jsonResponse({ task_id: taskId, edit_id: editId });
  } catch (error) {
    console.error("[editar-imagem-flux] Erro:", error);
    return jsonResponse(
      {
        success: false,
        error: error instanceof Error ? error.message : "Erro interno",
      },
      500
    );
  }
});
