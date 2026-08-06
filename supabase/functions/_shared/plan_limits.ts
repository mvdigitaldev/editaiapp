import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export interface PhotoStorageStatus {
  ok: boolean;
  maxPhotos: number;
  storedCount: number;
  pendingCount: number;
}

/**
 * Returns photo expiration days from the current user plan.
 */
export async function getExpirationDays(
  supabase: SupabaseClient,
  userId: string,
): Promise<number> {
  const { data } = await supabase
    .rpc("get_plan_photo_limits", { p_user_id: userId })
    .single();
  return data?.expiration_days ?? 15;
}

/**
 * Checks unified storage quota (max_stored_photos) for the user.
 *
 * Pass `countPending` on flows that only produce the photo later (IA), so the
 * queued jobs already count against the quota.
 */
export async function getPhotoStorageStatus(
  supabase: SupabaseClient,
  userId: string,
  options: { countPending?: boolean } = {},
): Promise<PhotoStorageStatus> {
  const { data: planLimits } = await supabase
    .rpc("get_plan_photo_limits", { p_user_id: userId })
    .single();
  const maxPhotos = planLimits?.max_photos ?? 10;
  const now = new Date().toISOString();

  const { count: completedCount } = await supabase
    .from("edits")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("status", "completed")
    .not("image_url", "is", null)
    .or(`expires_at.is.null,expires_at.gt.${now}`);

  let pendingCount = 0;
  if (options.countPending) {
    const { count } = await supabase
      .from("edits")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .in("status", ["queued", "processing"]);
    pendingCount = count ?? 0;
  }

  const storedCount = completedCount ?? 0;
  return {
    ok: storedCount + pendingCount < maxPhotos,
    maxPhotos,
    storedCount,
    pendingCount,
  };
}

/**
 * Standard 403 body for a rejected save. `stored_photos_count` includes queued
 * jobs so the number matches what the user sees as "in use".
 *
 * Nada é apagado automaticamente: o usuário só precisa excluir fotos na
 * galeria para liberar espaço.
 */
export function storageLimitPayload(status: PhotoStorageStatus) {
  const used = status.storedCount + status.pendingCount;
  return {
    success: false,
    error:
      `Armazenamento cheio (${used}/${status.maxPhotos} fotos). ` +
      "Exclua fotos na galeria para salvar novas.",
    code: "storage_limit_reached",
    max_photos: status.maxPhotos,
    stored_photos_count: used,
  };
}
