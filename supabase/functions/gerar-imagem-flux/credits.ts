import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export async function deductAndCreateEdit(
  supabase: SupabaseClient,
  userId: string,
  operationType: string,
  credits: number,
  promptText: string,
  taskId: string | null
): Promise<{ editId: string }> {
  const { data: edit, error: editErr } = await supabase
    .from("edits")
    .insert({
      user_id: userId,
      image_id: null,
      prompt_text: promptText,
      operation_type: operationType,
      task_id: taskId,
      status: "queued",
      credits_used: credits,
    })
    .select("id")
    .single();

  if (editErr || !edit?.id) {
    throw new Error(editErr?.message ?? "Falha ao criar registro de edição");
  }

  const { error: deductErr } = await supabase.rpc("deduct_credits_for_operation", {
    p_user_id: userId,
    p_credits: credits,
    p_description: "usage",
    p_reference_id: edit.id,
  });

  if (deductErr) {
    await supabase.from("edits").delete().eq("id", edit.id);
    if (deductErr.message?.includes("insufficient_credits")) {
      const e = new Error("Créditos insuficientes") as Error & { status?: number };
      e.status = 402;
      throw e;
    }
    throw new Error(deductErr.message);
  }

  return { editId: edit.id };
}

export async function refundCredits(
  supabase: SupabaseClient,
  userId: string,
  credits: number,
  editId: string
): Promise<void> {
  await supabase.rpc("refund_credits_for_edit", {
    p_user_id: userId,
    p_credits: credits,
    p_edit_id: editId,
  });
}
