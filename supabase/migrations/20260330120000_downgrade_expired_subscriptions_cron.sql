-- =============================================================================
-- Downgrade para Free quando assinatura vencer.
-- Executa diariamente às 12h: identifica usuários cuja subscription mais recente
-- expirou (ends_at < now) e atualiza current_plan_id para Free.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.downgrade_expired_subscriptions()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  free_plan_id uuid;
  updated_count int;
BEGIN
  SELECT id INTO free_plan_id
  FROM public.plans
  WHERE name ILIKE 'free'
  LIMIT 1;

  IF free_plan_id IS NULL THEN
    RAISE NOTICE 'downgrade_expired_subscriptions: plano Free não encontrado';
    RETURN 0;
  END IF;

  WITH users_to_downgrade AS (
    SELECT u.id
    FROM public.users u
    WHERE u.current_plan_id IS DISTINCT FROM free_plan_id
      AND NOT EXISTS (
        SELECT 1
        FROM public.subscriptions s
        WHERE s.user_id = u.id
          AND s.ends_at >= now()
      )
  )
  UPDATE public.users u
  SET
    current_plan_id = free_plan_id,
    subscription_status = 'expired'
  FROM users_to_downgrade utd
  WHERE u.id = utd.id;

  GET DIAGNOSTICS updated_count = ROW_COUNT;

  IF updated_count > 0 THEN
    RAISE NOTICE 'downgrade_expired_subscriptions: % usuário(s) rebaixado(s) para Free', updated_count;
  END IF;

  RETURN updated_count;
END;
$$;

COMMENT ON FUNCTION public.downgrade_expired_subscriptions() IS
  'Rebaixa para Free usuários cuja assinatura expirou (nenhuma subscription com ends_at >= now). Chamada diariamente pelo cron às 12h.';

-- Agendar execução diária às 12h
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'downgrade-expired-subscriptions'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;
END;
$$;

SELECT cron.schedule(
  'downgrade-expired-subscriptions',
  '0 12 * * *',
  $$SELECT public.downgrade_expired_subscriptions();$$
);
