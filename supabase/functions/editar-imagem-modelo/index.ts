import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  enforceBflUserJobLimit,
  enqueueBflInitJob,
} from "../_shared/bfl_queue.ts";
import {
  createEditAndReserveCredits,
  releaseReservedCreditsForEdit,
} from "../_shared/credits.ts";
import { triggerBflInitWorker } from "../_shared/bfl_init_invoke.ts";
import {
  IMAGE_CONTEXT_VISION_PROMPT,
  ensureSubjectPreservation,
} from "../_shared/flux_prompt_optimizer.ts";

function extractUserIdFromJwt(token: string): string | null {
  try {
    let value = token.trim();
    if (value.toLowerCase().startsWith("bearer ")) value = value.slice(7).trim();
    const parts = value.split(".");
    if (parts.length !== 3) return null;
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4));
    const payload = JSON.parse(atob(b64 + pad)) as { sub?: string; exp?: number };
    if (typeof payload.exp === "number" && payload.exp < Date.now() / 1000) return null;
    return typeof payload.sub === "string" && payload.sub.length > 0 ? payload.sub : null;
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
    const userId = extractUserIdFromJwt(raw);
    if (userId) return userId;
  }
  return null;
}

const OPENAI_API_URL = "https://api.openai.com/v1";
const EDIT_INPUTS_BUCKET = "edit-inputs";
const FLUX_IMAGENS_BUCKET = "flux-imagens";
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
  selected_improvements?: string[];
  user_notes?: string;
  access_token?: string;
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Metodo nao permitido" }, 405);
  }

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
      return jsonResponse({ success: false, error: "Campo 'modelo_id' e obrigatorio" }, 422);
    }

    if (!client_request_id || typeof client_request_id !== "string" || client_request_id.trim().length === 0) {
      return jsonResponse({ success: false, error: "Campo 'client_request_id' e obrigatorio" }, 422);
    }

    if (!storage_path || typeof storage_path !== "string" || storage_path.trim().length === 0) {
      return jsonResponse({ success: false, error: "Campo 'storage_path' e obrigatorio" }, 422);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const userId = resolveUserId(req, access_token);
    if (!userId) {
      return jsonResponse({ success: false, error: "Autenticacao obrigatoria" }, 401);
    }

    if (!storage_path.startsWith(`${userId}/`)) {
      return jsonResponse({ success: false, error: "Path invalido: nao pertence ao usuario" }, 403);
    }

    await enforceBflUserJobLimit(supabase, userId);

    const { data: bytes, error: downloadErr } = await supabase.storage
      .from(EDIT_INPUTS_BUCKET)
      .download(storage_path);

    if (downloadErr || !bytes) {
      console.error("[editar-imagem-modelo] Erro ao baixar:", storage_path, downloadErr);
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

    const { data: modelo, error: modeloErr } = await supabase
      .from("modelos")
      .select("id, prompt_padrao, categoria_id")
      .eq("id", modelo_id.trim())
      .eq("ativo", true)
      .maybeSingle();

    if (modeloErr || !modelo) {
      return jsonResponse({ success: false, error: "Modelo nao encontrado ou inativo" }, 404);
    }

    const categoriaId = modelo.categoria_id as string;
    const { data: categoriaRow } = await supabase
      .from("categorias")
      .select("edit_mode")
      .eq("id", categoriaId)
      .maybeSingle();

    const editMode = (categoriaRow?.edit_mode as string | undefined) ?? "guided";
    const improvementsRaw = Array.isArray(selected_improvements)
      ? selected_improvements.filter((item): item is string => typeof item === "string")
      : [];
    const improvements = improvementsRaw.map((item) => item.trim()).filter((item) => item.length > 0);
    const notesTrim = typeof user_notes === "string" ? user_notes.trim() : "";

    if (editMode === "guided" && improvements.length === 0 && notesTrim.length === 0) {
      return jsonResponse(
        { success: false, error: "Selecione ao menos uma sugestao ou descreva o que deseja alterar." },
        422,
      );
    }

    let imageContext: string;
    try {
      imageContext = await generateImageContext(imageBase64, openaiKey);
      if (!imageContext || imageContext.length < 10) {
        imageContext = "Unknown image context.";
      }
    } catch (visionErr) {
      console.error("[editar-imagem-modelo] Vision error:", visionErr);
      return jsonResponse({ success: false, error: "Falha ao analisar a imagem" }, 502);
    }

    const promptPadrao = (modelo.prompt_padrao as string)?.trim() ?? "";
    let promptMiddle = "";
    if (editMode === "guided") {
      const bullets = improvements.map((item) => `- ${item}`).join("\n");
      const improvementsBlock = improvements.length > 0
        ? `User-selected improvements:\n${bullets}`
        : "User-selected improvements: (none)";
      const notesBlock = notesTrim.length > 0
        ? `Additional notes: ${notesTrim}`
        : "Additional notes: (none)";
      promptMiddle = `\n\n${improvementsBlock}\n\n${notesBlock}`;
    }
    const promptWithContext = `${promptPadrao}${promptMiddle}\n\nImage context: ${imageContext}`;
    const promptFinal = ensureSubjectPreservation(promptWithContext, {
      intent: "scene_change",
      imageContext,
      translatedUserPrompt: `${promptPadrao} ${notesTrim}`,
    });

    const fileSizeBytes = Math.ceil((imageBase64.length * 3) / 4);
    let reservationId = "";
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
        console.warn("[editar-imagem-modelo] Falha ao persistir original:", uploadOriginalErr);
      }
    } catch (origErr) {
      console.warn("[editar-imagem-modelo] Erro ao persistir original:", origErr);
    }

    try {
      await enqueueBflInitJob(supabase, {
        edit_id: editId,
        user_id: userId,
        reservation_id: reservationId,
        operation_type: "edit_model",
        prompt_text: promptFinal,
        storage_paths: [storage_path],
        width: resizedWidth,
        height: resizedHeight,
        enqueued_at: new Date().toISOString(),
      });
    } catch (enqueueError) {
      console.error("[editar-imagem-modelo] Erro ao enfileirar:", enqueueError);
      await releaseReservedCreditsForEdit(supabase, editId, "enqueue_failed");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse(
        { success: false, error: "Falha ao enfileirar job", edit_id: editId },
        500,
      );
    }

    await triggerBflInitWorker(supabaseUrl);

    return jsonResponse({
      edit_id: editId,
      status: "queued",
      accepted_at: acceptedAt,
    });
  } catch (error) {
    console.error("[editar-imagem-modelo] Erro:", error);
    const err = error as Error & { status?: number };
    if (editId) {
      try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
        const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        const cleanupClient = createClient(supabaseUrl, supabaseKey);
        await releaseReservedCreditsForEdit(cleanupClient, editId, "edge_uncaught_error");
        await cleanupClient.from("edits").update({ status: "failed" }).eq("id", editId);
      } catch (cleanupErr) {
        console.error("[editar-imagem-modelo] Falha ao liberar reserva apos erro:", cleanupErr);
      }
    }
    return jsonResponse(
      {
        success: false,
        error: error instanceof Error ? error.message : "Erro interno",
        ...(editId ? { edit_id: editId } : {}),
      },
      err.status ?? 500,
    );
  }
});
