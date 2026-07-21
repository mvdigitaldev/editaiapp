-- Sprint 27 ajustes: rollout 100%, marketplace admin-only, RLS publicação.

INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('beauty_engine_enabled', 'enable'),
  ('beauty_engine_rollout_percent', '100'),
  ('beauty_marketplace_publish_admin_only', 'enable')
ON CONFLICT (setting_key) DO UPDATE SET
  setting_value = EXCLUDED.setting_value,
  updated_at = now();

CREATE TABLE IF NOT EXISTS public.beauty_engine_error_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  context text,
  message text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_beauty_engine_error_logs_created
  ON public.beauty_engine_error_logs (created_at DESC);

ALTER TABLE public.beauty_engine_error_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "beauty_engine_errors_insert_own" ON public.beauty_engine_error_logs;
CREATE POLICY "beauty_engine_errors_insert_own"
  ON public.beauty_engine_error_logs
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id IS NULL OR user_id = auth.uid());

DROP POLICY IF EXISTS "beauty_engine_errors_insert_anon" ON public.beauty_engine_error_logs;
CREATE POLICY "beauty_engine_errors_insert_anon"
  ON public.beauty_engine_error_logs
  FOR INSERT
  TO anon
  WITH CHECK (user_id IS NULL);

DROP POLICY IF EXISTS "beauty_engine_errors_no_select" ON public.beauty_engine_error_logs;
CREATE POLICY "beauty_engine_errors_no_select"
  ON public.beauty_engine_error_logs
  FOR SELECT
  TO authenticated, anon
  USING (false);

CREATE OR REPLACE FUNCTION public.can_publish_beauty_preset_to_marketplace()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN COALESCE(
      (
        SELECT lower(trim(setting_value))
        FROM public.app_settings
        WHERE setting_key = 'beauty_marketplace_publish_admin_only'
      ),
      'disable'
    ) <> 'enable' THEN true
    ELSE public.is_admin_user()
  END;
$$;

GRANT EXECUTE ON FUNCTION public.can_publish_beauty_preset_to_marketplace() TO authenticated;

DROP POLICY IF EXISTS beauty_presets_insert_own ON public.beauty_presets;
CREATE POLICY beauty_presets_insert_own
ON public.beauty_presets FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND (NOT is_public OR public.can_publish_beauty_preset_to_marketplace())
);

DROP POLICY IF EXISTS beauty_presets_update_own ON public.beauty_presets;
CREATE POLICY beauty_presets_update_own
ON public.beauty_presets FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (
  user_id = auth.uid()
  AND (NOT is_public OR public.can_publish_beauty_preset_to_marketplace())
);

COMMENT ON FUNCTION public.can_publish_beauty_preset_to_marketplace() IS
  'Quando beauty_marketplace_publish_admin_only=enable, só admin pode is_public=true.';
