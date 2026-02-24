CREATE TABLE IF NOT EXISTS public.app_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  setting_key text NOT NULL UNIQUE,
  setting_value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "app_settings_select_public" ON public.app_settings
  FOR SELECT USING (true);

INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('support_whatsapp', '5511999999999'),
  ('support_email', 'suporte@editai.com.br')
ON CONFLICT (setting_key) DO NOTHING;
