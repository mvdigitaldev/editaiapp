-- Notificação push quando o usuário recebe créditos (insert em credit_transactions com amount > 0).
-- Depende de: pg_net (habilitar no Dashboard: Database > Extensions > pg_net) e da Edge Function notify-credit-earned.
-- Configuração: ver migration 20260325120000 (URL em app_settings, segredo no Vault).

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.notify_credit_earned_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net
AS $$
DECLARE
  fn_url text;
  service_key text;
  req_body jsonb;
  req_headers jsonb;
BEGIN
  IF NEW.amount IS NULL OR NEW.amount <= 0 OR NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Tipos que geram notificação: créditos entrando (não usage)
  IF NEW.type::text = 'usage' THEN
    RETURN NEW;
  END IF;

  SELECT setting_value INTO fn_url
  FROM public.app_settings
  WHERE setting_key = 'notify_credit_earned_url'
  LIMIT 1;

  SELECT setting_value INTO service_key
  FROM public.app_settings
  WHERE setting_key = 'notify_credit_earned_service_role_key'
  LIMIT 1;

  IF fn_url IS NULL OR fn_url = '' OR service_key IS NULL OR service_key = '' THEN
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
    'Authorization', 'Bearer ' || service_key
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
  'Chama a Edge Function notify-credit-earned após insert em credit_transactions com amount > 0. Configure notify_credit_earned_url e notify_credit_earned_service_role_key em app_settings.';

DROP TRIGGER IF EXISTS credit_transactions_notify_credit_earned ON public.credit_transactions;

CREATE TRIGGER credit_transactions_notify_credit_earned
  AFTER INSERT ON public.credit_transactions
  FOR EACH ROW
  WHEN (NEW.amount > 0)
  EXECUTE FUNCTION public.notify_credit_earned_after_insert();
