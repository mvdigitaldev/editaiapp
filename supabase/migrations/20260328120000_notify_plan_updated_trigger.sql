-- Push notification quando o plano do usuário é atualizado (current_plan_id na tabela users).
-- Depende de: pg_net, Vault. Configuração: URL em app_settings, segredo no Vault.
-- O trigger dispara apenas quando current_plan_id realmente muda (incluindo NULL).

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.notify_plan_updated_after_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, vault
AS $$
DECLARE
  fn_url text;
  invocation_secret text;
  new_plan_name text;
  req_body jsonb;
  req_headers jsonb;
BEGIN
  -- Obter nome do novo plano (NULL -> Free)
  IF NEW.current_plan_id IS NULL THEN
    new_plan_name := 'Free';
  ELSE
    SELECT COALESCE(p.name, 'Free') INTO new_plan_name
    FROM public.plans p
    WHERE p.id = NEW.current_plan_id
    LIMIT 1;
    IF new_plan_name IS NULL THEN
      new_plan_name := 'Free';
    END IF;
  END IF;

  SELECT setting_value INTO fn_url
  FROM public.app_settings
  WHERE setting_key = 'notify_plan_updated_url'
  LIMIT 1;

  SELECT decrypted_secret INTO invocation_secret
  FROM vault.decrypted_secrets
  WHERE name = 'notify_plan_updated_invocation_secret'
  LIMIT 1;

  IF invocation_secret IS NULL OR invocation_secret = '' THEN
    SELECT decrypted_secret INTO invocation_secret
    FROM vault.decrypted_secrets
    WHERE name = 'notify_credits_invocation_secret'
    LIMIT 1;
  END IF;

  IF fn_url IS NULL OR fn_url = '' OR invocation_secret IS NULL OR invocation_secret = '' THEN
    RETURN NEW;
  END IF;

  req_body := jsonb_build_object(
    'user_id', NEW.id,
    'new_plan_id', NEW.current_plan_id,
    'new_plan_name', new_plan_name
  );

  req_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || trim(invocation_secret)
  );

  BEGIN
    PERFORM net.http_post(
      url := fn_url,
      body := req_body,
      headers := req_headers,
      timeout_milliseconds := 10000
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'notify_plan_updated: falha ao chamar Edge Function: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_plan_updated_after_update() IS
  'Chama a Edge Function notify-plan-updated após update em users quando current_plan_id muda. URL em app_settings (notify_plan_updated_url); segredo no Vault (notify_plan_updated_invocation_secret).';

DROP TRIGGER IF EXISTS users_notify_plan_updated ON public.users;

CREATE TRIGGER users_notify_plan_updated
  AFTER UPDATE ON public.users
  FOR EACH ROW
  WHEN (OLD.current_plan_id IS DISTINCT FROM NEW.current_plan_id)
  EXECUTE FUNCTION public.notify_plan_updated_after_update();

-- Placeholder para URL (valor real configurado no deploy)
INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('notify_plan_updated_url', '')
ON CONFLICT (setting_key) DO NOTHING;
