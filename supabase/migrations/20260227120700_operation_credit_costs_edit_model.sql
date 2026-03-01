-- =============================================================================
-- Adicionar edit_model aos custos de operação (7 créditos, igual a edit_image)
-- =============================================================================

UPDATE app_settings
SET
  setting_value = '{"text_to_image":5,"edit_image":7,"edit_model":7,"remove_background":7,"multi_image_base":7,"multi_image_per_image":3}',
  updated_at = now()
WHERE setting_key = 'operation_credit_costs';
