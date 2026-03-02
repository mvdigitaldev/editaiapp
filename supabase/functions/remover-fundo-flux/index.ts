import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { deductAndCreateEdit, refundCredits } from "./credits.ts";

const FAL_API_URL = "https://fal.run/fal-ai/birefnet";
const BUCKET_NAME = "flux-imagens";
const MAX_BASE64_BYTES = 10 * 1024 * 1024; // 10 MB

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface RequestBody {
  image_base64: string;
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

function normalizeBase64(input: string): { base64: string; mime: string } {
  const trimmed = input.trim();
  const dataUrlMatch = trimmed.match(/^data:image\/(jpeg|png|webp);base64,(.+)$/i);
  if (dataUrlMatch) {
    return { base64: dataUrlMatch[2], mime: `image/${dataUrlMatch[1].toLowerCase()}` };
  }
  return { base64: trimmed, mime: "image/jpeg" };
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
    const { image_base64 } = body;

    if (!image_base64 || typeof image_base64 !== "string" || image_base64.trim().length === 0) {
      return jsonResponse(
        { success: false, error: "Campo 'image_base64' é obrigatório e não pode estar vazio" },
        422
      );
    }

    const falKey = Deno.env.get("FAL_KEY");
    if (!falKey) {
      console.error("[remover-fundo-flux] FAL_KEY não configurada");
      return jsonResponse(
        { success: false, error: "Configuração do serviço indisponível" },
        500
      );
    }

    const { base64: imageBase64, mime } = normalizeBase64(image_base64);
    if (imageBase64.length < 100) {
      return jsonResponse(
        { success: false, error: "Imagem inválida ou base64 corrompido" },
        422
      );
    }

    const base64Bytes = Math.ceil((imageBase64.length * 3) / 4);
    if (base64Bytes > MAX_BASE64_BYTES) {
      return jsonResponse(
        { success: false, error: "Imagem muito grande. Máximo: 10 MB." },
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

    const taskId = crypto.randomUUID();
    const fileSizeBytes = Math.ceil((imageBase64.length * 3) / 4);

    let editId: string;
    try {
      const result = await deductAndCreateEdit(
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
    } catch (creditErr) {
      const err = creditErr as Error & { status?: number };
      if (err.status === 402) {
        return jsonResponse({ success: false, error: "Créditos insuficientes" }, 402);
      }
      throw creditErr;
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
          ? "Token fal.ai inválido. Verifique FAL_KEY nas secrets do Supabase."
          : falRes.status === 403
          ? `fal.ai: ${falDetail || "Verifique créditos em fal.ai/dashboard e scopes da chave em fal.ai/dashboard/keys."}`
          : falDetail || `Erro na API fal.ai: ${falRes.status}`;
      console.error("[remover-fundo-flux] fal.ai error:", falRes.status, "body:", falDetail);
      await refundCredits(supabase, userId, 7, editId);
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
      const errMsg = "Resultado inválido da API fal.ai";
      await refundCredits(supabase, userId, 7, editId);
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
      await refundCredits(supabase, userId, 7, editId);
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
      await refundCredits(supabase, userId, 7, editId);
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
