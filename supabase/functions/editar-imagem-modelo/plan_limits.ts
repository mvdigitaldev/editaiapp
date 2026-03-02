import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export interface PhotoLimitResult {
  allowed: boolean;
  current: number;
  max: number;
}

/**
 * Verifica se o usuário pode adicionar mais fotos (edits completed com image_url).
 * Retorna allowed=false se count >= max.
 */
export async function checkPhotoLimit(
  supabase: SupabaseClient,
  userId: string
): Promise<PhotoLimitResult> {
  const { data: limits } = await supabase
    .rpc("get_plan_photo_limits", { p_user_id: userId })
    .single();

  const max = limits?.max_photos ?? 10;

  const { count, error } = await supabase
    .from("edits")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("status", "completed")
    .not("image_url", "is", null)
    .or(`expires_at.is.null,expires_at.gt.${new Date().toISOString()}`);

  if (error) {
    console.error("[plan_limits] Erro ao contar edits:", error);
    return { allowed: true, current: 0, max };
  }

  const current = count ?? 0;
  return {
    allowed: current < max,
    current,
    max,
  };
}

/**
 * Retorna os dias de expiração do plano do usuário.
 */
export async function getExpirationDays(
  supabase: SupabaseClient,
  userId: string
): Promise<number> {
  const { data } = await supabase
    .rpc("get_plan_photo_limits", { p_user_id: userId })
    .single();
  return data?.expiration_days ?? 15;
}
