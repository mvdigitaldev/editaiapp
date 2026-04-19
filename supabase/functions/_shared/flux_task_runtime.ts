import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  consumeReservedCreditsForEdit,
  releaseReservedCreditsForEdit,
} from "./credits.ts";
import { getEditByTaskId } from "./flux_tasks.ts";

const BUCKET_NAME = "flux-imagens";

export interface FluxTaskRow {
  task_id: string;
  edit_id: string | null;
  user_id: string | null;
  provider: string | null;
  status: string;
  image_url: string | null;
  polling_url: string | null;
  error_message: string | null;
  last_provider_status: string | null;
  last_polled_at: string | null;
  poll_attempt_count: number | null;
  created_at: string;
  updated_at: string;
}

export async function getTaskRecord(
  supabase: SupabaseClient,
  taskId: string,
): Promise<FluxTaskRow | null> {
  const { data, error } = await supabase
    .from("flux_tasks")
    .select([
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
    ].join(", "))
    .eq("task_id", taskId)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  return (data as FluxTaskRow | null) ?? null;
}

export async function findOrReconcileTaskRecord(
  supabase: SupabaseClient,
  taskId: string,
): Promise<FluxTaskRow | null> {
  const currentTask = await getTaskRecord(supabase, taskId);
  if (currentTask) return currentTask;

  const edit = await getEditByTaskId(supabase, taskId);
  if (!edit) return null;

  const fallbackStatus =
    edit.status === "completed"
      ? "ready"
      : edit.status === "failed"
      ? "error"
      : "pending";

  const { error: upsertError } = await supabase.from("flux_tasks").upsert(
    {
      task_id: taskId,
      user_id: edit.user_id,
      edit_id: edit.id,
      provider: "bfl",
      status: fallbackStatus,
      image_url: edit.image_url,
    },
    { onConflict: "task_id" },
  );

  if (upsertError) {
    console.warn("[flux-task-runtime] Falha ao reconciliar flux_tasks:", {
      taskId,
      editId: edit.id,
      error: upsertError.message,
    });
  } else {
    console.warn("[flux-task-runtime] flux_tasks reconciliada a partir de edits:", {
      taskId,
      editId: edit.id,
      status: fallbackStatus,
    });
  }

  return await getTaskRecord(supabase, taskId);
}

async function setEditProcessingIfNeeded(
  supabase: SupabaseClient,
  editId: string | null,
): Promise<void> {
  if (!editId) return;

  const { error } = await supabase
    .from("edits")
    .update({
      status: "processing",
      started_at: new Date().toISOString(),
    })
    .eq("id", editId)
    .eq("status", "queued");

  if (error) {
    console.warn("[flux-task-runtime] Falha ao mover edit para processing:", {
      editId,
      error: error.message,
    });
  }
}

export async function recordTaskHeartbeat(
  supabase: SupabaseClient,
  taskId: string,
  providerStatus: string,
  options?: {
    polled?: boolean;
    errorMessage?: string | null;
  },
): Promise<FluxTaskRow | null> {
  const task = await findOrReconcileTaskRecord(supabase, taskId);
  if (!task) return null;
  if (task.status === "ready" || task.status === "error") return task;

  const now = new Date().toISOString();
  const nextPollCount = options?.polled
    ? (task.poll_attempt_count ?? 0) + 1
    : task.poll_attempt_count ?? 0;
  const nextErrorMessage =
    options && Object.prototype.hasOwnProperty.call(options, "errorMessage")
      ? options.errorMessage ?? null
      : task.error_message;

  const { error } = await supabase
    .from("flux_tasks")
    .update({
      last_provider_status: providerStatus,
      last_polled_at: options?.polled ? now : task.last_polled_at,
      poll_attempt_count: nextPollCount,
      error_message: nextErrorMessage,
      updated_at: now,
    })
    .eq("task_id", taskId);

  if (error) {
    throw new Error(error.message);
  }

  const lower = providerStatus.trim().toLowerCase();
  if (lower && lower !== "ready" && lower !== "error" && lower !== "failed") {
    await setEditProcessingIfNeeded(supabase, task.edit_id);
  }

  return await getTaskRecord(supabase, taskId);
}

async function claimTaskForFinalization(
  supabase: SupabaseClient,
  taskId: string,
  providerStatus: string,
  polled: boolean,
): Promise<FluxTaskRow | null> {
  const now = new Date().toISOString();
  const currentTask = await findOrReconcileTaskRecord(supabase, taskId);
  if (!currentTask) return null;

  if (currentTask.status === "ready" && currentTask.image_url) {
    return null;
  }

  if (currentTask.status === "error") {
    return null;
  }

  const { data, error } = await supabase
    .from("flux_tasks")
    .update({
      status: "finalizing",
      last_provider_status: providerStatus,
      last_polled_at: polled ? now : currentTask.last_polled_at,
      poll_attempt_count: polled
        ? (currentTask.poll_attempt_count ?? 0) + 1
        : currentTask.poll_attempt_count ?? 0,
      updated_at: now,
    })
    .eq("task_id", taskId)
    .eq("status", "pending")
    .select([
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
    ].join(", "))
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  return (data as FluxTaskRow | null) ?? null;
}

export async function markTaskAsFailed(
  supabase: SupabaseClient,
  taskId: string,
  errorMessage: string,
  releaseReason: string,
  options?: {
    providerStatus?: string;
    polled?: boolean;
  },
): Promise<void> {
  const task = await findOrReconcileTaskRecord(supabase, taskId);
  if (!task) return;
  if (task.status === "ready" || task.status === "error") return;

  if (task.edit_id) {
    await releaseReservedCreditsForEdit(supabase, task.edit_id, releaseReason);
    await supabase
      .from("edits")
      .update({ status: "failed" })
      .eq("id", task.edit_id);
  }

  const now = new Date().toISOString();
  const nextPollCount = options?.polled
    ? (task.poll_attempt_count ?? 0) + 1
    : task.poll_attempt_count ?? 0;

  await supabase
    .from("flux_tasks")
    .update({
      status: "error",
      error_message: errorMessage,
      last_provider_status: options?.providerStatus ?? task.last_provider_status,
      last_polled_at: options?.polled ? now : task.last_polled_at,
      poll_attempt_count: nextPollCount,
      updated_at: now,
    })
    .eq("task_id", taskId);
}

async function markTaskAsReady(
  supabase: SupabaseClient,
  task: FluxTaskRow,
  imageUrl: string,
  options?: {
    providerStatus?: string;
    polled?: boolean;
  },
): Promise<void> {
  const now = new Date().toISOString();

  await supabase
    .from("flux_tasks")
    .update({
      status: "ready",
      image_url: imageUrl,
      last_provider_status: options?.providerStatus ?? task.last_provider_status,
      last_polled_at: options?.polled ? now : task.last_polled_at,
      poll_attempt_count: options?.polled
        ? (task.poll_attempt_count ?? 0) + 1
        : task.poll_attempt_count ?? 0,
      error_message: null,
      updated_at: now,
    })
    .eq("task_id", task.task_id);

  if (!task.edit_id) return;

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

export async function finalizeTaskFromSampleUrl(
  supabase: SupabaseClient,
  taskId: string,
  sampleUrl: string,
  options?: {
    providerStatus?: string;
    polled?: boolean;
  },
): Promise<void> {
  const task = await claimTaskForFinalization(
    supabase,
    taskId,
    options?.providerStatus ?? "Ready",
    options?.polled ?? false,
  );

  if (!task) return;

  const imgRes = await fetch(sampleUrl);
  if (!imgRes.ok) {
    await markTaskAsFailed(
      supabase,
      taskId,
      "Falha ao obter imagem gerada",
      "provider_image_download_failed",
      options,
    );
    return;
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
    await markTaskAsFailed(
      supabase,
      taskId,
      "Falha ao salvar imagem",
      "storage_upload_failed",
      options,
    );
    return;
  }

  const { data: urlData } = supabase.storage.from(BUCKET_NAME).getPublicUrl(fileName);
  const imageUrl = urlData.publicUrl;

  if (task.edit_id) {
    try {
      await consumeReservedCreditsForEdit(supabase, task.edit_id, "usage");
    } catch (_) {
      await markTaskAsFailed(
        supabase,
        taskId,
        "Falha ao consumir creditos",
        "consume_failed_on_ready",
        options,
      );
      return;
    }
  }

  await markTaskAsReady(supabase, task, imageUrl, options);
}
