-- Adicionar subscription_started_at à view user_profiles.
-- Usado no card "Seu plano atual" da página de planos (Contratado em).

DROP VIEW IF EXISTS public.user_profiles;

CREATE VIEW public.user_profiles AS
SELECT
  u.id,
  u.email,
  u.name AS display_name,
  u.avatar_url,
  COALESCE(p.name, 'Free') AS subscription_tier,
  u.created_at,
  u.credits_balance,
  u.trial_ends_at,
  u.subscription_status,
  sub.started_at AS subscription_started_at,
  sub.ends_at AS subscription_ends_at,
  p.photo_expiration_days,
  p.credit_expiration_days,
  p.credit_referral
FROM public.users u
LEFT JOIN public.plans p ON p.id = u.current_plan_id
LEFT JOIN LATERAL (
  SELECT s.started_at, s.ends_at
  FROM public.subscriptions s
  WHERE s.user_id = u.id
    AND s.status IN ('active', 'trialing')
  ORDER BY s.ends_at DESC NULLS LAST
  LIMIT 1
) sub ON true;

COMMENT ON VIEW public.user_profiles IS 'Perfil estendido: users + plans + dados de assinatura. Inclui subscription_started_at, subscription_ends_at, photo_expiration_days, credit_expiration_days, credit_referral.';

GRANT SELECT ON public.user_profiles TO authenticated;
GRANT SELECT ON public.user_profiles TO anon;
