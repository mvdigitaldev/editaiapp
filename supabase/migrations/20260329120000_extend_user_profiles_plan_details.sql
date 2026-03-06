-- Estender user_profiles com campos do plano: photo_expiration_days, credit_expiration_days, credit_referral.
-- Usado na página de planos para exibir detalhes do plano atual do usuário.

-- Garantir que credit_referral existe em plans (caso não tenha sido adicionado antes)
ALTER TABLE public.plans ADD COLUMN IF NOT EXISTS credit_referral int NOT NULL DEFAULT 0 CHECK (credit_referral >= 0);
COMMENT ON COLUMN public.plans.credit_referral IS 'Créditos que o usuário ganha por indicação ativa';

-- DROP + CREATE evita erro 42P16 ao alterar colunas (PostgreSQL interpreta como rename em CREATE OR REPLACE)
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
  sub.ends_at AS subscription_ends_at,
  p.photo_expiration_days,
  p.credit_expiration_days,
  p.credit_referral
FROM public.users u
LEFT JOIN public.plans p ON p.id = u.current_plan_id
LEFT JOIN LATERAL (
  SELECT s.ends_at
  FROM public.subscriptions s
  WHERE s.user_id = u.id
    AND s.status IN ('active', 'trialing')
  ORDER BY s.ends_at DESC NULLS LAST
  LIMIT 1
) sub ON true;

COMMENT ON VIEW public.user_profiles IS 'Perfil estendido: users + plans + dados de assinatura. Inclui photo_expiration_days, credit_expiration_days, credit_referral do plano atual.';

GRANT SELECT ON public.user_profiles TO authenticated;
GRANT SELECT ON public.user_profiles TO anon;
