-- Remove uso de service_role_key da tabela app_settings.
-- O trigger passa a usar um segredo de invocação guardado no Vault; a Edge Function
-- valida o header Authorization (Bearer) e usa apenas SUPABASE_SERVICE_ROLE_KEY das suas secrets.

CREATE OR REPLACE FUNCTION public.notify_credit_earned_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, vault
AS $$
DECLARE
  fn_url text;
  invocation_secret text;
  req_body jsonb;
  req_headers jsonb;
BEGIN
  IF NEW.amount IS NULL OR NEW.amount <= 0 OR NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.type::text = 'usage' THEN
    RETURN NEW;
  END IF;

  SELECT setting_value INTO fn_url
  FROM public.app_settings
  WHERE setting_key = 'notify_credit_earned_url'
  LIMIT 1;

  SELECT decrypted_secret INTO invocation_secret
  FROM vault.decrypted_secrets
  WHERE name = 'notify_credits_invocation_secret'
  LIMIT 1;

  IF fn_url IS NULL OR fn_url = '' OR invocation_secret IS NULL OR invocation_secret = '' THEN
    RETURN NEW;
  END IF;

  req_body := jsonb_build_object(
    'user_id', NEW.user_id,
    'amount', NEW.amount,
    'type', NEW.type::text,
    'description', NEW.description
  );

  req_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || invocation_secret
  );

  BEGIN
    PERFORM net.http_post(
      url := fn_url,
      body := req_body,
      headers := req_headers,
      timeout_milliseconds := 10000
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'notify_credit_earned: falha ao chamar Edge Function: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_credit_earned_after_insert() IS
  'Chama a Edge Function notify-credit-earned após insert em credit_transactions. URL em app_settings (notify_credit_earned_url); segredo de invocação no Vault (notify_credits_invocation_secret). A Edge Function usa SUPABASE_SERVICE_ROLE_KEY das suas secrets.';
