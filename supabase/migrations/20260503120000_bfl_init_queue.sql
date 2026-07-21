-- Fila global para iniciação de tasks BFL com controle de capacidade.

CREATE EXTENSION IF NOT EXISTS pgmq;
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT pgmq.create('bfl-init-jobs');

CREATE OR REPLACE FUNCTION public.enqueue_bfl_init_job(p_msg jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pgmq
AS $$
DECLARE
  v_msg_id bigint;
BEGIN
  FOR v_msg_id IN SELECT pgmq.send('bfl-init-jobs', p_msg) LIMIT 1
  LOOP
    RETURN v_msg_id;
  END LOOP;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.enqueue_bfl_init_job(jsonb) IS
  'Enfileira job genérico de iniciação BFL.';

CREATE OR REPLACE FUNCTION public.read_bfl_init_job()
RETURNS TABLE(msg_id bigint, read_ct bigint, message jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pgmq
AS $$
  SELECT m.msg_id, m.read_ct, m.message
  FROM pgmq.read('bfl-init-jobs', 60, 1) m
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.read_bfl_init_job() IS
  'Lê uma mensagem da fila bfl-init-jobs (VT=60s).';

CREATE OR REPLACE FUNCTION public.delete_bfl_init_message(p_msg_id bigint)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pgmq
AS $$
  SELECT pgmq.delete('bfl-init-jobs', p_msg_id);
$$;

CREATE OR REPLACE FUNCTION public.archive_bfl_init_message(p_msg_id bigint)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pgmq
AS $$
  SELECT pgmq.archive('bfl-init-jobs', p_msg_id);
$$;

CREATE OR REPLACE FUNCTION public.bfl_init_queue_metrics()
RETURNS TABLE(queue_length bigint, oldest_msg_age_sec integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pgmq
AS $$
  SELECT m.queue_length, m.oldest_msg_age_sec
  FROM pgmq.metrics('bfl-init-jobs') m;
$$;

GRANT EXECUTE ON FUNCTION public.enqueue_bfl_init_job(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_bfl_init_job() TO service_role;
GRANT EXECUTE ON FUNCTION public.delete_bfl_init_message(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.archive_bfl_init_message(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.bfl_init_queue_metrics() TO service_role;

CREATE TABLE IF NOT EXISTS public.worker_leases (
  lease_name text PRIMARY KEY,
  holder_id text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.worker_leases IS
  'Leases curtos para coordenar workers stateless via banco.';

CREATE OR REPLACE FUNCTION public.try_acquire_worker_lease(
  p_lease_name text,
  p_holder_id text,
  p_ttl_seconds integer DEFAULT 120
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rowcount integer := 0;
  v_ttl_seconds integer := GREATEST(COALESCE(p_ttl_seconds, 120), 5);
BEGIN
  INSERT INTO public.worker_leases (lease_name, holder_id, expires_at)
  VALUES (
    p_lease_name,
    p_holder_id,
    now() + make_interval(secs => v_ttl_seconds)
  )
  ON CONFLICT (lease_name) DO UPDATE
  SET
    holder_id = EXCLUDED.holder_id,
    expires_at = EXCLUDED.expires_at,
    updated_at = now()
  WHERE public.worker_leases.expires_at <= now()
    OR public.worker_leases.holder_id = EXCLUDED.holder_id;

  GET DIAGNOSTICS v_rowcount = ROW_COUNT;
  RETURN v_rowcount > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.renew_worker_lease(
  p_lease_name text,
  p_holder_id text,
  p_ttl_seconds integer DEFAULT 120
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rowcount integer := 0;
  v_ttl_seconds integer := GREATEST(COALESCE(p_ttl_seconds, 120), 5);
BEGIN
  UPDATE public.worker_leases
  SET
    expires_at = now() + make_interval(secs => v_ttl_seconds),
    updated_at = now()
  WHERE lease_name = p_lease_name
    AND holder_id = p_holder_id;

  GET DIAGNOSTICS v_rowcount = ROW_COUNT;
  RETURN v_rowcount > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_worker_lease(
  p_lease_name text,
  p_holder_id text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rowcount integer := 0;
BEGIN
  DELETE FROM public.worker_leases
  WHERE lease_name = p_lease_name
    AND holder_id = p_holder_id;

  GET DIAGNOSTICS v_rowcount = ROW_COUNT;
  RETURN v_rowcount > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.try_acquire_worker_lease(text, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.renew_worker_lease(text, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.release_worker_lease(text, text) TO service_role;

INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('bfl_init_worker_url', 'https://dqlkcrdkgtpsmshwarzx.supabase.co/functions/v1/bfl-init-worker')
ON CONFLICT (setting_key) DO UPDATE SET
  setting_value = EXCLUDED.setting_value,
  updated_at = now();

CREATE OR REPLACE FUNCTION public.invoke_bfl_init_worker()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, vault
AS $function$
DECLARE
  fn_url text;
  invocation_secret text;
  req_headers jsonb;
BEGIN
  SELECT setting_value INTO fn_url
  FROM public.app_settings
  WHERE setting_key = 'bfl_init_worker_url'
  LIMIT 1;

  SELECT decrypted_secret INTO invocation_secret
  FROM vault.decrypted_secrets
  WHERE name = 'notify_credits_invocation_secret'
  LIMIT 1;

  IF fn_url IS NULL OR fn_url = '' OR invocation_secret IS NULL OR invocation_secret = '' THEN
    RAISE NOTICE 'invoke_bfl_init_worker: URL ou segredo não configurado';
    RETURN;
  END IF;

  req_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || trim(invocation_secret)
  );

  BEGIN
    PERFORM net.http_post(
      fn_url,
      '{}'::jsonb,
      '{}'::jsonb,
      req_headers,
      60000
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'invoke_bfl_init_worker: falha ao chamar worker: %', SQLERRM;
  END;
END;
$function$;

COMMENT ON FUNCTION public.invoke_bfl_init_worker() IS
  'Invoca a Edge Function bfl-init-worker. Chamado pelo cron a cada minuto.';

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'invoke-bfl-init-worker'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;
END;
$$;

SELECT cron.schedule(
  'invoke-bfl-init-worker',
  '* * * * *',
  'SELECT public.invoke_bfl_init_worker();'
);
