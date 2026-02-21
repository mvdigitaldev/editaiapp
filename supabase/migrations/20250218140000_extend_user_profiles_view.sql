-- Estender user_profiles com created_at, credits_balance, trial_ends_at, subscription_status
-- e subscription_ends_at (vencimento da assinatura ativa) para a página Meus dados e Painel.
-- Também cria o bucket de avatares e políticas de storage para upload por usuário autenticado.

-- =============================================================================
-- 1. VIEW user_profiles (estendida)
-- =============================================================================

CREATE OR REPLACE VIEW public.user_profiles AS
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
  sub.ends_at AS subscription_ends_at
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

COMMENT ON VIEW public.user_profiles IS 'Perfil estendido: users + plans + dados de assinatura. Inclui created_at, credits_balance, trial_ends_at, subscription_ends_at para Meus dados e Painel.';

GRANT SELECT ON public.user_profiles TO authenticated;
GRANT SELECT ON public.user_profiles TO anon;

-- =============================================================================
-- 2. BUCKET avatars (fotos de perfil)
-- =============================================================================
-- Cria o bucket para avatares; público para leitura (URL pública). Upload apenas
-- pelo dono do path (prefixo = auth.uid()).

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Política: usuário autenticado pode fazer upload apenas no próprio folder (path = {user_id}/...)
CREATE POLICY "avatars_insert_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Política: usuário pode atualizar/sobrescrever apenas os próprios arquivos
CREATE POLICY "avatars_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Política: usuário pode deletar apenas os próprios arquivos
CREATE POLICY "avatars_delete_own"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Bucket público: SELECT permite leitura por todos (anon + authenticated)
CREATE POLICY "avatars_select_public"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'avatars');
