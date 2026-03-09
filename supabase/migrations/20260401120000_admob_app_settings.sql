-- AdMob ad unit IDs (test IDs for development; replace with real IDs in production)
INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('admob_banner_android', 'ca-app-pub-3940256099942544/6300978111'),
  ('admob_banner_ios', 'ca-app-pub-3940256099942544/2934735716'),
  ('admob_interstitial_android', 'ca-app-pub-3940256099942544/1033173712'),
  ('admob_interstitial_ios', 'ca-app-pub-3940256099942544/4411468910')
ON CONFLICT (setting_key) DO NOTHING;
