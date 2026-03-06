-- Corrige o cenário multi-conta: um token FCM deve pertencer a apenas um usuário por vez.
-- Remove duplicatas (mesmo token para múltiplos usuários), altera constraint e atualiza save_device_token.

-- 1. Deduplicar: manter apenas a linha mais recente por token
DELETE FROM public.device_tokens
WHERE id IN (
  SELECT id
  FROM (
    SELECT id,
      ROW_NUMBER() OVER (PARTITION BY token ORDER BY updated_at DESC) AS rn
    FROM public.device_tokens
  ) sub
  WHERE sub.rn > 1
);

-- 2. Remover constraint antiga (user_id, token)
ALTER TABLE public.device_tokens
  DROP CONSTRAINT IF EXISTS device_tokens_user_id_token_key;

-- 3. Adicionar constraint nova: token único por dispositivo
ALTER TABLE public.device_tokens
  ADD CONSTRAINT device_tokens_token_key UNIQUE (token);

-- 4. Atualizar save_device_token: ON CONFLICT (token) transfere o token para o novo usuário
CREATE OR REPLACE FUNCTION public.save_device_token(p_token text, p_platform text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;
  INSERT INTO public.device_tokens (user_id, token, platform, updated_at)
  VALUES (auth.uid(), p_token, p_platform, now())
  ON CONFLICT (token)
  DO UPDATE SET user_id = auth.uid(), platform = p_platform, updated_at = now();
END;
$$;
