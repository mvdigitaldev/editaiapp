-- Feature flags da home. Ausência da chave mantém o módulo visível no cliente.
insert into public.app_settings (setting_key, setting_value)
values
  ('module_manual_edit_enabled', 'true'),
  ('module_ai_edit_enabled', 'true'),
  ('module_text_to_image_enabled', 'true'),
  ('module_multi_image_enabled', 'true'),
  ('module_remove_background_enabled', 'true'),
  ('banuba_license_token', '')
on conflict (setting_key) do nothing;

