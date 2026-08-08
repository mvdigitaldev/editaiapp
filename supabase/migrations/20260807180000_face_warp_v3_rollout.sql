-- Face Warp V3 rollout (Sprint 38). Ausência da chave = desligado no cliente.
insert into public.app_settings (setting_key, setting_value)
values
  ('face_warp_v3_enabled', 'disable'),
  ('face_warp_v3_gpu_percent', '0'),
  ('face_warp_v3_inpaint_percent', '0')
on conflict (setting_key) do nothing;
