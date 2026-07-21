import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export type PhotoStorageStatus =
  | { ok: true; maxPhotos: number; storedCount: number }
  | { ok: false; maxPhotos: number; storedCount: number };

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
 */
export async function getPhotoStorageStatus(
  supabase: SupabaseClient,
  userId: string,
): Promise<PhotoStorageStatus> {
  const { data: planLimits } = await supabase
    .rpc("get_plan_photo_limits", { p_user_id: userId })
    .single();
  const maxPhotos = planLimits?.max_photos ?? 10;
  const now = new Date().toISOString();

  const { count } = await supabase
    .from("edits")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("status", "completed")
    .not("image_url", "is", null)
    .or(`expires_at.is.null,expires_at.gt.${now}`);

  const storedCount = count ?? 0;
  if (storedCount >= maxPhotos) {
    return { ok: false, maxPhotos, storedCount };
  }

  return { ok: true, maxPhotos, storedCount };
}
