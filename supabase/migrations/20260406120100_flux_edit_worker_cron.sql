-- Cron para invocar o flux-edit-worker a cada minuto (fallback).
-- Depende de: pg_net, Vault. URL em app_settings (flux_edit_worker_url), segredo no Vault (notify_credits_invocation_secret).

CREATE EXTENSION IF NOT EXISTS pg_net;

INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('flux_edit_worker_url', 'https://dqlkcrdkgtpsmshwarzx.supabase.co/functions/v1/flux-edit-worker')
ON CONFLICT (setting_key) DO UPDATE SET
  setting_value = EXCLUDED.setting_value,
  updated_at = now();

CREATE OR REPLACE FUNCTION public.invoke_flux_edit_worker()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, vault
AS $$
DECLARE
  fn_url text;
  invocation_secret text;
  req_headers jsonb;
BEGIN
  SELECT setting_value INTO fn_url
  FROM public.app_settings
  WHERE setting_key = 'flux_edit_worker_url'
  LIMIT 1;

  SELECT decrypted_secret INTO invocation_secret
  FROM vault.decrypted_secrets
  WHERE name = 'notify_credits_invocation_secret'
  LIMIT 1;

  IF fn_url IS NULL OR fn_url = '' OR invocation_secret IS NULL OR invocation_secret = '' THEN
    RAISE NOTICE 'invoke_flux_edit_worker: URL ou segredo não configurado';
    RETURN;
  END IF;

  req_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || trim(invocation_secret)
  );

  BEGIN
    PERFORM net.http_post(
      url := fn_url,
      body := '{}'::jsonb,
      headers := req_headers,
      timeout_milliseconds := 60000
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'invoke_flux_edit_worker: falha ao chamar worker: %', SQLERRM;
  END;
END;
$$;

COMMENT ON FUNCTION public.invoke_flux_edit_worker() IS
  'Invoca a Edge Function flux-edit-worker. Chamado pelo cron a cada minuto. URL em app_settings (flux_edit_worker_url); segredo no Vault (notify_credits_invocation_secret).';

-- Agendar execução a cada minuto
DO $$
DECLARE
  v_job_id bigint;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'invoke-flux-edit-worker'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;
END;
$$;

SELECT cron.schedule(
  'invoke-flux-edit-worker',
  '* * * * *',
  $$SELECT public.invoke_flux_edit_worker();$$
);
