import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  finalizeTaskFromSampleUrl,
  findOrReconcileTaskRecord,
  markTaskAsFailed,
  recordTaskHeartbeat,
} from "../_shared/flux_task_runtime.ts";

interface WebhookPayload {
  id?: string;
  task_id?: string;
  status?: string;
  progress?: number;
  polling_url?: string;
  result?: { sample?: string };
}

function resolveFluxTaskId(payload: WebhookPayload): string | undefined {
  const fromId = typeof payload.id === "string" ? payload.id.trim() : "";
  if (fromId) return fromId;
  const fromTask = typeof payload.task_id === "string" ? payload.task_id.trim() : "";
  if (fromTask) return fromTask;
  return undefined;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(null, { status: 405 });
  }

  try {
    const payload = (await req.json()) as WebhookPayload;
    const taskId = resolveFluxTaskId(payload);
    const { status, result } = payload;
    const pollingUrl =
      typeof payload.polling_url === "string" && payload.polling_url.trim().length > 0
        ? payload.polling_url.trim()
        : null;

    console.log("[flux-webhook] Recebido:", {
      taskId,
      status,
      hasResult: !!result?.sample,
    });

    if (!taskId) {
      console.warn("[flux-webhook] Payload sem id nem task_id:", payload);
      return new Response(null, { status: 200 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const currentTask = await findOrReconcileTaskRecord(supabase, taskId);
    if (!currentTask) {
      console.warn("[flux-webhook] task_id nao encontrado em flux_tasks nem edits:", taskId);
      return new Response(null, { status: 200 });
    }

    if (pollingUrl && !currentTask.polling_url) {
      const { error: pollingUpdateError } = await supabase
        .from("flux_tasks")
        .update({ polling_url: pollingUrl })
        .eq("task_id", taskId);

      if (pollingUpdateError) {
        console.warn("[flux-webhook] Falha ao backfill de polling_url:", {
          taskId,
          error: pollingUpdateError.message,
        });
      }
    }

    if (currentTask.status === "ready" && currentTask.image_url) {
      return new Response(null, { status: 200 });
    }

    const st = typeof status === "string" ? status.trim() : "";
    const stLower = st.toLowerCase();

    if (
      stLower === "error" ||
      stLower === "failed" ||
      stLower === "content moderated" ||
      stLower === "request moderated"
    ) {
      const errMsg = stLower === "content moderated" || stLower === "request moderated"
        ? "Conteudo moderado pela API"
        : "Erro na geracao da imagem";
      await markTaskAsFailed(supabase, taskId, errMsg, "provider_error", {
        providerStatus: st || "Error",
      });
      return new Response(null, { status: 200 });
    }

    if (stLower !== "ready") {
      await recordTaskHeartbeat(supabase, taskId, st || "processing");
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
        { providerStatus: st || "Ready" },
      );
      return new Response(null, { status: 200 });
    }

    await finalizeTaskFromSampleUrl(supabase, taskId, sampleUrl, {
      providerStatus: st || "Ready",
    });
    return new Response(null, { status: 200 });
  } catch (error) {
    console.error("[flux-webhook] Erro:", error);
    return new Response(null, { status: 500 });
  }
});
