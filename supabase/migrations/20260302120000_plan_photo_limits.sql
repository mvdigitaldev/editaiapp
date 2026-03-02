-- =============================================================================
-- Limite de fotos e expiração por plano
-- Campos em plans, expires_at em edits, função get_plan_photo_limits
-- =============================================================================

-- 1) Novos campos em plans
ALTER TABLE plans ADD COLUMN IF NOT EXISTS max_stored_photos int NOT NULL DEFAULT 10 CHECK (max_stored_photos >= 0);
ALTER TABLE plans ADD COLUMN IF NOT EXISTS photo_expiration_days int NOT NULL DEFAULT 15 CHECK (photo_expiration_days >= 1);

COMMENT ON COLUMN plans.max_stored_photos IS 'Máximo de fotos armazenadas (edits completed com image_url)';
COMMENT ON COLUMN plans.photo_expiration_days IS 'Dias até expiração automática da foto';

-- 2) Novo campo em edits
ALTER TABLE edits ADD COLUMN IF NOT EXISTS expires_at timestamptz;

COMMENT ON COLUMN edits.expires_at IS 'Data de expiração calculada no momento da criação (created_at + plan.photo_expiration_days)';

CREATE INDEX IF NOT EXISTS idx_edits_expires_at ON edits(expires_at) WHERE expires_at IS NOT NULL;

-- 3) Função auxiliar para obter limites do plano
CREATE OR REPLACE FUNCTION get_plan_photo_limits(p_user_id uuid)
RETURNS TABLE(max_photos int, expiration_days int) AS $$
  SELECT COALESCE(p.max_stored_photos, 10), COALESCE(p.photo_expiration_days, 15)
  FROM users u
  LEFT JOIN plans p ON p.id = u.current_plan_id
  WHERE u.id = p_user_id;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION get_plan_photo_limits(uuid) IS 'Retorna max_stored_photos e photo_expiration_days do plano do usuário';
