import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import type { FluxTaskRow } from "../_shared/flux_task_runtime.ts";
import {
  finalizeTaskFromSampleUrl,
  markTaskAsFailed,
  recordTaskHeartbeat,
} from "../_shared/flux_task_runtime.ts";

const BATCH_SIZE = 10;
const MIN_POLL_INTERVAL_MS = 30 * 1000;
const MAX_PENDING_AGE_MS = 45 * 60 * 1000;
const FIRST_POLL_GRACE_MS = 20 * 1000;

const TASK_SELECT = [
  "task_id",
  "edit_id",
  "user_id",
  "provider",
  "status",
  "image_url",
  "polling_url",
  "error_message",
  "last_provider_status",
  "last_polled_at",
  "poll_attempt_count",
  "created_at",
  "updated_at",
].join(", ");

interface ProviderPollResponse {
  id?: string;
  status?: string;
  result?: { sample?: string };
  detail?: string;
  details?: string;
}

async function fetchPollableTasks(
  supabase: ReturnType<typeof createClient>,
): Promise<FluxTaskRow[]> {
  const pollCutoffIso = new Date(Date.now() - MIN_POLL_INTERVAL_MS).toISOString();
  const firstPollCutoffIso = new Date(Date.now() - FIRST_POLL_GRACE_MS).toISOString();

  const { data, error } = await supabase
    .from("flux_tasks")
    .select(TASK_SELECT)
    .eq("status", "pending")
    .eq("provider", "bfl")
    .not("polling_url", "is", null)
    .lte("created_at", firstPollCutoffIso)
    .or(`last_polled_at.is.null,last_polled_at.lte.${pollCutoffIso}`)
    .order("last_polled_at", { ascending: true, nullsFirst: true })
    .order("created_at", { ascending: true })
    .limit(BATCH_SIZE);

  if (error) {
    throw new Error(error.message);
  }

  return (data as FluxTaskRow[] | null) ?? [];
}

async function fetchStaleTasksWithoutPolling(
  supabase: ReturnType<typeof createClient>,
): Promise<FluxTaskRow[]> {
  const staleCutoffIso = new Date(Date.now() - MAX_PENDING_AGE_MS).toISOString();

  const { data, error } = await supabase
    .from("flux_tasks")
    .select(TASK_SELECT)
    .in("status", ["pending", "finalizing"])
    .lte("created_at", staleCutoffIso)
    .order("created_at", { ascending: true })
    .limit(BATCH_SIZE);

  if (error) {
    throw new Error(error.message);
  }

  const rows = (data as FluxTaskRow[] | null) ?? [];
  return rows.filter((row) =>
    row.status === "finalizing" || row.provider !== "bfl" || !row.polling_url
  );
}

function buildProviderErrorMessage(payload: ProviderPollResponse): string {
  if (typeof payload.detail === "string" && payload.detail.trim()) {
    return payload.detail.trim();
  }
  if (typeof payload.details === "string" && payload.details.trim()) {
    return payload.details.trim();
  }
  if (typeof payload.status === "string" && payload.status.trim()) {
    return `Provider status: ${payload.status.trim()}`;
  }
  return "Erro no provedor de imagem";
}

async function processPollableTask(
  supabase: ReturnType<typeof createClient>,
  task: FluxTaskRow,
  bflApiKey: string,
): Promise<void> {
  const ageMs = Date.now() - new Date(task.created_at).getTime();

  if (!task.polling_url) {
    if (ageMs > MAX_PENDING_AGE_MS) {
      await markTaskAsFailed(
        supabase,
        task.task_id,
        "Tempo limite excedido sem URL de polling",
        "missing_polling_url_timeout",
        { providerStatus: task.last_provider_status ?? "Timeout" },
      );
    }
    return;
  }

  try {
    const response = await fetch(task.polling_url, {
      method: "GET",
      headers: {
        "accept": "application/json",
        "x-key": bflApiKey,
      },
      signal: AbortSignal.timeout(15000),
    });

    if (!response.ok) {
      const pollError = `Polling HTTP ${response.status}`;
      if (ageMs > MAX_PENDING_AGE_MS) {
        await markTaskAsFailed(
          supabase,
          task.task_id,
          "Tempo limite excedido aguardando retorno do provedor",
          "provider_timeout",
          {
            providerStatus: task.last_provider_status ?? "Timeout",
            polled: true,
          },
        );
        return;
      }

      await recordTaskHeartbeat(supabase, task.task_id, task.last_provider_status ?? "Polling", {
        polled: true,
        errorMessage: pollError,
      });
      return;
    }

    const payload = (await response.json()) as ProviderPollResponse;
    const providerStatus =
      typeof payload.status === "string" && payload.status.trim().length > 0
        ? payload.status.trim()
        : "unknown";
    const statusLower = providerStatus.toLowerCase();

    if (statusLower === "ready") {
      const sampleUrl = payload.result?.sample;
      if (!sampleUrl || typeof sampleUrl !== "string") {
        await markTaskAsFailed(
          supabase,
          task.task_id,
          "Resultado invalido da API",
          "provider_invalid_payload",
          {
            providerStatus,
            polled: true,
          },
        );
        return;
      }

      await finalizeTaskFromSampleUrl(supabase, task.task_id, sampleUrl, {
        providerStatus,
        polled: true,
      });
      return;
    }

    if (
      statusLower === "error" ||
      statusLower === "failed" ||
      statusLower === "content moderated" ||
      statusLower === "request moderated"
    ) {
      await markTaskAsFailed(
        supabase,
        task.task_id,
        buildProviderErrorMessage(payload),
        "provider_error",
        {
          providerStatus,
          polled: true,
        },
      );
      return;
    }

    if (ageMs > MAX_PENDING_AGE_MS) {
      await markTaskAsFailed(
        supabase,
        task.task_id,
        "Tempo limite excedido aguardando retorno do provedor",
        "provider_timeout",
        {
          providerStatus,
          polled: true,
        },
      );
      return;
    }

    await recordTaskHeartbeat(supabase, task.task_id, providerStatus, {
      polled: true,
      errorMessage: null,
    });
  } catch (error) {
    if (ageMs > MAX_PENDING_AGE_MS) {
      await markTaskAsFailed(
        supabase,
        task.task_id,
        "Tempo limite excedido aguardando retorno do provedor",
        "provider_timeout",
        {
          providerStatus: task.last_provider_status ?? "Timeout",
          polled: true,
        },
      );
      return;
    }

    const errorMessage = error instanceof Error ? error.message : "Falha no polling";
    await recordTaskHeartbeat(
      supabase,
      task.task_id,
      task.last_provider_status ?? "Polling",
      {
        polled: true,
        errorMessage,
      },
    );
  }
}

async function selfInvokeIfNeeded(
  supabaseUrl: string,
  processedCount: number,
): Promise<void> {
  if (processedCount < BATCH_SIZE) return;

  const invokeSecret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!invokeSecret) return;

  const workerUrl = `${supabaseUrl}/functions/v1/flux-task-reconciler`;
  fetch(workerUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${invokeSecret}`,
    },
    body: JSON.stringify({ source: "self_invoke" }),
  }).catch((error) => {
    console.warn("[flux-task-reconciler] Self-invoke failed:", error);
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(null, { status: 405 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const bflApiKey = Deno.env.get("BFL_API_KEY");
  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    const staleTasks = await fetchStaleTasksWithoutPolling(supabase);
    for (const task of staleTasks) {
      await markTaskAsFailed(
        supabase,
        task.task_id,
        "Tempo limite excedido aguardando processamento",
        "stale_pending_timeout",
        { providerStatus: task.last_provider_status ?? "Timeout" },
      );
    }

    let pollableTasks: FluxTaskRow[] = [];
    if (bflApiKey) {
      pollableTasks = await fetchPollableTasks(supabase);
      for (const task of pollableTasks) {
        await processPollableTask(supabase, task, bflApiKey);
      }
    } else {
      console.warn("[flux-task-reconciler] BFL_API_KEY ausente; polling ignorado.");
    }

    await selfInvokeIfNeeded(supabaseUrl, staleTasks.length + pollableTasks.length);

    return new Response(
      JSON.stringify({
        ok: true,
        stale_processed: staleTasks.length,
        poll_processed: pollableTasks.length,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("[flux-task-reconciler] Erro:", error);
    return new Response(
      JSON.stringify({
        ok: false,
        error: error instanceof Error ? error.message : "Erro interno",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
