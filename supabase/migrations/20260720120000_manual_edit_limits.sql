-- =============================================================================
-- Fase 1 Manual Editor — custo zero de créditos
-- =============================================================================

UPDATE app_settings
SET
  setting_value = (
    setting_value::jsonb || '{"manual_edit": 0}'::jsonb
  )::text,
  updated_at = now()
WHERE setting_key = 'operation_credit_costs'
  AND NOT (setting_value::jsonb ? 'manual_edit');
