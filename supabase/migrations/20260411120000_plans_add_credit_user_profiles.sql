-- Adicionar add_credit em plans (créditos ganhos na renovação do plano).
-- Expor add_credit na view user_profiles para exibir no card "Seu plano atual".

ALTER TABLE public.plans ADD COLUMN IF NOT EXISTS add_credit int NOT NULL DEFAULT 0 CHECK (add_credit >= 0);
COMMENT ON COLUMN public.plans.add_credit IS 'Créditos que o usuário ganha quando o plano é renovado';

DROP VIEW IF EXISTS public.user_profiles;

CREATE VIEW public.user_profiles AS
SELECT
  u.id,
  u.email,
  u.name AS display_name,
  u.avatar_url,
  u.referral_code,
  COALESCE(p.name, 'Free') AS subscription_tier,
  u.created_at,
  u.credits_balance,
  u.trial_ends_at,
  u.subscription_status,
  sub.started_at AS subscription_started_at,
  sub.ends_at AS subscription_ends_at,
  p.photo_expiration_days,
  p.credit_expiration_days,
  p.credit_referral,
  p.add_credit
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

COMMENT ON VIEW public.user_profiles IS 'Perfil estendido: users + plans + dados de assinatura. Inclui add_credit (créditos na renovação).';

GRANT SELECT ON public.user_profiles TO authenticated;
GRANT SELECT ON public.user_profiles TO anon;
