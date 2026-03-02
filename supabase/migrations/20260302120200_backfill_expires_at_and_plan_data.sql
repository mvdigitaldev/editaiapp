-- =============================================================================
-- Backfill expires_at em edits existentes + dados dos planos
-- =============================================================================

-- 1) Backfill expires_at para edits que ainda não têm
UPDATE edits e
SET expires_at = e.created_at + (
  COALESCE(
    (SELECT p.photo_expiration_days FROM plans p JOIN users u ON u.current_plan_id = p.id WHERE u.id = e.user_id),
    15
  ) * interval '1 day'
)
WHERE e.expires_at IS NULL;

-- 2) Atualizar planos com limites de fotos e expiração
-- Premium: 30 fotos, 30 dias
UPDATE plans SET max_stored_photos = 30, photo_expiration_days = 30
WHERE name ILIKE '%premium%' OR name = 'Premium';

-- Basic: 10 fotos, 15 dias
UPDATE plans SET max_stored_photos = 10, photo_expiration_days = 15
WHERE name ILIKE '%basic%' OR name = 'Basic';

-- Free: 5 fotos, 7 dias
UPDATE plans SET max_stored_photos = 5, photo_expiration_days = 7
WHERE name ILIKE '%free%' OR name = 'Free';
