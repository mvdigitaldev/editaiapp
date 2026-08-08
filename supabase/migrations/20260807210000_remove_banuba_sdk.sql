-- Remove Banuba SDK settings (editor nativo único).
delete from public.app_settings
where setting_key in (
  'banuba_license_token',
  'face_editor_native_swap_enabled',
  'face_editor_native_rollout_percent'
);
