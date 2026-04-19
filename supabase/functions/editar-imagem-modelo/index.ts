import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  createEditAndReserveCredits,
  releaseReservedCreditsForEdit,
} from "../_shared/credits.ts";
import { registerFluxTask } from "../_shared/flux_tasks.ts";

/**
 * Extrai o user id direto do payload do JWT (base64).
 * Sem chamadas de rede — o gateway já validou a assinatura.
 */
function extractUserIdFromJwt(token: string): string | null {
  try {
    let t = token.trim();
    if (t.toLowerCase().startsWith("bearer ")) t = t.slice(7).trim();
    const parts = t.split(".");
    if (parts.length !== 3) return null;
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4));
    const payload = JSON.parse(atob(b64 + pad)) as { sub?: string; exp?: number };
    if (typeof payload.exp === "number" && payload.exp < Date.now() / 1000) return null;
    const sub = payload.sub;
    return typeof sub === "string" && sub.length > 0 ? sub : null;
  } catch {
    return null;
  }
}

function resolveUserId(req: Request, bodyAccessToken?: string | null): string | null {
  const sources = [
    req.headers.get("Authorization"),
    req.headers.get("authorization"),
    req.headers.get("x-forwarded-authorization"),
    typeof bodyAccessToken === "string" ? bodyAccessToken : null,
  ];
  for (const raw of sources) {
    if (!raw?.trim()) continue;
    const uid = extractUserIdFromJwt(raw);
    if (uid) return uid;
  }
  return null;
}
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
  client_request_id: string;
  modelo_id: string;
  storage_path: string;
  width?: number;
  height?: number;
  /** Somente para categorias edit_mode = guided */
  selected_improvements?: string[];
  user_notes?: string;
  /** Fallback quando o gateway não repassa Authorization (ex.: app móvel). */
  access_token?: string;
}

interface AsyncWebhookResponse {
  id: string;
  polling_url?: string;
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
    return jsonResponse({ success: false, error: "Método não permitido" }, 405);
  }

  /** Preenchido após `createEditAndReserveCredits`; usado no catch global para liberar reserva. */
  let editId: string | undefined;

  try {
    const body = (await req.json()) as Partial<RequestBody>;
    const {
      client_request_id,
      modelo_id,
      storage_path,
      width,
      height,
      selected_improvements,
      user_notes,
      access_token,
    } = body;

    if (!modelo_id || typeof modelo_id !== "string" || modelo_id.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'modelo_id' é obrigatório e não pode estar vazio" },
        422
      );
    }

    if (
      !client_request_id ||
      typeof client_request_id !== "string" ||
      client_request_id.trim().length === 0
    ) {
      return jsonResponse(
        { success: false, error: "Campo 'client_request_id' é obrigatório" },
        422,
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

    const userId = resolveUserId(req, access_token);
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
      .select("id, prompt_padrao, categoria_id")
      .eq("id", modelo_id.trim())
      .eq("ativo", true)
      .maybeSingle();

    if (modeloErr || !modelo) {
      return jsonResponse(
        { success: false, error: "Modelo não encontrado ou inativo" },
        404
      );
    }

    const categoriaId = modelo.categoria_id as string;
    const { data: categoriaRow } = await supabase
      .from("categorias")
      .select("edit_mode")
      .eq("id", categoriaId)
      .maybeSingle();

    const editMode = (categoriaRow?.edit_mode as string | undefined) ?? "guided";

    const improvementsRaw = Array.isArray(selected_improvements)
      ? selected_improvements.filter((s): s is string => typeof s === "string")
      : [];
    const improvements = improvementsRaw.map((s) => s.trim()).filter((s) => s.length > 0);
    const notesTrim = typeof user_notes === "string" ? user_notes.trim() : "";

    if (editMode === "guided") {
      if (improvements.length === 0 && notesTrim.length === 0) {
        return jsonResponse(
          {
            success: false,
            error: "Selecione ao menos uma sugestão ou descreva o que deseja alterar.",
          },
          422,
        );
      }
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
        { success: false, error: "Falha ao analisar a imagem. Verifique se o formato é válido (JPEG/PNG)." },
        502
      );
    }

    const promptPadrao = (modelo.prompt_padrao as string)?.trim() ?? "";
    let promptMiddle = "";
    if (editMode === "guided") {
      const bullets = improvements.map((s) => `- ${s}`).join("\n");
      const impBlock = improvements.length > 0
        ? `User-selected improvements:\n${bullets}`
        : "User-selected improvements: (none)";
      const notesBlock = notesTrim.length > 0
        ? `Additional notes: ${notesTrim}`
        : "Additional notes: (none)";
      promptMiddle = `\n\n${impBlock}\n\n${notesBlock}`;
    }
    const promptFinal = `${promptPadrao}${promptMiddle}\n\nImage context: ${imageContext}`;

    const fileSizeBytes = Math.ceil((resizedBase64.length * 3) / 4);
    let acceptedAt = new Date().toISOString();
    try {
      const result = await createEditAndReserveCredits(
        supabase,
        userId,
        "edit_model",
        CREDITS_EDIT_MODEL,
        promptFinal,
        null,
        {
          clientRequestId: client_request_id.trim(),
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
        return jsonResponse({ success: false, error: "Créditos insuficientes" }, 402);
      }
      throw creditErr;
    }

    const abortAfterReserve = async (reason: string, errMsg: string, httpStatus: number) => {
      const eid = editId!;
      await releaseReservedCreditsForEdit(supabase, eid, reason);
      await supabase.from("edits").update({ status: "failed" }).eq("id", eid);
      return jsonResponse(
        { success: false, error: errMsg, edit_id: eid },
        httpStatus,
      );
    };

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
      let errMsg = "Erro ao iniciar edição na BFL";
      if (initRes.status === 401) errMsg = "API key BFL inválida";
      else if (initRes.status === 402) {
        errMsg =
          "Créditos insuficientes no provedor de imagem. Tente mais tarde ou contate o suporte.";
      } else if (initRes.status === 422) {
        errMsg = "Dados inválidos: " + (errText || "verifique prompt e imagem");
      } else if (initRes.status === 429) errMsg = "Rate limit excedido, tente novamente em breve";
      console.error("[editar-imagem-modelo] BFL init error:", initRes.status, errText);
      const reason = initRes.status === 402 ? "bfl_provider_402" : "bfl_init_error";
      /** 402 da BFL não é saldo do app — evita confusão com `credits_shop`. */
      const httpStatus = initRes.status === 402
        ? 502
        : (initRes.status >= 500 ? 502 : initRes.status);
      return await abortAfterReserve(reason, errMsg, httpStatus);
    }

    const initData = (await initRes.json()) as AsyncWebhookResponse;
    const taskId = initData.id;
    const pollingUrl =
      typeof initData.polling_url === "string" && initData.polling_url.trim().length > 0
        ? initData.polling_url.trim()
        : null;

    if (!taskId) {
      console.error("[editar-imagem-modelo] Resposta BFL sem id:", initData);
      return await abortAfterReserve("missing_task_id", "Resposta inválida da API", 502);
    }

    try {
      await registerFluxTask(supabase, {
        taskId,
        userId,
        editId,
        provider: "bfl",
        pollingUrl,
      });
    } catch (registerError) {
      console.error("[editar-imagem-modelo] Erro ao registrar tarefa:", registerError);
      return await abortAfterReserve("flux_task_insert_error", "Falha ao registrar tarefa", 500);
    }
    console.log("[editar-imagem-modelo] Tarefa criada:", { taskId, editId, webhookUrl });
    return jsonResponse({
      task_id: taskId,
      edit_id: editId,
      status: "queued",
      accepted_at: acceptedAt,
    });
  } catch (error) {
    console.error("[editar-imagem-modelo] Erro:", error);
    if (editId) {
      try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
        const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        const supabaseCleanup = createClient(supabaseUrl, supabaseKey);
        await releaseReservedCreditsForEdit(supabaseCleanup, editId, "edge_uncaught_error");
        await supabaseCleanup.from("edits").update({ status: "failed" }).eq("id", editId);
      } catch (cleanupErr) {
        console.error("[editar-imagem-modelo] Falha ao liberar reserva após erro:", cleanupErr);
      }
    }
    return jsonResponse(
      {
        success: false,
        error: error instanceof Error ? error.message : "Erro interno",
        ...(editId ? { edit_id: editId } : {}),
      },
      500
    );
  }
});

