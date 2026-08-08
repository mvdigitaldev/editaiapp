-- Face Warp V3 production rollout (Sprint 41).
insert into public.app_settings (setting_key, setting_value)
values
  ('face_warp_v3_rollout_percent', '0'),
  ('face_warp_v3_direct_percent', '0'),
  ('face_warp_v3_native_percent', '0')
on conflict (setting_key) do nothing;
