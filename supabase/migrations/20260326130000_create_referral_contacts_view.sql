-- View segura para expor detalhes de indicações
-- Mostra apenas indicações em que o usuário autenticado é o referrer
-- e retorna nome + email mascarado do indicado.

CREATE OR REPLACE VIEW public.referral_contacts AS
SELECT
  r.id,
  r.referrer_user_id,
  r.referred_user_id,
  r.reward_credits,
  r.reward_status,
  r.created_at,
  u.name AS referred_name,
  -- Email mascarado no formato mate****@***.com
  CASE
    WHEN u.email IS NULL OR position('@' IN u.email) = 0 THEN '***@***'
    ELSE
      -- parte local
      (
        substring(u.email FROM 1 FOR LEAST(4, position('@' IN u.email) - 1))
        || '****'
      )
      || '@***.' ||
      -- tld (último segmento após o ponto)
      split_part(u.email, '.', array_length(string_to_array(u.email, '.'), 1))
  END AS referred_email_masked
FROM public.referrals r
JOIN public.users u ON u.id = r.referred_user_id
WHERE r.referrer_user_id = auth.uid();

GRANT SELECT ON public.referral_contacts TO authenticated;

-- Política adicional em users para permitir SELECT limitado
-- de nome/email apenas quando existe referral onde o usuário
-- autenticado é o referrer.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'users'
      AND policyname = 'users_select_referred_by_referrer'
  ) THEN
    CREATE POLICY "users_select_referred_by_referrer"
    ON public.users
    FOR SELECT
    TO authenticated
    USING (
      id = auth.uid()
      OR EXISTS (
        SELECT 1
        FROM public.referrals r
        WHERE r.referred_user_id = users.id
          AND r.referrer_user_id = auth.uid()
      )
    );
  END IF;
END
$$;

