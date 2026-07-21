-- Sprint 27: feature flag + rollout gradual + telemetria de erros Beauty Engine

INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('beauty_engine_enabled', 'enable'),
  ('beauty_engine_rollout_percent', '100')
ON CONFLICT (setting_key) DO UPDATE SET
  setting_value = EXCLUDED.setting_value,
  updated_at = now();

COMMENT ON TABLE public.app_settings IS
  'beauty_engine_enabled: enable|disable; beauty_engine_rollout_percent: 0-100 (rollout gradual)';

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

CREATE POLICY "beauty_engine_errors_insert_own"
  ON public.beauty_engine_error_logs
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id IS NULL OR user_id = auth.uid());

CREATE POLICY "beauty_engine_errors_insert_anon"
  ON public.beauty_engine_error_logs
  FOR INSERT
  TO anon
  WITH CHECK (user_id IS NULL);

-- Leitura restrita a service role / dashboard (sem SELECT para clientes)
CREATE POLICY "beauty_engine_errors_no_select"
  ON public.beauty_engine_error_logs
  FOR SELECT
  TO authenticated, anon
  USING (false);

COMMENT ON TABLE public.beauty_engine_error_logs IS
  'Telemetria pós-release Sprint 27 — monitorar crash-free rate (consultar via SQL/dashboard).';
