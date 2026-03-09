INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('enable_plans', 'enable')
ON CONFLICT (setting_key) DO NOTHING;
