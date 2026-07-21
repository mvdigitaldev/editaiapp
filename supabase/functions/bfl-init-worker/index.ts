import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  BFL_INIT_BATCH_SIZE,
  BFL_INIT_MAX_READ_COUNT,
  BFL_INIT_WORKER_LEASE_NAME,
  BFL_INIT_WORKER_LEASE_TTL_SECONDS,
  BFL_QUEUE_TIMEOUT_MS,
  type BflInitJobPayload,
  getActiveBflTaskCount,
  MAX_BFL_ACTIVE_TASKS,
  releaseWorkerLease,
  renewWorkerLease,
  tryAcquireWorkerLease,
} from "../_shared/bfl_queue.ts";
import { releaseReservedCredits } from "../_shared/credits.ts";
import { processFluxEditJob } from "../_shared/flux_edit_processor.ts";
import { registerFluxTask } from "../_shared/flux_tasks.ts";

const BFL_API_URL = "https://api.bfl.ai/v1/flux-2-pro";
const EDIT_INPUTS_BUCKET = "edit-inputs";
const RETRY_STATUSES = [429, 500, 502, 503];
const MAX_SINGLE_IMAGE_BYTES = 2 * 1024 * 1024;

interface QueueMessageRow {
  msg_id: number;
  read_ct: number;
  message: BflInitJobPayload;
}

interface AsyncWebhookResponse {
  id?: string;
  polling_url?: string;
}

async function selfInvokeIfNeeded(
  supabase: ReturnType<typeof createClient>,
  supabaseUrl: string,
  processedCount: number,
  capacityStops: number,
): Promise<void> {
  if (capacityStops > 0 || processedCount < BFL_INIT_BATCH_SIZE) {
    return;
  }

  const { data: metrics, error } = await supabase.rpc("bfl_init_queue_metrics");
  if (error) {
    console.warn("[bfl-init-worker] Falha ao ler métricas da fila:", error);
    return;
  }

  const queueLength = Array.isArray(metrics) && metrics[0]
    ? Number((metrics[0] as { queue_length?: number }).queue_length ?? 0)
    : 0;
  if (queueLength <= 0) {
    return;
  }

  const invokeSecret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!invokeSecret) {
    return;
  }

  const workerUrl = `${supabaseUrl}/functions/v1/bfl-init-worker`;
  fetch(workerUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${invokeSecret}`,
    },
    body: JSON.stringify({ source: "self_invoke" }),
  }).catch((error) => {
    console.warn("[bfl-init-worker] Self-invoke failed:", error);
  });
}

async function fetchWithRetry(
  url: string,
  options: RequestInit,
  maxAttempts = 3,
  baseDelayMs = 1000,
): Promise<Response> {
  let lastResponse: Response | null = null;

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const response = await fetch(url, options);
    lastResponse = response;

    if (response.ok || !RETRY_STATUSES.includes(response.status)) {
      return response;
    }

    if (attempt < maxAttempts - 1) {
      const jitter = Math.floor(Math.random() * 250);
      const delay = baseDelayMs * Math.pow(2, attempt) + jitter;
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  if (lastResponse) {
    return lastResponse;
  }

  throw new Error(`Failed after ${maxAttempts} attempts`);
}

async function failEdit(
  supabase: ReturnType<typeof createClient>,
  payload: BflInitJobPayload,
  reason: string,
  errorMessage: string,
): Promise<void> {
  await releaseReservedCredits(supabase, payload.reservation_id, reason);
  await supabase
    .from("edits")
    .update({ status: "failed" })
    .eq("id", payload.edit_id);
  console.error("[bfl-init-worker] Job failed:", {
    editId: payload.edit_id,
    operationType: payload.operation_type,
    reason,
    errorMessage,
  });
}

async function downloadAndEncodeImages(
  supabase: ReturnType<typeof createClient>,
  storagePaths: string[],
): Promise<string[]> {
  const encodedImages: string[] = [];

  for (const path of storagePaths) {
    const { data: bytes, error } = await supabase.storage
      .from(EDIT_INPUTS_BUCKET)
      .download(path);

    if (error || !bytes) {
      throw new Error(`storage_download_error:${path}`);
    }

    if (bytes.size > MAX_SINGLE_IMAGE_BYTES) {
      throw new Error(`payload_too_large:${path}`);
    }

    const array = new Uint8Array(bytes.size);
    array.set(new Uint8Array(await bytes.arrayBuffer()));
    let out = "";
    for (let i = 0; i < array.length; i++) out += String.fromCharCode(array[i]);
    encodedImages.push(btoa(out));
  }

  return encodedImages;
}

async function processGenericBflJob(
  supabase: ReturnType<typeof createClient>,
  payload: BflInitJobPayload,
): Promise<{ taskId: string } | { error: string }> {
  const bflApiKey = Deno.env.get("BFL_API_KEY");
  if (!bflApiKey) {
    return { error: "ConfiguraÃ§Ã£o indisponÃ­vel" };
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const webhookUrl = `${supabaseUrl}/functions/v1/flux-webhook`;
  const body: Record<string, unknown> = {
    prompt: payload.prompt_text,
    width: payload.width,
    height: payload.height,
    output_format: "jpeg" as const,
    webhook_url: webhookUrl,
  };

  if (payload.storage_paths.length > 0) {
    const encodedImages = await downloadAndEncodeImages(supabase, payload.storage_paths);
    encodedImages.forEach((base64, index) => {
      body[index === 0 ? "input_image" : `input_image_${index + 1}`] = base64;
    });
  }

  const initRes = await fetchWithRetry(
    BFL_API_URL,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "x-key": bflApiKey,
      },
      body: JSON.stringify(body),
    },
    3,
    2000,
  );

  if (!initRes.ok) {
    const errText = await initRes.text();
    return { error: errText || `Erro BFL: ${initRes.status}` };
  }

  const rawResponseText = await initRes.text();
  console.log("[bfl-init-worker] BFL init raw response:", {
    editId: payload.edit_id,
    httpStatus: initRes.status,
    body: rawResponseText,
  });

  let initData: AsyncWebhookResponse;
  try {
    initData = JSON.parse(rawResponseText) as AsyncWebhookResponse;
  } catch (error) {
    return {
      error: error instanceof Error
        ? `Resposta BFL invalida: ${error.message}`
        : "Resposta BFL invalida",
    };
  }
  const taskId = initData.id;
  const pollingUrl =
    typeof initData.polling_url === "string" && initData.polling_url.trim().length > 0
      ? initData.polling_url.trim()
      : null;

  console.log("[bfl-init-worker] BFL init response:", {
    editId: payload.edit_id,
    taskId: taskId ?? null,
    hasPollingUrl: !!pollingUrl,
    responseKeys: Object.keys(initData ?? {}),
  });

  if (!taskId) {
    return { error: "Resposta invÃ¡lida da API" };
  }

  try {
    await registerFluxTask(supabase, {
      taskId,
      userId: payload.user_id,
      editId: payload.edit_id,
      provider: "bfl",
      pollingUrl,
    });
  } catch (error) {
    return {
      error: error instanceof Error ? error.message : "Falha ao registrar tarefa",
    };
  }

  return { taskId };
}

async function shouldFailQueuedJob(
  editCreatedAt: string | null,
  editStartedAt: string | null,
): Promise<boolean> {
  const reference = editStartedAt ?? editCreatedAt;
  if (!reference) return false;
  return Date.now() - new Date(reference).getTime() > BFL_QUEUE_TIMEOUT_MS;
}

async function processMessage(
  supabase: ReturnType<typeof createClient>,
  row: QueueMessageRow,
): Promise<"deleted" | "deferred" | "capacity_full"> {
  const payload = row.message;

  if (row.read_ct > BFL_INIT_MAX_READ_COUNT) {
    await failEdit(
      supabase,
      payload,
      "bfl_init_max_retries",
      "Numero maximo de tentativas do worker excedido",
    );
    await supabase.rpc("archive_bfl_init_message", { p_msg_id: row.msg_id });
    return "deleted";
  }

  const { data: edit, error: editError } = await supabase
    .from("edits")
    .select("id, status, started_at, created_at, task_id")
    .eq("id", payload.edit_id)
    .maybeSingle();

  if (editError) {
    console.error("[bfl-init-worker] Erro ao buscar edit:", editError);
    return "deferred";
  }

  if (!edit) {
    await supabase.rpc("delete_bfl_init_message", { p_msg_id: row.msg_id });
    return "deleted";
  }

  const status = String(edit.status ?? "");
  const startedAt = typeof edit.started_at === "string" ? edit.started_at : null;
  const createdAt = typeof edit.created_at === "string" ? edit.created_at : null;
  const existingTaskId = typeof edit.task_id === "string" ? edit.task_id : null;

  if (status === "completed" || status === "failed" || (existingTaskId && existingTaskId.length > 0)) {
    await supabase.rpc("delete_bfl_init_message", { p_msg_id: row.msg_id });
    return "deleted";
  }

  if (status === "processing") {
    if (await shouldFailQueuedJob(createdAt, startedAt)) {
      await failEdit(
        supabase,
        payload,
        "init_worker_stale_processing",
        "Tempo limite excedido antes de registrar task remota",
      );
      await supabase.rpc("delete_bfl_init_message", { p_msg_id: row.msg_id });
      return "deleted";
    }
    return "deferred";
  }

  if (status !== "queued") {
    await supabase.rpc("delete_bfl_init_message", { p_msg_id: row.msg_id });
    return "deleted";
  }

  if (await shouldFailQueuedJob(createdAt, startedAt)) {
    await failEdit(
      supabase,
      payload,
      "init_worker_queue_timeout",
      "Tempo limite excedido aguardando capacidade",
    );
    await supabase.rpc("delete_bfl_init_message", { p_msg_id: row.msg_id });
    return "deleted";
  }

  const activeTasks = await getActiveBflTaskCount(supabase);
  if (activeTasks >= MAX_BFL_ACTIVE_TASKS) {
    console.warn("[bfl-init-worker] Capacidade BFL esgotada:", {
      activeTasks,
      limit: MAX_BFL_ACTIVE_TASKS,
      editId: payload.edit_id,
    });
    return "capacity_full";
  }

  const { data: claimed } = await supabase
    .from("edits")
    .update({
      status: "processing",
      started_at: new Date().toISOString(),
    })
    .eq("id", payload.edit_id)
    .eq("status", "queued")
    .select("id")
    .maybeSingle();

  if (!claimed) {
    return "deferred";
  }

  let result: { taskId: string } | { error: string };
  try {
    result = payload.operation_type === "multi_image"
      ? await processFluxEditJob(supabase, {
        edit_id: payload.edit_id,
        user_id: payload.user_id,
        reservation_id: payload.reservation_id,
        storage_paths: payload.storage_paths,
        user_prompt: payload.prompt_text,
        width: payload.width,
        height: payload.height,
        operation_type: payload.operation_type,
      })
      : await processGenericBflJob(supabase, payload);
  } catch (error) {
    result = {
      error: error instanceof Error ? error.message : "Erro ao iniciar task BFL",
    };
  }

  if ("error" in result) {
    await failEdit(supabase, payload, "bfl_init_error", result.error);
    await supabase.rpc("delete_bfl_init_message", { p_msg_id: row.msg_id });
    return "deleted";
  }

  await supabase.rpc("delete_bfl_init_message", { p_msg_id: row.msg_id });
  return "deleted";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(null, { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);
  const leaseHolderId = crypto.randomUUID();
  let acquiredLease = false;

  try {
    acquiredLease = await tryAcquireWorkerLease(
      supabase,
      BFL_INIT_WORKER_LEASE_NAME,
      leaseHolderId,
      BFL_INIT_WORKER_LEASE_TTL_SECONDS,
    );

    if (!acquiredLease) {
      return new Response(
        JSON.stringify({
          ok: true,
          processed: 0,
          deferred: 0,
          skipped: "lease_busy",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    let processed = 0;
    let deferred = 0;
    let capacityStops = 0;

    while (processed < BFL_INIT_BATCH_SIZE) {
      const renewed = await renewWorkerLease(
        supabase,
        BFL_INIT_WORKER_LEASE_NAME,
        leaseHolderId,
        BFL_INIT_WORKER_LEASE_TTL_SECONDS,
      );
      if (!renewed) {
        console.warn("[bfl-init-worker] Lease perdida; encerrando drain atual.");
        break;
      }

      const { data: rows, error: readError } = await supabase.rpc("read_bfl_init_job");

      if (readError) {
        console.error("[bfl-init-worker] Erro ao ler fila:", readError);
        return new Response(
          JSON.stringify({ ok: false, error: readError.message }),
          { status: 500, headers: { "Content-Type": "application/json" } },
        );
      }

      const messages = Array.isArray(rows) ? rows : rows ? [rows] : [];
      if (messages.length === 0) break;

      const result = await processMessage(supabase, messages[0] as QueueMessageRow);
      if (result === "capacity_full") {
        capacityStops += 1;
        break;
      }
      if (result === "deferred") {
        deferred += 1;
        continue;
      }
      processed += 1;
    }

    await selfInvokeIfNeeded(supabase, supabaseUrl, processed, capacityStops);

    return new Response(
      JSON.stringify({
        ok: true,
        processed,
        deferred,
        capacity_stops: capacityStops,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("[bfl-init-worker] Erro:", error);
    return new Response(
      JSON.stringify({
        ok: false,
        error: error instanceof Error ? error.message : "Erro interno",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  } finally {
    if (acquiredLease) {
      try {
        await releaseWorkerLease(supabase, BFL_INIT_WORKER_LEASE_NAME, leaseHolderId);
      } catch (error) {
        console.warn("[bfl-init-worker] Falha ao liberar lease:", error);
      }
    }
  }
});
