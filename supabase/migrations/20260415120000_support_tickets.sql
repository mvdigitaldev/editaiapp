CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'ticket_status'
      AND typnamespace = 'public'::regnamespace
  ) THEN
    CREATE TYPE public.ticket_status AS ENUM (
      'NOVO',
      'ABERTO',
      'AGUARDANDO_CLIENTE',
      'RESPONDIDO',
      'FECHADO'
    );
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.support_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL
    CONSTRAINT support_tickets_user_id_fkey
    REFERENCES public.users(id) ON DELETE CASCADE,
  subject text,
  status public.ticket_status NOT NULL DEFAULT 'NOVO',
  closed_at timestamptz,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  last_message_preview text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.support_tickets IS
  'Chamados de suporte criados pelos usuarios.';

CREATE TABLE IF NOT EXISTS public.support_ticket_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL
    CONSTRAINT support_ticket_messages_ticket_id_fkey
    REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  user_id uuid NOT NULL
    CONSTRAINT support_ticket_messages_user_id_fkey
    REFERENCES public.users(id) ON DELETE CASCADE,
  message text NOT NULL CHECK (char_length(btrim(message)) > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.support_ticket_messages IS
  'Mensagens trocadas dentro de um chamado de suporte.';

CREATE TABLE IF NOT EXISTS public.support_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  message_id uuid REFERENCES public.support_ticket_messages(id) ON DELETE CASCADE,
  recipient_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('new_ticket', 'admin_reply')),
  route text NOT NULL DEFAULT '/support-ticket',
  delivery_status text NOT NULL DEFAULT 'pending'
    CHECK (delivery_status IN ('pending', 'sending', 'sent', 'failed')),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  last_error text,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.support_notifications IS
  'Outbox idempotente de notificacoes push relacionadas a chamados.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_support_notifications_new_ticket_unique
  ON public.support_notifications (ticket_id, recipient_user_id, kind)
  WHERE kind = 'new_ticket';

CREATE UNIQUE INDEX IF NOT EXISTS idx_support_notifications_admin_reply_unique
  ON public.support_notifications (message_id, recipient_user_id, kind)
  WHERE kind = 'admin_reply';

CREATE INDEX IF NOT EXISTS idx_support_tickets_user_id
  ON public.support_tickets (user_id);

CREATE INDEX IF NOT EXISTS idx_support_tickets_status
  ON public.support_tickets (status);

CREATE INDEX IF NOT EXISTS idx_support_tickets_last_message_at
  ON public.support_tickets (last_message_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_ticket_messages_ticket_created_at
  ON public.support_ticket_messages (ticket_id, created_at);

CREATE INDEX IF NOT EXISTS idx_support_notifications_delivery_status
  ON public.support_notifications (delivery_status, updated_at);

DROP TRIGGER IF EXISTS support_tickets_updated_at ON public.support_tickets;
CREATE TRIGGER support_tickets_updated_at
  BEFORE UPDATE ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS support_notifications_updated_at ON public.support_notifications;
CREATE TRIGGER support_notifications_updated_at
  BEFORE UPDATE ON public.support_notifications
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.is_admin_user(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = COALESCE(p_user_id, auth.uid())
      AND u.role = 'admin'::public.user_role
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_admin_user(uuid) TO authenticated;

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_ticket_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_admin" ON public.users;
CREATE POLICY "users_select_admin" ON public.users
  FOR SELECT
  USING (public.is_admin_user());

DROP POLICY IF EXISTS "support_tickets_select_own_or_admin" ON public.support_tickets;
CREATE POLICY "support_tickets_select_own_or_admin" ON public.support_tickets
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin_user());

DROP POLICY IF EXISTS "support_tickets_insert_own" ON public.support_tickets;
CREATE POLICY "support_tickets_insert_own" ON public.support_tickets
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "support_tickets_update_admin" ON public.support_tickets;
CREATE POLICY "support_tickets_update_admin" ON public.support_tickets
  FOR UPDATE
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

DROP POLICY IF EXISTS "support_ticket_messages_select_via_ticket" ON public.support_ticket_messages;
CREATE POLICY "support_ticket_messages_select_via_ticket" ON public.support_ticket_messages
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.support_tickets t
      WHERE t.id = support_ticket_messages.ticket_id
        AND (t.user_id = auth.uid() OR public.is_admin_user())
    )
  );

DROP POLICY IF EXISTS "support_ticket_messages_insert_owner_or_admin" ON public.support_ticket_messages;
CREATE POLICY "support_ticket_messages_insert_owner_or_admin" ON public.support_ticket_messages
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.support_tickets t
      WHERE t.id = support_ticket_messages.ticket_id
        AND (
          (
            t.user_id = auth.uid()
            AND support_ticket_messages.user_id = auth.uid()
            AND t.status <> 'FECHADO'::public.ticket_status
          )
          OR (
            public.is_admin_user()
            AND support_ticket_messages.user_id = auth.uid()
            AND t.status <> 'FECHADO'::public.ticket_status
          )
        )
    )
  );

CREATE OR REPLACE FUNCTION public.create_support_ticket(
  p_subject text DEFAULT NULL,
  p_message text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_ticket_id uuid;
  v_message text;
  v_subject text;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  v_message := NULLIF(btrim(COALESCE(p_message, '')), '');
  IF v_message IS NULL THEN
    RAISE EXCEPTION 'A descricao do chamado e obrigatoria';
  END IF;

  v_subject := NULLIF(btrim(COALESCE(p_subject, '')), '');
  IF v_subject IS NULL THEN
    v_subject := left(v_message, 80);
  END IF;

  INSERT INTO public.support_tickets (
    user_id,
    subject,
    status,
    last_message_at,
    last_message_preview
  )
  VALUES (
    v_user_id,
    v_subject,
    'NOVO'::public.ticket_status,
    now(),
    left(v_message, 160)
  )
  RETURNING id INTO v_ticket_id;

  INSERT INTO public.support_ticket_messages (
    ticket_id,
    user_id,
    message
  )
  VALUES (
    v_ticket_id,
    v_user_id,
    v_message
  );

  RETURN v_ticket_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_support_ticket(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reopen_support_ticket(
  p_ticket_id uuid,
  p_message text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket public.support_tickets%ROWTYPE;
  v_message text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  SELECT *
  INTO v_ticket
  FROM public.support_tickets
  WHERE id = p_ticket_id
    AND user_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chamado nao encontrado';
  END IF;

  IF v_ticket.status <> 'FECHADO'::public.ticket_status THEN
    RAISE EXCEPTION 'Somente chamados fechados podem ser reabertos';
  END IF;

  UPDATE public.support_tickets
  SET status = 'ABERTO'::public.ticket_status,
      closed_at = NULL,
      updated_at = now()
  WHERE id = p_ticket_id;

  v_message := NULLIF(btrim(COALESCE(p_message, '')), '');
  IF v_message IS NOT NULL THEN
    INSERT INTO public.support_ticket_messages (
      ticket_id,
      user_id,
      message
    )
    VALUES (
      p_ticket_id,
      auth.uid(),
      v_message
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reopen_support_ticket(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.sync_support_ticket_after_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket public.support_tickets%ROWTYPE;
  v_is_admin boolean;
  v_has_previous_message boolean;
  v_next_status public.ticket_status;
BEGIN
  SELECT *
  INTO v_ticket
  FROM public.support_tickets
  WHERE id = NEW.ticket_id;

  v_is_admin := public.is_admin_user(NEW.user_id);

  SELECT EXISTS (
    SELECT 1
    FROM public.support_ticket_messages m
    WHERE m.ticket_id = NEW.ticket_id
      AND m.id <> NEW.id
  )
  INTO v_has_previous_message;

  v_next_status := v_ticket.status;

  IF v_is_admin THEN
    IF v_ticket.status <> 'FECHADO'::public.ticket_status THEN
      v_next_status := 'AGUARDANDO_CLIENTE'::public.ticket_status;
    END IF;
  ELSIF v_has_previous_message AND v_ticket.status <> 'FECHADO'::public.ticket_status THEN
    v_next_status := 'ABERTO'::public.ticket_status;
  END IF;

  UPDATE public.support_tickets
  SET last_message_at = NEW.created_at,
      last_message_preview = left(NEW.message, 160),
      status = v_next_status,
      closed_at = CASE
        WHEN v_next_status = 'FECHADO'::public.ticket_status THEN closed_at
        ELSE NULL
      END,
      updated_at = now()
  WHERE id = NEW.ticket_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS support_ticket_messages_sync_ticket ON public.support_ticket_messages;
CREATE TRIGGER support_ticket_messages_sync_ticket
  AFTER INSERT ON public.support_ticket_messages
  FOR EACH ROW EXECUTE FUNCTION public.sync_support_ticket_after_message();

CREATE OR REPLACE FUNCTION public.enqueue_support_notification(
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
  WHERE setting_key = 'notify_support_ticket_url'
  LIMIT 1;

  SELECT decrypted_secret INTO invocation_secret
  FROM vault.decrypted_secrets
  WHERE name = 'notify_support_ticket_invocation_secret'
  LIMIT 1;

  IF invocation_secret IS NULL OR invocation_secret = '' THEN
    SELECT decrypted_secret INTO invocation_secret
    FROM vault.decrypted_secrets
    WHERE name = 'notify_edit_terminal_invocation_secret'
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
    RAISE NOTICE 'enqueue_support_notification: falha ao chamar Edge Function: %', SQLERRM;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_support_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.enqueue_support_notification(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS support_notifications_dispatch_after_insert ON public.support_notifications;
CREATE TRIGGER support_notifications_dispatch_after_insert
  AFTER INSERT ON public.support_notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_support_after_insert();

CREATE OR REPLACE FUNCTION public.create_support_notifications_for_new_ticket()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.support_notifications (
    ticket_id,
    recipient_user_id,
    actor_user_id,
    kind,
    route
  )
  SELECT
    NEW.id,
    u.id,
    NEW.user_id,
    'new_ticket',
    '/support-ticket'
  FROM public.users u
  WHERE u.role = 'admin'::public.user_role
    AND u.id <> NEW.user_id
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS support_tickets_create_notifications_after_insert ON public.support_tickets;
CREATE TRIGGER support_tickets_create_notifications_after_insert
  AFTER INSERT ON public.support_tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.create_support_notifications_for_new_ticket();

CREATE OR REPLACE FUNCTION public.create_support_notifications_for_admin_reply()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket public.support_tickets%ROWTYPE;
BEGIN
  IF NOT public.is_admin_user(NEW.user_id) THEN
    RETURN NEW;
  END IF;

  SELECT *
  INTO v_ticket
  FROM public.support_tickets
  WHERE id = NEW.ticket_id;

  IF NOT FOUND OR v_ticket.user_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.support_notifications (
    ticket_id,
    message_id,
    recipient_user_id,
    actor_user_id,
    kind,
    route
  )
  VALUES (
    NEW.ticket_id,
    NEW.id,
    v_ticket.user_id,
    NEW.user_id,
    'admin_reply',
    '/support-ticket'
  )
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS support_ticket_messages_create_notifications_after_insert ON public.support_ticket_messages;
CREATE TRIGGER support_ticket_messages_create_notifications_after_insert
  AFTER INSERT ON public.support_ticket_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.create_support_notifications_for_admin_reply();

CREATE OR REPLACE FUNCTION public.dispatch_pending_support_notifications(
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
    FROM public.support_notifications
    WHERE delivery_status IN ('pending', 'failed')
      AND sent_at IS NULL
    ORDER BY updated_at ASC, created_at ASC
    LIMIT GREATEST(COALESCE(p_limit, 25), 1)
  LOOP
    PERFORM public.enqueue_support_notification(v_row.id);
  END LOOP;
END;
$$;

INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('notify_support_ticket_url', 'https://dqlkcrdkgtpsmshwarzx.supabase.co/functions/v1/notify-support-ticket')
ON CONFLICT (setting_key) DO UPDATE SET
  setting_value = CASE
    WHEN COALESCE(public.app_settings.setting_value, '') = '' THEN EXCLUDED.setting_value
    ELSE public.app_settings.setting_value
  END,
  updated_at = CASE
    WHEN COALESCE(public.app_settings.setting_value, '') = '' THEN now()
    ELSE public.app_settings.updated_at
  END;

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'dispatch-pending-support-notifications'
  LIMIT 1;

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;
END;
$$;

SELECT cron.schedule(
  'dispatch-pending-support-notifications',
  '* * * * *',
  $$SELECT public.dispatch_pending_support_notifications();$$
);
