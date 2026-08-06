-- Flag do editor facial próprio (beta) no hub de retoque.
-- Ausência da chave mantém o card visível; defina 'false' para esconder em produção.
insert into public.app_settings (setting_key, setting_value)
values
  ('module_face_lab_enabled', 'true')
on conflict (setting_key) do nothing;
