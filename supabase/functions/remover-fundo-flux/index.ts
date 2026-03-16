import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  consumeReservedCredits,
  createEditAndReserveCredits,
  releaseReservedCredits,
} from "../_shared/credits.ts";

const FAL_API_URL = "https://fal.run/fal-ai/birefnet";
const BUCKET_NAME = "flux-imagens";
const EDIT_INPUTS_BUCKET = "edit-inputs";
const MAX_IMAGE_BYTES = 2 * 1024 * 1024;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  storage_path: string;
}

interface FalBirefnetResponse {
  image?: { url: string; content_type?: string };
  detail?: string;
}

function jsonResponse(data: object, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
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
    const { storage_path } = body;

    if (!storage_path || typeof storage_path !== "string" || storage_path.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'storage_path' é obrigatório" },
        422
      );
    }

    const falKey = Deno.env.get("FAL_KEY");
    if (!falKey) {
      return jsonResponse({ success: false, error: "Configuração do serviço indisponível" }, 500);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ success: false, error: "AutenticaÃ§Ã£o obrigatÃ³ria" }, 401);
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
      console.error("[remover-fundo-flux] Erro ao baixar:", storage_path, downloadErr);
      return jsonResponse({ success: false, error: "Imagem não encontrada ou inacessível" }, 422);
    }

    if (bytes.size > MAX_IMAGE_BYTES) {
      return jsonResponse({ success: false, error: "Imagem muito grande. Máximo: 2 MB." }, 422);
    }

    const arr = new Uint8Array(bytes.size);
    arr.set(new Uint8Array(await bytes.arrayBuffer()));
    let outStr = "";
    for (let j = 0; j < arr.length; j++) outStr += String.fromCharCode(arr[j]);
    const imageBase64 = btoa(outStr);
    const mime = "image/jpeg";

    const taskId = crypto.randomUUID();
    const fileSizeBytes = bytes.size;

    let editId: string;
    let reservationId = "";
    try {
      const result = await createEditAndReserveCredits(
        supabase,
        userId,
        "remove_background",
        7,
        "remove_background",
        taskId,
        {
          imageMetadata: {
            file_size: fileSizeBytes,
            mime_type: mime,
          },
          promptTextOriginal: "remove_background",
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
        .from(BUCKET_NAME)
        .upload(originalPath, await bytes.arrayBuffer(), {
          contentType: mime,
          upsert: true,
        });
      if (!uploadOriginalErr) {
        const { data: urlData } = supabase.storage.from(BUCKET_NAME).getPublicUrl(originalPath);
        await supabase.from("edits").update({ original_image_url: urlData.publicUrl }).eq("id", editId);
      } else {
        console.warn("[remover-fundo-flux] Falha ao persistir original (continuando):", uploadOriginalErr);
      }
    } catch (origErr) {
      console.warn("[remover-fundo-flux] Erro ao persistir original (continuando):", origErr);
    }

    const imageUrl = `data:${mime};base64,${imageBase64}`;

    const { error: insertError } = await supabase.from("flux_tasks").insert({
      task_id: taskId,
      user_id: userId,
      edit_id: editId,
      status: "pending",
    });

    if (insertError) {
      console.error("[remover-fundo-flux] Erro ao inserir flux_tasks:", insertError);
      await releaseReservedCredits(supabase, reservationId, "flux_task_insert_error");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse(
        { success: false, error: "Falha ao registrar tarefa" },
        500
      );
    }

    const startMs = Date.now();
    const falRes = await fetch(FAL_API_URL, {
      method: "POST",
      headers: {
        "Authorization": `Key ${falKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        image_url: imageUrl,
        output_format: "png",
      }),
    });

    const falData = (await falRes.json()) as FalBirefnetResponse;

    if (!falRes.ok) {
      const falDetail = typeof falData?.detail === "string" ? falData.detail : JSON.stringify(falData);
      const errMsg =
        falRes.status === 401
          ? "Token fal.ai invÃ¡lido. Verifique FAL_KEY nas secrets do Supabase."
          : falRes.status === 403
          ? `fal.ai: ${falDetail || "Verifique crÃ©ditos em fal.ai/dashboard e scopes da chave em fal.ai/dashboard/keys."}`
          : falDetail || `Erro na API fal.ai: ${falRes.status}`;
      console.error("[remover-fundo-flux] fal.ai error:", falRes.status, "body:", falDetail);
      await releaseReservedCredits(supabase, reservationId, "fal_api_error");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      await supabase
        .from("flux_tasks")
        .update({
          status: "error",
          error_message: errMsg,
          updated_at: new Date().toISOString(),
        })
        .eq("task_id", taskId);
      return jsonResponse(
        { success: false, error: errMsg },
        falRes.status >= 500 ? 502 : falRes.status
      );
    }

    const outputUrl = falData?.image?.url;
    if (!outputUrl || typeof outputUrl !== "string") {
      console.error("[remover-fundo-flux] Output inesperado:", JSON.stringify(falData));
      const errMsg = "Resultado invÃ¡lido da API fal.ai";
      await releaseReservedCredits(supabase, reservationId, "invalid_fal_output");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      await supabase
        .from("flux_tasks")
        .update({
          status: "error",
          error_message: errMsg,
          updated_at: new Date().toISOString(),
        })
        .eq("task_id", taskId);
      return jsonResponse({ success: false, error: errMsg }, 502);
    }

    const imgRes = await fetch(outputUrl, {
      headers: { "User-Agent": "Supabase-Edge-Function/1.0" },
    });
    if (!imgRes.ok) {
      const errMsg = "Falha ao obter imagem gerada";
      console.error("[remover-fundo-flux] Erro ao baixar PNG:", imgRes.status);
      await releaseReservedCredits(supabase, reservationId, "download_generated_error");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      await supabase
        .from("flux_tasks")
        .update({
          status: "error",
          error_message: errMsg,
          updated_at: new Date().toISOString(),
        })
        .eq("task_id", taskId);
      return jsonResponse({ success: false, error: errMsg }, 502);
    }

    const imgBytes = await imgRes.arrayBuffer();
    const timestamp = Math.floor(Date.now() / 1000);
    const fileName = `default/${timestamp}_${taskId}.png`;

    const { error: uploadError } = await supabase.storage
      .from(BUCKET_NAME)
      .upload(fileName, imgBytes, {
        contentType: "image/png",
        upsert: true,
      });

    if (uploadError) {
      const uploadErrMsg = uploadError.message || JSON.stringify(uploadError);
      console.error("[remover-fundo-flux] Erro upload:", uploadError);
      await releaseReservedCredits(supabase, reservationId, "storage_upload_error");
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      await supabase
        .from("flux_tasks")
        .update({
          status: "error",
          error_message: `Falha ao salvar imagem: ${uploadErrMsg}`,
          updated_at: new Date().toISOString(),
        })
        .eq("task_id", taskId);
      return jsonResponse(
        { success: false, error: `Falha ao salvar imagem: ${uploadErrMsg}` },
        500
      );
    }

    const { data: urlData } = supabase.storage.from(BUCKET_NAME).getPublicUrl(fileName);

    await supabase
      .from("flux_tasks")
      .update({
        status: "ready",
        image_url: urlData.publicUrl,
        updated_at: new Date().toISOString(),
      })
      .eq("task_id", taskId);

    const aiProcessingTimeMs = Math.max(0, Date.now() - startMs);
    await supabase
      .from("edits")
      .update({
        status: "completed",
        image_url: urlData.publicUrl,
        ai_processing_time_ms: aiProcessingTimeMs,
      })
      .eq("id", editId);

    try {
      await consumeReservedCredits(supabase, reservationId, editId, "usage");
    } catch (consumeErr) {
      console.error("[remover-fundo-flux] Erro ao consumir reserva:", consumeErr);
      await releaseReservedCredits(supabase, reservationId, "consume_failed");
      await supabase
        .from("flux_tasks")
        .update({
          status: "error",
          error_message: "Falha ao consumir crÃ©ditos",
          updated_at: new Date().toISOString(),
        })
        .eq("task_id", taskId);
      await supabase.from("edits").update({ status: "failed" }).eq("id", editId);
      return jsonResponse(
        { success: false, error: "Falha ao consumir crÃ©ditos" },
        500,
      );
    }

    return jsonResponse({ task_id: taskId });
  } catch (error) {
    const errMsg = error instanceof Error ? error.message : String(error);
    const errStack = error instanceof Error ? error.stack : undefined;
    console.error("[remover-fundo-flux] Erro:", errMsg, errStack);
    return jsonResponse(
      {
        success: false,
        error: errMsg || "Erro interno",
      },
      500
    );
  }
});
