import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { deductAndCreateEdit, refundCredits } from "./credits.ts";
import {
  ImageMagick,
  initializeImageMagick,
  MagickFormat,
} from "npm:@imagemagick/magick-wasm@0.0.30";

const BFL_API_URL = "https://api.bfl.ai/v1/flux-2-pro";
const OPENAI_API_URL = "https://api.openai.com/v1";
const MAX_MEGAPIXELS_SINGLE = 1.5;
const MAX_MEGAPIXELS_MULTI = 1.0;
const JPEG_QUALITY = 90;
const MAX_BASE64_BYTES = 10 * 1024 * 1024; // ~10 MB por imagem

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  user_prompt: string;
  images: string[];
  width: number;
  height: number;
}

let magickInitialized = false;

async function ensureMagickInit() {
  if (magickInitialized) return;
  const wasmPath = new URL("magick.wasm", import.meta.resolve("npm:@imagemagick/magick-wasm@0.0.30"));
  const wasmBytes = await Deno.readFile(wasmPath);
  await initializeImageMagick(wasmBytes);
  magickInitialized = true;
}

function resizeToMaxMp(
  imageBase64: string,
  maxMp: number
): { base64: string; width: number; height: number } {
  const binary = atob(imageBase64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

  let outWidth = 0;
  let outHeight = 0;
  let outData: Uint8Array = new Uint8Array(0);

  ImageMagick.read(bytes, (img) => {
    const w = img.width;
    const h = img.height;
    if (w <= 0 || h <= 0) {
      throw new Error("Imagem sem dimensões válidas");
    }
    const total = w * h;
    const maxPixels = maxMp * 1_000_000;

    let newW = w;
    let newH = h;

    if (total > maxPixels) {
      const scale = Math.sqrt(maxPixels / total);
      newW = Math.max(64, Math.floor(w * scale) & ~15);
      newH = Math.max(64, Math.floor(h * scale) & ~15);
      img.resize(newW, newH);
    }

    if (newW < 64 || newH < 64) {
      const scaleUp = Math.max(64 / newW, 64 / newH);
      newW = Math.max(64, Math.floor(newW * scaleUp) & ~15);
      newH = Math.max(64, Math.floor(newH * scaleUp) & ~15);
      img.resize(newW, newH);
    }

    outWidth = newW;
    outHeight = newH;
    img.quality = JPEG_QUALITY;
    outData = img.write(MagickFormat.Jpeg, (data: Uint8Array) => data);
  });

  if (outWidth < 64 || outHeight < 64 || !outData || outData.length === 0) {
    throw new Error("Falha ao processar imagem. Verifique se o formato é válido (JPEG/PNG).");
  }

  let outStr = "";
  for (let i = 0; i < outData.length; i++) outStr += String.fromCharCode(outData[i]);
  const outBase64 = btoa(outStr);
  return { base64: outBase64, width: outWidth, height: outHeight };
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

function normalizeBase64(input: string): string {
  const trimmed = input.trim();
  const dataUrlMatch = trimmed.match(/^data:image\/[a-zA-Z]+;base64,(.+)$/);
  return dataUrlMatch ? dataUrlMatch[1] : trimmed;
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

async function optimizePromptMultiRef(
  userPrompt: string,
  imageCount: number,
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
User editing request:
${translated}

Image context:
${imageContext}

Intent category: ${intent}

Focus on relevant FLUX official documentation, especially:
- multi-reference image editing
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

  const improvedPrompt = await openaiChat(
    "gpt-4o-mini",
    `You are a professional FLUX multi-reference image editing prompt optimizer.

STRICT RULES:
- OUTPUT ONLY the final improved English prompt.
- This is MULTI-REFERENCE editing: combine reference images (clothing, accessories, objects) into a cohesive scene.
- Describe how each input should be used in the final composition.
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Método não permitido" }, 405);
  }

  try {
    const body = (await req.json()) as Partial<RequestBody>;
    const { user_prompt, images, width, height } = body;

    if (!user_prompt || typeof user_prompt !== "string" || user_prompt.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'user_prompt' é obrigatório e não pode estar vazio" },
        422
      );
    }

    if (!Array.isArray(images) || images.length < 1 || images.length > 8) {
      return jsonResponse(
        { success: false, error: "Campo 'images' deve ser um array com 1 a 8 imagens em base64" },
        422
      );
    }

    if (typeof width !== "number" || typeof height !== "number") {
      return jsonResponse(
        { success: false, error: "Campos 'width' e 'height' são obrigatórios e devem ser números" },
        422
      );
    }

    if (width < 64 || height < 64) {
      return jsonResponse(
        { success: false, error: "width e height devem ser >= 64" },
        422
      );
    }

    const outW = Math.floor(width) & ~15;
    const outH = Math.floor(height) & ~15;
    if (outW < 64 || outH < 64) {
      return jsonResponse(
        { success: false, error: "width e height devem ser múltiplos de 16 e >= 64" },
        422
      );
    }

    const bflApiKey = Deno.env.get("BFL_API_KEY");
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!bflApiKey) {
      console.error("[editar-multi-imagem-flux] BFL_API_KEY não configurada");
      return jsonResponse(
        { success: false, error: "Configuração do serviço indisponível" },
        500
      );
    }
    if (!openaiKey) {
      console.error("[editar-multi-imagem-flux] OPENAI_API_KEY não configurada");
      return jsonResponse(
        { success: false, error: "Configuração do serviço indisponível" },
        500
      );
    }

    const normalizedImages: string[] = [];
    for (let i = 0; i < images.length; i++) {
      const img = images[i];
      if (typeof img !== "string" || img.trim().length < 100) {
        return jsonResponse(
          { success: false, error: `Imagem ${i + 1} inválida ou base64 corrompido` },
          422
        );
      }
      const normalized = normalizeBase64(img);
      const base64Bytes = Math.ceil((normalized.length * 3) / 4);
      if (base64Bytes > MAX_BASE64_BYTES) {
        return jsonResponse(
          { success: false, error: `Imagem ${i + 1} muito grande. Máximo recomendado: ~10 MB.` },
          422
        );
      }
      normalizedImages.push(normalized);
    }

    const maxMp = images.length > 1 ? MAX_MEGAPIXELS_MULTI : MAX_MEGAPIXELS_SINGLE;
    await ensureMagickInit();

    const resizedImages: string[] = [];
    try {
      for (let i = 0; i < normalizedImages.length; i++) {
        const resized = resizeToMaxMp(normalizedImages[i], maxMp);
        resizedImages.push(resized.base64);
      }
    } catch (resizeErr) {
      console.error("[editar-multi-imagem-flux] Resize error:", resizeErr);
      return jsonResponse(
        { success: false, error: "Falha ao processar imagem. Verifique se o formato é válido (JPEG/PNG)." },
        422
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    let userId: string | null = null;
    const authHeader = req.headers.get("Authorization");
    if (authHeader?.startsWith("Bearer ")) {
      const token = authHeader.replace("Bearer ", "");
      const { data: { user } } = await supabase.auth.getUser(token);
      userId = user?.id ?? null;
    }
    if (!userId) {
      return jsonResponse({ success: false, error: "Autenticação obrigatória" }, 401);
    }

    const { improvedPrompt, intent, avgSimilarity, matchedIds } = await optimizePromptMultiRef(
      user_prompt.trim(),
      resizedImages.length,
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
          source: "editar-multi-imagem-flux",
          rag_match_count: matchedIds.length,
          intent,
          image_count: resizedImages.length,
        },
      });
    } catch (logErr) {
      console.warn("[editar-multi-imagem-flux] Falha ao logar em prompt_optimization_logs:", logErr);
    }

    const creditsMulti = 7 + (resizedImages.length - 1) * 3;
    let editId: string;
    try {
      const result = await deductAndCreateEdit(
        supabase,
        userId,
        "multi_image",
        creditsMulti,
        improvedPrompt,
        null
      );
      editId = result.editId;
    } catch (creditErr) {
      const err = creditErr as Error & { status?: number };
      if (err.status === 402) {
        return jsonResponse({ success: false, error: "Créditos insuficientes" }, 402);
      }
      throw creditErr;
    }

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
      let errMsg = "Erro ao iniciar edição na BFL";
      if (initRes.status === 401) errMsg = "API key BFL inválida";
      else if (initRes.status === 402) errMsg = "Créditos insuficientes na conta BFL";
      else if (initRes.status === 422) errMsg = "Dados inválidos: " + (errText || "verifique prompt e imagens");
      else if (initRes.status === 429) errMsg = "Rate limit excedido, tente novamente em breve";
      console.error("[editar-multi-imagem-flux] BFL init error:", initRes.status, errText);
      await refundCredits(supabase, userId, creditsMulti, editId);
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse({ success: false, error: errMsg }, initRes.status >= 500 ? 502 : initRes.status);
    }

    const initData = (await initRes.json()) as AsyncWebhookResponse;
    const taskId = initData.id;

    if (!taskId) {
      console.error("[editar-multi-imagem-flux] Resposta BFL sem id:", initData);
      await refundCredits(supabase, userId, creditsMulti, editId);
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse({ success: false, error: "Resposta inválida da API" }, 502);
    }

    await supabase.from("edits").update({ task_id: taskId }).eq("id", editId);

    const { error: insertError } = await supabase.from("flux_tasks").insert({
      task_id: taskId,
      user_id: userId,
      edit_id: editId,
      status: "pending",
    });

    if (insertError) {
      console.error("[editar-multi-imagem-flux] Erro ao inserir flux_tasks:", insertError);
      return jsonResponse(
        { success: false, error: "Falha ao registrar tarefa" },
        500
      );
    }

    return jsonResponse({ task_id: taskId });
  } catch (error) {
    console.error("[editar-multi-imagem-flux] Erro:", error);
    return jsonResponse(
      {
        success: false,
        error: error instanceof Error ? error.message : "Erro interno",
      },
      500
    );
  }
});
