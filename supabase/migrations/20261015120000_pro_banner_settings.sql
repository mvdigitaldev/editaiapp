-- Intervalo do convite principal e dias de silêncio depois de fechar.
INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('free_manual_pro_banner_every', '3'),
  ('pro_banner_dismiss_days', '7')
ON CONFLICT (setting_key) DO NOTHING;
