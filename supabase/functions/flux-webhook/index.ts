import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  consumeReservedCreditsForEdit,
  releaseReservedCreditsForEdit,
} from "../_shared/credits.ts";

const BUCKET_NAME = "flux-imagens";

interface WebhookPayload {
  /** BFL polling/final; webhooks de progresso podem usar só `task_id` */
  id?: string;
  task_id?: string;
  status?: string;
  progress?: number;
  result?: { sample?: string };
}

function resolveFluxTaskId(payload: WebhookPayload): string | undefined {
  const fromId = typeof payload.id === "string" ? payload.id.trim() : "";
  if (fromId) return fromId;
  const fromTask = typeof payload.task_id === "string" ? payload.task_id.trim() : "";
  if (fromTask) return fromTask;
  return undefined;
}

interface FluxTaskRow {
  task_id: string;
  edit_id: string | null;
  user_id: string | null;
  status: string;
  image_url: string | null;
}

async function getTaskRecord(
  supabase: ReturnType<typeof createClient>,
  taskId: string,
): Promise<FluxTaskRow | null> {
  const { data, error } = await supabase
    .from("flux_tasks")
    .select("task_id, edit_id, user_id, status, image_url")
    .eq("task_id", taskId)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  return data as FluxTaskRow | null;
}

async function markTaskAsFailed(
  supabase: ReturnType<typeof createClient>,
  taskId: string,
  errorMessage: string,
  releaseReason: string,
) {
  const task = await getTaskRecord(supabase, taskId);
  if (!task) return;
  if (task.status === "ready") return;

  if (task.edit_id) {
    await releaseReservedCreditsForEdit(supabase, task.edit_id, releaseReason);
    await supabase
      .from("edits")
      .update({ status: "failed" })
      .eq("id", task.edit_id);
  }

  await supabase
    .from("flux_tasks")
    .update({
      status: "error",
      error_message: errorMessage,
      updated_at: new Date().toISOString(),
    })
    .eq("task_id", taskId);
}

async function markTaskAsReady(
  supabase: ReturnType<typeof createClient>,
  taskId: string,
  imageUrl: string,
) {
  await supabase
    .from("flux_tasks")
    .update({
      status: "ready",
      image_url: imageUrl,
      updated_at: new Date().toISOString(),
    })
    .eq("task_id", taskId);

  const task = await getTaskRecord(supabase, taskId);
  if (!task?.edit_id) return;

  const { data: edit } = await supabase
    .from("edits")
    .select("created_at, expires_at")
    .eq("id", task.edit_id)
    .single();

  const aiProcessingTimeMs =
    edit?.created_at
      ? Math.max(0, Math.round(Date.now() - new Date(edit.created_at).getTime()))
      : undefined;

  let expiresAt: string | undefined;
  if (edit?.expires_at == null && task.user_id) {
    const { data: limits } = await supabase
      .rpc("get_plan_photo_limits", { p_user_id: task.user_id })
      .single();
    const expirationDays = limits?.expiration_days ?? 15;
    const expDate = edit?.created_at
      ? new Date(edit.created_at)
      : new Date();
    expDate.setDate(expDate.getDate() + expirationDays);
    expiresAt = expDate.toISOString();
  }

  await supabase
    .from("edits")
    .update({
      status: "completed",
      image_url: imageUrl,
      ...(aiProcessingTimeMs != null && { ai_processing_time_ms: aiProcessingTimeMs }),
      ...(expiresAt != null && { expires_at: expiresAt }),
    })
    .eq("id", task.edit_id);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(null, { status: 405 });
  }

  try {
    const payload = (await req.json()) as WebhookPayload;
    const taskId = resolveFluxTaskId(payload);
    const { status, result } = payload;

    console.log("[flux-webhook] Recebido:", { taskId, status, hasResult: !!result?.sample });

    if (!taskId) {
      console.warn("[flux-webhook] Payload sem id nem task_id:", payload);
      return new Response(null, { status: 200 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const currentTask = await getTaskRecord(supabase, taskId);
    if (!currentTask) {
      console.warn("[flux-webhook] task_id nao encontrado:", taskId);
      return new Response(null, { status: 200 });
    }

    if (currentTask.status === "ready" && currentTask.image_url) {
      return new Response(null, { status: 200 });
    }

    const st = typeof status === "string" ? status.trim() : "";
    const stLower = st.toLowerCase();

    if (
      stLower === "error" ||
      stLower === "content moderated" ||
      stLower === "request moderated"
    ) {
      const errMsg = stLower === "content moderated" || stLower === "request moderated"
        ? "Conteudo moderado pela API"
        : "Erro na geracao da imagem";
      await markTaskAsFailed(supabase, taskId, errMsg, "provider_error");
      return new Response(null, { status: 200 });
    }

    if (stLower !== "ready") {
      return new Response(null, { status: 200 });
    }

    const sampleUrl = result?.sample;
    if (!sampleUrl || typeof sampleUrl !== "string") {
      console.error("[flux-webhook] Resultado sem sample:", payload);
      await markTaskAsFailed(
        supabase,
        taskId,
        "Resultado invalido da API",
        "provider_invalid_payload",
      );
      return new Response(null, { status: 200 });
    }

    const imgRes = await fetch(sampleUrl);
    if (!imgRes.ok) {
      console.error("[flux-webhook] Erro ao baixar imagem:", imgRes.status);
      await markTaskAsFailed(
        supabase,
        taskId,
        "Falha ao obter imagem gerada",
        "provider_image_download_failed",
      );
      return new Response(null, { status: 200 });
    }

    const imgBytes = await imgRes.arrayBuffer();
    const timestamp = Math.floor(Date.now() / 1000);
    const fileName = `default/${timestamp}_${taskId}.jpeg`;

    const { error: uploadError } = await supabase.storage
      .from(BUCKET_NAME)
      .upload(fileName, imgBytes, {
        contentType: "image/jpeg",
        upsert: true,
      });

    if (uploadError) {
      console.error("[flux-webhook] Erro upload:", uploadError);
      await markTaskAsFailed(
        supabase,
        taskId,
        "Falha ao salvar imagem",
        "storage_upload_failed",
      );
      return new Response(null, { status: 200 });
    }

    const { data: urlData } = supabase.storage.from(BUCKET_NAME).getPublicUrl(fileName);
    const imageUrl = urlData.publicUrl;

    if (currentTask.edit_id) {
      try {
        await consumeReservedCreditsForEdit(supabase, currentTask.edit_id, "usage");
      } catch (consumeError) {
        console.error("[flux-webhook] Falha ao consumir reserva:", consumeError);
        await markTaskAsFailed(
          supabase,
          taskId,
          "Falha ao consumir creditos",
          "consume_failed_on_ready",
        );
        return new Response(null, { status: 200 });
      }
    }

    await markTaskAsReady(supabase, taskId, imageUrl);
    return new Response(null, { status: 200 });
  } catch (error) {
    console.error("[flux-webhook] Erro:", error);
    return new Response(null, { status: 500 });
  }
});
