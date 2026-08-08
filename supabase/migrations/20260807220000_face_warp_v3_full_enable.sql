-- Pré-produção: Face Warp V3 integralmente ligado (100%).
update public.app_settings set setting_value = 'enable'
  where setting_key = 'face_warp_v3_enabled';

update public.app_settings set setting_value = '100'
  where setting_key in (
    'face_warp_v3_rollout_percent',
    'face_warp_v3_direct_percent',
    'face_warp_v3_gpu_percent',
    'face_warp_v3_inpaint_percent',
    'face_warp_v3_native_percent'
  );
