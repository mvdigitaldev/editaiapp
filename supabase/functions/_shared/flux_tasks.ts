import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

interface RegisterFluxTaskParams {
  taskId: string;
  userId: string;
  editId: string;
  provider?: "bfl" | "fal";
  pollingUrl?: string | null;
}

export async function registerFluxTask(
  supabase: SupabaseClient,
  { taskId, userId, editId, provider = "bfl", pollingUrl = null }: RegisterFluxTaskParams,
): Promise<void> {
  const { error: taskError } = await supabase.from("flux_tasks").upsert(
    {
      task_id: taskId,
      user_id: userId,
      edit_id: editId,
      provider,
      polling_url: pollingUrl,
      status: "pending",
    },
    { onConflict: "task_id" },
  );

  if (taskError) {
    throw new Error(`flux_tasks_insert_failed:${taskError.message}`);
  }

  const { error: editError } = await supabase
    .from("edits")
    .update({ task_id: taskId })
    .eq("id", editId);

  if (editError) {
    throw new Error(`edits_task_id_update_failed:${editError.message}`);
  }
}

interface EditTaskLookup {
  id: string;
  user_id: string;
  task_id: string;
  status: string;
  image_url: string | null;
}

export async function getEditByTaskId(
  supabase: SupabaseClient,
  taskId: string,
): Promise<EditTaskLookup | null> {
  const { data, error } = await supabase
    .from("edits")
    .select("id, user_id, task_id, status, image_url")
    .eq("task_id", taskId)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  return (data as EditTaskLookup | null) ?? null;
}
