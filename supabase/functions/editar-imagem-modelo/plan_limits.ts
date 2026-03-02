import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

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
