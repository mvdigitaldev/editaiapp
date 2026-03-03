import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  createEditAndReserveCredits,
  releaseReservedCredits,
} from "../_shared/credits.ts";
import {
  ImageMagick,
  initializeImageMagick,
  MagickFormat,
} from "npm:@imagemagick/magick-wasm@0.0.30";

const BFL_API_URL = "https://api.bfl.ai/v1/flux-2-pro";
const OPENAI_API_URL = "https://api.openai.com/v1";
const MAX_MEGAPIXELS = 1.5;
const JPEG_QUALITY = 90;
const MAX_BASE64_BYTES = 10 * 1024 * 1024;
const CREDITS_EDIT_MODEL = 7;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  modelo_id: string;
  image_base64: string;
}

let magickInitialized = false;

function getBearerToken(req: Request): string | null {
  const rawHeader =
    req.headers.get("Authorization") ??
    req.headers.get("authorization") ??
    req.headers.get("x-forwarded-authorization");
  if (!rawHeader) return null;

  const match = rawHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;

  const token = match[1]?.trim() ?? "";
  return token.length > 0 ? token : null;
}
async function resolveAuthenticatedUserId(
  req: Request,
  supabase: ReturnType<typeof createClient>,
  supabaseUrl: string,
): Promise<string | null> {
  const token = getBearerToken(req);
  if (!token) return null;
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims(token);
  const claimSub = claimsData?.claims?.sub;
  if (!claimsError && typeof claimSub === "string" && claimSub.length > 0) {
    return claimSub;
  }
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!anonKey) return null;
  const authClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: { user }, error: userError } = await authClient.auth.getUser();
  if (userError) return null;
  return user?.id ?? null;
}

async function ensureMagickInit() {
  if (magickInitialized) return;
  const wasmPath = new URL("magick.wasm", import.meta.resolve("npm:@imagemagick/magick-wasm@0.0.30"));
  const wasmBytes = await Deno.readFile(wasmPath);
  await initializeImageMagick(wasmBytes);
  magickInitialized = true;
}

function resizeToMaxMp(imageBase64: string): { base64: string; width: number; height: number } {
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
      throw new Error("Imagem sem dimensÃµes vÃ¡lidas");
    }
    const total = w * h;
    const maxPixels = MAX_MEGAPIXELS * 1_000_000;

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
    throw new Error("Falha ao processar imagem. Verifique se o formato Ã© vÃ¡lido (JPEG/PNG).");
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "MÃ©todo nÃ£o permitido" }, 405);
  }

  try {
    const body = (await req.json()) as Partial<RequestBody>;
    const { modelo_id, image_base64 } = body;

    if (!modelo_id || typeof modelo_id !== "string" || modelo_id.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'modelo_id' Ã© obrigatÃ³rio e nÃ£o pode estar vazio" },
        422
      );
    }

    if (!image_base64 || typeof image_base64 !== "string" || image_base64.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'image_base64' Ã© obrigatÃ³rio e nÃ£o pode estar vazio" },
        422
      );
    }

    const bflApiKey = Deno.env.get("BFL_API_KEY");
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!bflApiKey) {
      console.error("[editar-imagem-modelo] BFL_API_KEY nÃ£o configurada");
      return jsonResponse(
        { success: false, error: "ConfiguraÃ§Ã£o do serviÃ§o indisponÃ­vel" },
        500
      );
    }
    if (!openaiKey) {
      console.error("[editar-imagem-modelo] OPENAI_API_KEY nÃ£o configurada");
      return jsonResponse(
        { success: false, error: "ConfiguraÃ§Ã£o do serviÃ§o indisponÃ­vel" },
        500
      );
    }

    const imageBase64 = normalizeBase64(image_base64);
    if (imageBase64.length < 100) {
      return jsonResponse(
        { success: false, error: "Imagem invÃ¡lida ou base64 corrompido" },
        422
      );
    }

    const base64Bytes = Math.ceil((imageBase64.length * 3) / 4);
    if (base64Bytes > MAX_BASE64_BYTES) {
      return jsonResponse(
        { success: false, error: "Imagem muito grande. MÃ¡ximo recomendado: ~10 MB." },
        422
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const userId = await resolveAuthenticatedUserId(req, supabase, supabaseUrl);
    if (!userId) {
      console.error("[editar-imagem-modelo] Falha ao autenticar usuario");
      return jsonResponse({ success: false, error: "Autenticacao obrigatoria" }, 401);
    }

    const { data: modelo, error: modeloErr } = await supabase
      .from("modelos")
      .select("id, prompt_padrao")
      .eq("id", modelo_id.trim())
      .eq("ativo", true)
      .maybeSingle();

    if (modeloErr || !modelo) {
      return jsonResponse(
        { success: false, error: "Modelo nÃ£o encontrado ou inativo" },
        404
      );
    }

    await ensureMagickInit();
    let resizedBase64: string;
    let resizedWidth: number;
    let resizedHeight: number;
    try {
      const resized = resizeToMaxMp(imageBase64);
      resizedBase64 = resized.base64;
      resizedWidth = resized.width;
      resizedHeight = resized.height;
    } catch (resizeErr) {
      console.error("[editar-imagem-modelo] Resize error:", resizeErr);
      return jsonResponse(
        { success: false, error: "Falha ao processar imagem. Verifique se o formato Ã© vÃ¡lido (JPEG/PNG)." },
        422
      );
    }

    let imageContext: string;
    try {
      imageContext = await generateImageContext(resizedBase64, openaiKey);
      if (!imageContext || imageContext.length < 10) {
        imageContext = "Unknown image context.";
      }
    } catch (visionErr) {
      console.error("[editar-imagem-modelo] Vision error:", visionErr);
      return jsonResponse(
        { success: false, error: "Falha ao analisar a imagem. Verifique se o formato Ã© vÃ¡lido (JPEG/PNG)." },
        502
      );
    }

    const promptPadrao = (modelo.prompt_padrao as string)?.trim() ?? "";
    const promptFinal = `${promptPadrao}\n\nImage context: ${imageContext}`;

    const fileSizeBytes = Math.ceil((resizedBase64.length * 3) / 4);
    let editId: string;
    let reservationId = "";
    try {
      const result = await createEditAndReserveCredits(
        supabase,
        userId,
        "edit_model",
        CREDITS_EDIT_MODEL,
        promptFinal,
        null,
        {
          imageMetadata: {
            file_size: fileSizeBytes,
            mime_type: "image/jpeg",
            width: resizedWidth,
            height: resizedHeight,
          },
          promptTextOriginal: promptPadrao,
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

    const webhookUrl = `${supabaseUrl}/functions/v1/flux-webhook`;
    const bflBody = {
      prompt: promptFinal,
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
      console.error("[editar-imagem-modelo] BFL init error:", initRes.status, errText);
      await releaseReservedCredits(supabase, reservationId, "bfl_init_error");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse({ success: false, error: errMsg }, initRes.status >= 500 ? 502 : initRes.status);
    }

    const initData = (await initRes.json()) as AsyncWebhookResponse;
    const taskId = initData.id;

    if (!taskId) {
      console.error("[editar-imagem-modelo] Resposta BFL sem id:", initData);
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
      console.error("[editar-imagem-modelo] Erro ao inserir flux_tasks:", insertError);
      await releaseReservedCredits(supabase, reservationId, "flux_task_insert_error");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse(
        { success: false, error: "Falha ao registrar tarefa" },
        500
      );
    }
    return jsonResponse({ task_id: taskId });
  } catch (error) {
    console.error("[editar-imagem-modelo] Erro:", error);
    return jsonResponse(
      {
        success: false,
        error: error instanceof Error ? error.message : "Erro interno",
      },
      500
    );
  }
});

