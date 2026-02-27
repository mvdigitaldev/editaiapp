-- Tabela para armazenar tokens FCM (push notifications) por usuário e dispositivo.
-- Um usuário pode ter vários tokens (vários dispositivos).
CREATE TABLE IF NOT EXISTS public.device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token text NOT NULL,
  platform text NOT NULL CHECK (platform IN ('ios', 'android')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, token)
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id ON public.device_tokens(user_id);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

-- Usuário só pode gerenciar seus próprios tokens.
CREATE POLICY "Users can manage own device_tokens"
  ON public.device_tokens
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- RPC chamada pelo app após login para salvar/atualizar o token FCM.
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
  ON CONFLICT (user_id, token)
  DO UPDATE SET platform = p_platform, updated_at = now();
END;
$$;
