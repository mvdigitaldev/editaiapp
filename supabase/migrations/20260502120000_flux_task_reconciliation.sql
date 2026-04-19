-- Persistir dados de polling das tasks assíncronas e reconciliar pendências via cron.

ALTER TABLE public.flux_tasks
  ADD COLUMN IF NOT EXISTS provider text NOT NULL DEFAULT 'bfl';

ALTER TABLE public.flux_tasks
  ADD COLUMN IF NOT EXISTS polling_url text;

ALTER TABLE public.flux_tasks
  ADD COLUMN IF NOT EXISTS last_provider_status text;

ALTER TABLE public.flux_tasks
  ADD COLUMN IF NOT EXISTS last_polled_at timestamptz;

ALTER TABLE public.flux_tasks
  ADD COLUMN IF NOT EXISTS poll_attempt_count integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.flux_tasks.provider IS
  'Provedor responsável pela task assíncrona (ex.: bfl, fal).';
COMMENT ON COLUMN public.flux_tasks.polling_url IS
  'URL retornada pelo provedor para polling do resultado final.';
COMMENT ON COLUMN public.flux_tasks.last_provider_status IS
  'Último status observado no provedor externo.';
COMMENT ON COLUMN public.flux_tasks.last_polled_at IS
  'Timestamp do último polling ao provedor.';
COMMENT ON COLUMN public.flux_tasks.poll_attempt_count IS
  'Quantidade de consultas de polling realizadas para a task.';

UPDATE public.flux_tasks ft
SET provider = CASE
  WHEN e.operation_type = 'remove_background' THEN 'fal'
  ELSE 'bfl'
END
FROM public.edits e
WHERE e.id = ft.edit_id;

ALTER TABLE public.flux_tasks
  DROP CONSTRAINT IF EXISTS flux_tasks_provider_check;

ALTER TABLE public.flux_tasks
  ADD CONSTRAINT flux_tasks_provider_check
  CHECK (provider IN ('bfl', 'fal'));

CREATE INDEX IF NOT EXISTS idx_flux_tasks_pending_reconcile
  ON public.flux_tasks (provider, status, last_polled_at, created_at)
  WHERE status = 'pending';

CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('flux_task_reconciler_url', 'https://dqlkcrdkgtpsmshwarzx.supabase.co/functions/v1/flux-task-reconciler')
ON CONFLICT (setting_key) DO UPDATE SET
  setting_value = EXCLUDED.setting_value,
  updated_at = now();

CREATE OR REPLACE FUNCTION public.invoke_flux_task_reconciler()
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
  WHERE setting_key = 'flux_task_reconciler_url'
  LIMIT 1;

  SELECT decrypted_secret INTO invocation_secret
  FROM vault.decrypted_secrets
  WHERE name = 'notify_credits_invocation_secret'
  LIMIT 1;

  IF fn_url IS NULL OR fn_url = '' OR invocation_secret IS NULL OR invocation_secret = '' THEN
    RAISE NOTICE 'invoke_flux_task_reconciler: URL ou segredo não configurado';
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
    RAISE NOTICE 'invoke_flux_task_reconciler: falha ao chamar reconciler: %', SQLERRM;
  END;
END;
$$;

COMMENT ON FUNCTION public.invoke_flux_task_reconciler() IS
  'Invoca a Edge Function flux-task-reconciler. Chamado pelo cron a cada minuto.';

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'invoke-flux-task-reconciler'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;
END;
$$;

SELECT cron.schedule(
  'invoke-flux-task-reconciler',
  '* * * * *',
  $$SELECT public.invoke_flux_task_reconciler();$$
);
