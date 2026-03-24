-- Expor role em user_profiles; RLS de escrita em categorias/modelos apenas para admin.

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
  p.add_credit,
  u.role::text AS role
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

COMMENT ON VIEW public.user_profiles IS 'Perfil estendido: users + plans + assinatura; inclui role (user/admin).';

GRANT SELECT ON public.user_profiles TO authenticated;
GRANT SELECT ON public.user_profiles TO anon;

-- Condição: usuário autenticado com role admin em public.users
-- (cada um pode ler a própria linha em users conforme políticas existentes)

CREATE POLICY "categorias_insert_admin" ON public.categorias
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
    )
  );

CREATE POLICY "categorias_update_admin" ON public.categorias
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
    )
  );

CREATE POLICY "categorias_delete_admin" ON public.categorias
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
    )
  );

CREATE POLICY "modelos_insert_admin" ON public.modelos
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
    )
  );

CREATE POLICY "modelos_update_admin" ON public.modelos
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
    )
  );

CREATE POLICY "modelos_delete_admin" ON public.modelos
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
    )
  );
