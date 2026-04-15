CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE TABLE IF NOT EXISTS public.edit_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  edit_id uuid NOT NULL REFERENCES public.edits(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  terminal_status text NOT NULL CHECK (terminal_status IN ('completed', 'failed')),
  route text NOT NULL,
  delivery_status text NOT NULL DEFAULT 'pending'
    CHECK (delivery_status IN ('pending', 'sending', 'sent', 'failed')),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  last_error text,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (edit_id, terminal_status)
);

COMMENT ON TABLE public.edit_notifications IS
  'Outbox idempotente de notificações push terminais por edição.';

CREATE INDEX IF NOT EXISTS idx_edit_notifications_delivery_status
  ON public.edit_notifications (delivery_status, updated_at);

ALTER TABLE public.edit_notifications ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS edit_notifications_updated_at ON public.edit_notifications;
CREATE TRIGGER edit_notifications_updated_at
  BEFORE UPDATE ON public.edit_notifications
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('notify_edit_terminal_url', 'https://dqlkcrdkgtpsmshwarzx.supabase.co/functions/v1/notify-edit-terminal')
ON CONFLICT (setting_key) DO UPDATE SET
  setting_value = CASE
    WHEN COALESCE(public.app_settings.setting_value, '') = '' THEN EXCLUDED.setting_value
    ELSE public.app_settings.setting_value
  END,
  updated_at = CASE
    WHEN COALESCE(public.app_settings.setting_value, '') = '' THEN now()
    ELSE public.app_settings.updated_at
  END;

CREATE OR REPLACE FUNCTION public.enqueue_edit_terminal_notification(
  p_notification_id uuid
)
RETURNS void
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
  IF p_notification_id IS NULL THEN
    RETURN;
  END IF;

  SELECT setting_value INTO fn_url
  FROM public.app_settings
  WHERE setting_key = 'notify_edit_terminal_url'
  LIMIT 1;

  SELECT decrypted_secret INTO invocation_secret
  FROM vault.decrypted_secrets
  WHERE name = 'notify_edit_terminal_invocation_secret'
  LIMIT 1;

  IF invocation_secret IS NULL OR invocation_secret = '' THEN
    SELECT decrypted_secret INTO invocation_secret
    FROM vault.decrypted_secrets
    WHERE name = 'notify_credits_invocation_secret'
    LIMIT 1;
  END IF;

  IF fn_url IS NULL OR fn_url = '' OR invocation_secret IS NULL OR invocation_secret = '' THEN
    RETURN;
  END IF;

  req_body := jsonb_build_object('notification_id', p_notification_id);
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
    RAISE NOTICE 'enqueue_edit_terminal_notification: falha ao chamar Edge Function: %', SQLERRM;
  END;
END;
$$;

COMMENT ON FUNCTION public.enqueue_edit_terminal_notification(uuid) IS
  'Despacha uma notificação terminal de edição para a Edge Function notify-edit-terminal.';

CREATE OR REPLACE FUNCTION public.notify_edit_terminal_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.enqueue_edit_terminal_notification(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS edit_notifications_dispatch_after_insert ON public.edit_notifications;
CREATE TRIGGER edit_notifications_dispatch_after_insert
  AFTER INSERT ON public.edit_notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_edit_terminal_after_insert();

CREATE OR REPLACE FUNCTION public.create_edit_terminal_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_route text;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status::text NOT IN ('completed', 'failed') OR NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_route := CASE
    WHEN NEW.status::text = 'completed' THEN '/comparison'
    ELSE '/edit-detail'
  END;

  INSERT INTO public.edit_notifications (
    edit_id,
    user_id,
    terminal_status,
    route
  )
  VALUES (
    NEW.id,
    NEW.user_id,
    NEW.status::text,
    v_route
  )
  ON CONFLICT (edit_id, terminal_status) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.create_edit_terminal_notification() IS
  'Cria uma notificação push terminal idempotente quando a edição entra em completed ou failed.';

DROP TRIGGER IF EXISTS edits_create_terminal_notification ON public.edits;
CREATE TRIGGER edits_create_terminal_notification
  AFTER UPDATE ON public.edits
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status::text IN ('completed', 'failed'))
  EXECUTE FUNCTION public.create_edit_terminal_notification();

CREATE OR REPLACE FUNCTION public.dispatch_pending_edit_notifications(
  p_limit integer DEFAULT 25
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
BEGIN
  FOR v_row IN
    SELECT id
    FROM public.edit_notifications
    WHERE delivery_status IN ('pending', 'failed')
      AND sent_at IS NULL
    ORDER BY updated_at ASC, created_at ASC
    LIMIT GREATEST(COALESCE(p_limit, 25), 1)
  LOOP
    PERFORM public.enqueue_edit_terminal_notification(v_row.id);
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.dispatch_pending_edit_notifications(integer) IS
  'Reenvia notificações terminais pendentes ou falhas via pg_cron.';

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'dispatch-pending-edit-notifications'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;
END;
$$;

SELECT cron.schedule(
  'dispatch-pending-edit-notifications',
  '* * * * *',
  $$SELECT public.dispatch_pending_edit_notifications();$$
);
