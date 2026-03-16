-- 1. Adicionar referral_code à view user_profiles (necessário para o link de indicação)
-- 2. Inserir referral_url em app_settings (URL base para concatenar com o código do usuário)

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

COMMENT ON VIEW public.user_profiles IS 'Perfil estendido: users + plans + dados de assinatura. Inclui referral_code para link de indicação.';

GRANT SELECT ON public.user_profiles TO authenticated;
GRANT SELECT ON public.user_profiles TO anon;

-- Inserir referral_url em app_settings (configure a URL real no Dashboard conforme seu domínio/app)
INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('referral_url', 'https://editai.com.br/?ref=')
ON CONFLICT (setting_key) DO NOTHING;
