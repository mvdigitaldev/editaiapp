import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  createEditAndReserveCredits,
  releaseReservedCredits,
} from "../_shared/credits.ts";
const BFL_API_URL = "https://api.bfl.ai/v1/flux-2-pro";
const OPENAI_API_URL = "https://api.openai.com/v1";
const EDIT_INPUTS_BUCKET = "edit-inputs";
const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const CREDITS_EDIT_MODEL = 7;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  modelo_id: string;
  storage_path: string;
  width?: number;
  height?: number;
}

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
    const { modelo_id, storage_path, width, height } = body;

    if (!modelo_id || typeof modelo_id !== "string" || modelo_id.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'modelo_id' é obrigatório e não pode estar vazio" },
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

    const userId = await resolveAuthenticatedUserId(req, supabase, supabaseUrl);
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
      console.error("[editar-imagem-modelo] Erro ao baixar:", storage_path, downloadErr);
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

    const { data: modelo, error: modeloErr } = await supabase
      .from("modelos")
      .select("id, prompt_padrao")
      .eq("id", modelo_id.trim())
      .eq("ativo", true)
      .maybeSingle();

    if (modeloErr || !modelo) {
      return jsonResponse(
        { success: false, error: "Modelo não encontrado ou inativo" },
        404
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

    // Persistir imagem original em flux-imagens para slider antes/depois
    const FLUX_IMAGENS_BUCKET = "flux-imagens";
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
        console.warn("[editar-imagem-modelo] Falha ao persistir original (continuando):", uploadOriginalErr);
      }
    } catch (origErr) {
      console.warn("[editar-imagem-modelo] Erro ao persistir original (continuando):", origErr);
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
    console.log("[editar-imagem-modelo] Tarefa criada:", { taskId, editId, webhookUrl });
    return jsonResponse({ task_id: taskId, edit_id: editId });
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

