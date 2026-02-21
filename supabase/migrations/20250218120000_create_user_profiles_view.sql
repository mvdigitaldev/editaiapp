-- View user_profiles: expõe users + plans no formato esperado pelo app (id, email, display_name, avatar_url, subscription_tier).
-- O app Flutter lê desta view após login/signUp; RLS das tabelas base (users) restringe por auth.uid().

CREATE OR REPLACE VIEW public.user_profiles AS
SELECT
  u.id,
  u.email,
  u.name AS display_name,
  u.avatar_url,
  COALESCE(p.name, 'Free') AS subscription_tier
FROM public.users u
LEFT JOIN public.plans p ON p.id = u.current_plan_id;

COMMENT ON VIEW public.user_profiles IS 'Perfil por usuário para o app: mapeia users + plans. Fonte: users (name -> display_name), plans.name -> subscription_tier.';

GRANT SELECT ON public.user_profiles TO authenticated;
GRANT SELECT ON public.user_profiles TO anon;
