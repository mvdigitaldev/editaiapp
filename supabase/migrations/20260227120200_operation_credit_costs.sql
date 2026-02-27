-- =============================================================================
-- Custos por operação (créditos a cobrar)
-- FLUX.2 Pro: text_to_image=5, edit_image=7, remove_background=7, multi_image dinâmico
-- =============================================================================

INSERT INTO app_settings (setting_key, setting_value, updated_at)
VALUES (
  'operation_credit_costs',
  '{"text_to_image":5,"edit_image":7,"remove_background":7,"multi_image_base":7,"multi_image_per_image":3}',
  now()
)
ON CONFLICT (setting_key) DO UPDATE SET
  setting_value = EXCLUDED.setting_value,
  updated_at = now();

-- Nota: multi_image = 7 + (N-1)*3 créditos para N imagens (1-8)
