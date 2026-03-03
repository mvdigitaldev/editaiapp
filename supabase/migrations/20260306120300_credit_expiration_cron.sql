-- =============================================================================
-- Schedules credit reservation cleanup and lot expiration.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'cleanup-stale-credit-reservations'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;

  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'expire-credit-lots-daily'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;
END;
$$;

SELECT cron.schedule(
  'cleanup-stale-credit-reservations',
  '*/5 * * * *',
  $$SELECT public.cleanup_stale_credit_reservations(5000);$$
);

SELECT cron.schedule(
  'expire-credit-lots-daily',
  '0 4 * * *',
  $$SELECT * FROM public.expire_credit_lots(2000);$$
);
