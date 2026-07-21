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
  EDIT_PROMPT_OPTIMIZER_SYSTEM,
  INTENT_CLASSIFIER_SYSTEM_SINGLE,
  MINIMAL_EDIT_PROMPT_SYSTEM,
  buildMinimalEditUserMessage,
  buildOptimizerUserMessage,
  ensureSubjectPreservation,
} from "../_shared/flux_prompt_optimizer.ts";

const OPENAI_API_URL = "https://api.openai.com/v1";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  client_request_id: string;
  user_prompt: string;
  image_context?: string;
  width: number;
  height: number;
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
    const { client_request_id, user_prompt, image_context, width, height } = body;

    if (!client_request_id || typeof client_request_id !== "string" || client_request_id.trim().length === 0) {
      return jsonResponse({ success: false, error: "Campo 'client_request_id' e obrigatorio" }, 422);
    }

    if (!user_prompt || typeof user_prompt !== "string" || user_prompt.trim().length === 0) {
      return jsonResponse({ success: false, error: "Campo 'user_prompt' e obrigatorio" }, 422);
    }

    if (typeof width !== "number" || typeof height !== "number") {
      return jsonResponse({ success: false, error: "Campos 'width' e 'height' sao obrigatorios" }, 422);
    }

    if (width < 64 || height < 64) {
      return jsonResponse({ success: false, error: "width e height devem ser >= 64" }, 422);
    }

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      console.error("[gerar-imagem-flux] OPENAI_API_KEY nao configurada");
      return jsonResponse({ success: false, error: "Configuracao do servico indisponivel" }, 500);
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

    await enforceBflUserJobLimit(supabase, userId);

    const { improvedPrompt, intent, avgSimilarity, matchedIds } = await optimizePrompt(
      user_prompt.trim(),
      typeof image_context === "string" ? image_context.trim() || undefined : undefined,
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
          source: "flutter_app",
          rag_match_count: matchedIds.length,
          intent,
          image_context_used: !!image_context,
        },
      });
    } catch (logErr) {
      console.warn("[gerar-imagem-flux] Falha ao logar em prompt_optimization_logs:", logErr);
    }

    let editId = "";
    let reservationId = "";
    let acceptedAt = new Date().toISOString();
    try {
      const result = await createEditAndReserveCredits(
        supabase,
        userId,
        "text_to_image",
        5,
        improvedPrompt,
        null,
        {
          clientRequestId: client_request_id.trim(),
          imageMetadata: {
            mime_type: "image/jpeg",
            width,
            height,
          },
          promptTextOriginal: user_prompt.trim(),
        },
      );
      editId = result.editId;
      reservationId = result.reservationId;
      acceptedAt = result.acceptedAt;
      if (result.reused) {
        return jsonResponse({
          edit_id: result.editId,
          task_id: result.taskId,
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
      await enqueueBflInitJob(supabase, {
        edit_id: editId,
        user_id: userId,
        reservation_id: reservationId,
        operation_type: "text_to_image",
        prompt_text: improvedPrompt,
        storage_paths: [],
        width,
        height,
        enqueued_at: new Date().toISOString(),
      });
    } catch (enqueueError) {
      console.error("[gerar-imagem-flux] Erro ao enfileirar job:", enqueueError);
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
    console.error("[gerar-imagem-flux] Erro:", error);
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
