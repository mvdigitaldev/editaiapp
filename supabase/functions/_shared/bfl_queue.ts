import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const BFL_OPERATION_TYPES = [
  "text_to_image",
  "edit_image",
  "edit_model",
  "multi_image",
] as const;

export const MAX_BFL_ACTIVE_TASKS = 20;
export const MAX_BFL_JOBS_PER_USER = 5;
export const BFL_USER_LIMIT_WINDOW_HOURS = 1;
export const BFL_QUEUE_TIMEOUT_MS = 45 * 60 * 1000;
export const BFL_INIT_BATCH_SIZE = 20;
export const BFL_INIT_MAX_READ_COUNT = 5;
export const BFL_INIT_WORKER_LEASE_NAME = "bfl-init-worker";
export const BFL_INIT_WORKER_LEASE_TTL_SECONDS = 150;

export interface BflInitJobPayload {
  edit_id: string;
  user_id: string;
  reservation_id: string;
  operation_type: string;
  prompt_text: string;
  storage_paths: string[];
  width: number;
  height: number;
  enqueued_at: string;
}

export async function enforceBflUserJobLimit(
  supabase: SupabaseClient,
  userId: string,
): Promise<void> {
  const since = new Date(
    Date.now() - BFL_USER_LIMIT_WINDOW_HOURS * 60 * 60 * 1000,
  ).toISOString();

  const { count, error } = await supabase
    .from("edits")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .in("operation_type", [...BFL_OPERATION_TYPES])
    .in("status", ["queued", "processing"])
    .gte("created_at", since);

  if (error) {
    throw new Error(error.message);
  }

  if ((count ?? 0) >= MAX_BFL_JOBS_PER_USER) {
    const err = new Error(
      `MÃ¡ximo de ${MAX_BFL_JOBS_PER_USER} jobs simultÃ¢neos. Aguarde a conclusÃ£o de algum antes de enviar outro.`,
    ) as Error & { status?: number };
    err.status = 429;
    throw err;
  }
}

export async function enqueueBflInitJob(
  supabase: SupabaseClient,
  payload: BflInitJobPayload,
): Promise<void> {
  const { error } = await supabase.rpc("enqueue_bfl_init_job", {
    p_msg: payload,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export async function getActiveBflTaskCount(
  supabase: SupabaseClient,
): Promise<number> {
  const { count, error } = await supabase
    .from("flux_tasks")
    .select("task_id", { count: "exact", head: true })
    .eq("provider", "bfl")
    .in("status", ["pending", "finalizing"]);

  if (error) {
    throw new Error(error.message);
  }

  return count ?? 0;
}

export async function tryAcquireWorkerLease(
  supabase: SupabaseClient,
  leaseName: string,
  holderId: string,
  ttlSeconds = BFL_INIT_WORKER_LEASE_TTL_SECONDS,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("try_acquire_worker_lease", {
    p_lease_name: leaseName,
    p_holder_id: holderId,
    p_ttl_seconds: ttlSeconds,
  });

  if (error) {
    throw new Error(error.message);
  }

  return data === true;
}

export async function renewWorkerLease(
  supabase: SupabaseClient,
  leaseName: string,
  holderId: string,
  ttlSeconds = BFL_INIT_WORKER_LEASE_TTL_SECONDS,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("renew_worker_lease", {
    p_lease_name: leaseName,
    p_holder_id: holderId,
    p_ttl_seconds: ttlSeconds,
  });

  if (error) {
    throw new Error(error.message);
  }

  return data === true;
}

export async function releaseWorkerLease(
  supabase: SupabaseClient,
  leaseName: string,
  holderId: string,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("release_worker_lease", {
    p_lease_name: leaseName,
    p_holder_id: holderId,
  });

  if (error) {
    throw new Error(error.message);
  }

  return data === true;
}
