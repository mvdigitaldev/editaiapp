import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  enforceBflUserJobLimit,
  enqueueBflInitJob,
} from "../_shared/bfl_queue.ts";
import {
  createEditAndReserveCredits,
  releaseReservedCredits,
} from "../_shared/credits.ts";
import { triggerBflInitWorker } from "../_shared/bfl_init_invoke.ts";
import {
  getPhotoStorageStatus,
  storageLimitPayload,
} from "../_shared/plan_limits.ts";
import {
  EDIT_PROMPT_OPTIMIZER_SYSTEM,
  IMAGE_CONTEXT_VISION_PROMPT,
  INTENT_CLASSIFIER_SYSTEM_SINGLE,
  MINIMAL_EDIT_PROMPT_SYSTEM,
  buildMinimalEditUserMessage,
  buildOptimizerUserMessage,
  ensureSubjectPreservation,
} from "../_shared/flux_prompt_optimizer.ts";

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
  client_request_id: string;
  user_prompt: string;
  storage_path: string;
  width?: number;
  height?: number;
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
  openaiKey: string,
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
  return openaiVision(imageBase64, IMAGE_CONTEXT_VISION_PROMPT, openaiKey);
}

async function optimizePrompt(
  userPrompt: string,
  imageContext: string | undefined,
  supabase: ReturnType<typeof createClient>,
  openaiKey: string,
): Promise<{ improvedPrompt: string; intent: string; avgSimilarity: number; matchedIds: string[] }> {
  const translated = await openaiChat(
    "gpt-4o-mini",
    "Translate the user request to English. Output only the translated text.",
    userPrompt,
  );

  const intent = await openaiChat(
    "gpt-4o-mini",
    INTENT_CLASSIFIER_SYSTEM_SINGLE,
    translated,
  );

  const expandedQuery = `
User editing request:
${translated}

Image context:
${imageContext || "Unknown image context."}

Intent category: ${intent}

Focus on relevant FLUX official documentation, especially:
- intentional subject/color preservation when relocating products
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

  let improvedPrompt: string;
  if (avgSimilarity < 0.5 && translated.split(/\s+/).length <= 15) {
    improvedPrompt = await openaiChat(
      "gpt-4o-mini",
      MINIMAL_EDIT_PROMPT_SYSTEM,
      buildMinimalEditUserMessage(translated, imageContext),
    );
    improvedPrompt = improvedPrompt || translated;
  } else {
    improvedPrompt = await openaiChat(
      "gpt-4o-mini",
      EDIT_PROMPT_OPTIMIZER_SYSTEM,
      buildOptimizerUserMessage({
        translated,
        imageContext,
        intent,
        contextString,
      }),
    );
  }

  improvedPrompt = ensureSubjectPreservation(improvedPrompt || translated, {
    intent,
    imageContext,
    translatedUserPrompt: translated,
  });

  return { improvedPrompt, intent, avgSimilarity, matchedIds };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Metodo nao permitido" }, 405);
  }

  try {
    const body = (await req.json()) as Partial<RequestBody>;
    const { client_request_id, user_prompt, storage_path, width, height } = body;

    if (!client_request_id || typeof client_request_id !== "string" || client_request_id.trim().length === 0) {
      return jsonResponse({ success: false, error: "Campo 'client_request_id' e obrigatorio" }, 422);
    }

    if (!user_prompt || typeof user_prompt !== "string" || user_prompt.trim().length === 0) {
      return jsonResponse({ success: false, error: "Campo 'user_prompt' e obrigatorio" }, 422);
    }

    if (!storage_path || typeof storage_path !== "string" || storage_path.trim().length === 0) {
      return jsonResponse({ success: false, error: "Campo 'storage_path' e obrigatorio" }, 422);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ success: false, error: "Autenticacao obrigatoria" }, 401);
    }
    const authClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await authClient.auth.getUser();
    const userId = user?.id ?? null;
    if (!userId) {
      return jsonResponse({ success: false, error: "Autenticacao obrigatoria" }, 401);
    }

    if (!storage_path.startsWith(`${userId}/`)) {
      return jsonResponse({ success: false, error: "Path invalido: nao pertence ao usuario" }, 403);
    }

    await enforceBflUserJobLimit(supabase, userId);

    const storage = await getPhotoStorageStatus(supabase, userId, {
      countPending: true,
    });
    if (!storage.ok) {
      return jsonResponse(storageLimitPayload(storage), 403);
    }

    const { data: bytes, error: downloadErr } = await supabase.storage
      .from(EDIT_INPUTS_BUCKET)
      .download(storage_path);

    if (downloadErr || !bytes) {
      console.error("[editar-imagem-flux] Erro ao baixar:", storage_path, downloadErr);
      return jsonResponse({ success: false, error: "Imagem nao encontrada ou inacessivel" }, 422);
    }

    if (bytes.size > MAX_IMAGE_BYTES) {
      return jsonResponse({ success: false, error: "Imagem muito grande. Maximo: 2 MB." }, 422);
    }

    const arr = new Uint8Array(bytes.size);
    arr.set(new Uint8Array(await bytes.arrayBuffer()));
    let outStr = "";
    for (let j = 0; j < arr.length; j++) outStr += String.fromCharCode(arr[j]);
    const imageBase64 = btoa(outStr);

    let resizedWidth = typeof width === "number" ? Math.floor(width) & ~15 : 1024;
    let resizedHeight = typeof height === "number" ? Math.floor(height) & ~15 : 1024;
    if (resizedWidth < 64 || resizedHeight < 64) {
      resizedWidth = 1024;
      resizedHeight = 1024;
    }

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      return jsonResponse({ success: false, error: "Configuracao do servico indisponivel" }, 500);
    }

    let imageContext: string;
    try {
      imageContext = await generateImageContext(imageBase64, openaiKey);
      if (!imageContext || imageContext.length < 10) {
        imageContext = "Unknown image context.";
      }
    } catch (visionErr) {
      console.error("[editar-imagem-flux] Vision error:", visionErr);
      return jsonResponse({ success: false, error: "Falha ao analisar a imagem" }, 502);
    }

    const { improvedPrompt, intent, avgSimilarity, matchedIds } = await optimizePrompt(
      user_prompt.trim(),
      imageContext,
      supabase,
      openaiKey,
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

    const fileSizeBytes = Math.ceil((imageBase64.length * 3) / 4);
    let editId = "";
    let reservationId = "";
    let acceptedAt = new Date().toISOString();
    try {
      const result = await createEditAndReserveCredits(
        supabase,
        userId,
        "edit_image",
        7,
        improvedPrompt,
        null,
        {
          clientRequestId: client_request_id.trim(),
          imageMetadata: {
            file_size: fileSizeBytes,
            mime_type: "image/jpeg",
            width: resizedWidth,
            height: resizedHeight,
          },
          promptTextOriginal: user_prompt.trim(),
        },
      );
      editId = result.editId;
      reservationId = result.reservationId;
      acceptedAt = result.acceptedAt;
      if (result.reused) {
        return jsonResponse({
          task_id: result.taskId,
          edit_id: result.editId,
          status: result.status,
          accepted_at: result.acceptedAt,
        });
      }
    } catch (creditErr) {
      const err = creditErr as Error & { status?: number };
      if (err.status === 402) {
        return jsonResponse({ success: false, error: "Creditos insuficientes" }, 402);
      }
      if (err.status === 429) {
        return jsonResponse({ success: false, error: err.message }, 429);
      }
      throw creditErr;
    }

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
        console.warn("[editar-imagem-flux] Falha ao persistir original:", uploadOriginalErr);
      }
    } catch (origErr) {
      console.warn("[editar-imagem-flux] Erro ao persistir original:", origErr);
    }

    try {
      await enqueueBflInitJob(supabase, {
        edit_id: editId,
        user_id: userId,
        reservation_id: reservationId,
        operation_type: "edit_image",
        prompt_text: improvedPrompt,
        storage_paths: [storage_path],
        width: resizedWidth,
        height: resizedHeight,
        enqueued_at: new Date().toISOString(),
      });
    } catch (enqueueError) {
      console.error("[editar-imagem-flux] Erro ao enfileirar:", enqueueError);
      await releaseReservedCredits(supabase, reservationId, "enqueue_failed");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse({ success: false, error: "Falha ao enfileirar job" }, 500);
    }

    await triggerBflInitWorker(supabaseUrl);

    return jsonResponse({
      edit_id: editId,
      status: "queued",
      accepted_at: acceptedAt,
    });
  } catch (error) {
    console.error("[editar-imagem-flux] Erro:", error);
    const err = error as Error & { status?: number };
    return jsonResponse(
      {
        success: false,
        error: error instanceof Error ? error.message : "Erro interno",
      },
      err.status ?? 500,
    );
  }
});
