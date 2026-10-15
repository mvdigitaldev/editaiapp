-- Cliques nos convites do Plano Pro. O app só grava o toque no botão;
-- o resumo entra na mesma leitura de admin.

CREATE TABLE public.pro_banner_clicks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  banner_kind text NOT NULL CHECK (
    banner_kind IN ('principal', 'compact', 'opportunity', 'offer')
  ),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX pro_banner_clicks_kind_created_idx
  ON public.pro_banner_clicks (banner_kind, created_at DESC);

COMMENT ON TABLE public.pro_banner_clicks IS
  'Toques no botão dos convites flutuantes do Plano Pro.';

ALTER TABLE public.pro_banner_clicks ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.pro_banner_clicks FROM PUBLIC, anon;
GRANT INSERT ON public.pro_banner_clicks TO authenticated;

CREATE POLICY pro_banner_clicks_insert_own
  ON public.pro_banner_clicks
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.get_admin_usage_overview()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_utc_now timestamp := v_now AT TIME ZONE 'utc';
  v_day_start timestamptz := date_trunc(
    'day',
    v_now AT TIME ZONE 'America/Sao_Paulo'
  ) AT TIME ZONE 'America/Sao_Paulo';
  v_day_start_utc timestamp := v_day_start AT TIME ZONE 'utc';
  v_since_30 timestamptz := v_now - interval '30 days';
  v_since_7 timestamptz := v_now - interval '7 days';
  v_online int := 0;
  v_active_today int := 0;
  v_edits_today int := 0;
  v_edits_7d int := 0;
  v_edits_30d int := 0;
  v_completed_30d int := 0;
  v_failed_30d int := 0;
  v_credits_30d int := 0;
  v_editors_30d int := 0;
  v_tools jsonb := '[]'::jsonb;
  v_plans jsonb := '[]'::jsonb;
  v_costs jsonb := '{}'::jsonb;
  v_banner_clicks jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.role = 'admin'::public.user_role
  ) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(DISTINCT s.user_id)::int
  INTO v_online
  FROM auth.sessions s
  WHERE s.refreshed_at IS NOT NULL
    AND s.refreshed_at > v_utc_now - interval '60 minutes'
    AND (s.not_after IS NULL OR s.not_after > v_now);

  SELECT COUNT(DISTINCT s.user_id)::int
  INTO v_active_today
  FROM auth.sessions s
  WHERE s.refreshed_at IS NOT NULL
    AND s.refreshed_at >= v_day_start_utc
    AND (s.not_after IS NULL OR s.not_after > v_now);

  SELECT
    COUNT(*) FILTER (WHERE created_at >= v_day_start)::int,
    COUNT(*) FILTER (WHERE created_at >= v_since_7)::int,
    COUNT(*)::int,
    COUNT(*) FILTER (WHERE status = 'completed')::int,
    COUNT(*) FILTER (WHERE status = 'failed')::int,
    COALESCE(SUM(credits_used) FILTER (WHERE status = 'completed'), 0)::int,
    COUNT(DISTINCT user_id)::int
  INTO
    v_edits_today,
    v_edits_7d,
    v_edits_30d,
    v_completed_30d,
    v_failed_30d,
    v_credits_30d,
    v_editors_30d
  FROM public.edits
  WHERE created_at >= v_since_30;

  SELECT COALESCE(jsonb_agg(tool ORDER BY (tool->>'total')::int DESC, tool->>'operation_type'), '[]'::jsonb)
  INTO v_tools
  FROM (
    SELECT jsonb_build_object(
      'operation_type', COALESCE(operation_type, 'unknown'),
      'total', COUNT(*)::int,
      'completed', COUNT(*) FILTER (WHERE status = 'completed')::int,
      'failed', COUNT(*) FILTER (WHERE status = 'failed')::int,
      'credits', COALESCE(SUM(credits_used) FILTER (WHERE status = 'completed'), 0)::int
    ) AS tool
    FROM public.edits
    WHERE created_at >= v_since_30
    GROUP BY COALESCE(operation_type, 'unknown')
  ) grouped;

  SELECT COALESCE(jsonb_agg(plan ORDER BY (plan->>'users')::int DESC, plan->>'name'), '[]'::jsonb)
  INTO v_plans
  FROM (
    SELECT jsonb_build_object(
      'name', COALESCE(p.name, 'Free'),
      'users', COUNT(*)::int
    ) AS plan
    FROM public.users u
    LEFT JOIN public.plans p ON p.id = u.current_plan_id
    GROUP BY COALESCE(p.name, 'Free')
  ) grouped;

  SELECT COALESCE(setting_value::jsonb, '{}'::jsonb)
  INTO v_costs
  FROM public.app_settings
  WHERE setting_key = 'operation_credit_costs'
  LIMIT 1;

  SELECT COALESCE(jsonb_agg(click ORDER BY (click->>'people')::int DESC, click->>'kind'), '[]'::jsonb)
  INTO v_banner_clicks
  FROM (
    SELECT jsonb_build_object(
      'kind', banner_kind,
      'clicks', COUNT(*)::int,
      'people', COUNT(DISTINCT user_id)::int
    ) AS click
    FROM public.pro_banner_clicks
    WHERE created_at >= v_since_30
    GROUP BY banner_kind
  ) grouped;

  RETURN jsonb_build_object(
    'generated_at', v_now,
    'online_window_minutes', 60,
    'online_users', v_online,
    'active_today', v_active_today,
    'edits_today', v_edits_today,
    'edits_7d', v_edits_7d,
    'edits_30d', v_edits_30d,
    'completed_30d', v_completed_30d,
    'failed_30d', v_failed_30d,
    'credits_30d', v_credits_30d,
    'editors_30d', v_editors_30d,
    'credit_costs', v_costs,
    'tools', v_tools,
    'plans', v_plans,
    'banner_clicks', v_banner_clicks
  );
END;
$$;
