import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export interface EditImageMetadata {
  file_size?: number;
  mime_type?: string;
  width?: number;
  height?: number;
}

export async function deductAndCreateEdit(
  supabase: SupabaseClient,
  userId: string,
  operationType: string,
  credits: number,
  promptText: string,
  taskId: string | null,
  options?: { imageId?: string | null; imageMetadata?: EditImageMetadata }
): Promise<{ editId: string }> {
  let metadata: EditImageMetadata | undefined = options?.imageMetadata;

  if (options?.imageId && !metadata) {
    const { data: img } = await supabase
      .from("images")
      .select("file_size, mime_type, width, height")
      .eq("id", options.imageId)
      .single();
    if (img) {
      metadata = {
        file_size: img.file_size ?? undefined,
        mime_type: img.mime_type ?? undefined,
        width: img.width ?? undefined,
        height: img.height ?? undefined,
      };
    }
  }

  const insertPayload: Record<string, unknown> = {
    user_id: userId,
    image_id: options?.imageId ?? null,
    prompt_text: promptText,
    operation_type: operationType,
    task_id: taskId,
    status: "queued",
    credits_used: credits,
  };
  if (metadata?.file_size != null) insertPayload.file_size = metadata.file_size;
  if (metadata?.mime_type) insertPayload.mime_type = metadata.mime_type;
  if (metadata?.width != null) insertPayload.width = metadata.width;
  if (metadata?.height != null) insertPayload.height = metadata.height;

  const { data: edit, error: editErr } = await supabase
    .from("edits")
    .insert(insertPayload as Record<string, unknown>)
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
