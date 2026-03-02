-- =============================================================================
-- Expiração automática de edits via pg_cron
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Função de limpeza (batch de 500 para não travar)
CREATE OR REPLACE FUNCTION cleanup_expired_edits()
RETURNS int AS $$
DECLARE deleted_count int;
BEGIN
  WITH expired AS (
    SELECT id FROM edits
    WHERE expires_at IS NOT NULL AND expires_at < now()
    LIMIT 500
  )
  DELETE FROM edits WHERE id IN (SELECT id FROM expired);
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION cleanup_expired_edits() IS 'Remove edits expirados (expires_at < now). Executa em batch de 500.';

-- Agendar diariamente às 3h UTC
SELECT cron.schedule(
  'cleanup-expired-edits',
  '0 3 * * *',
  $$SELECT cleanup_expired_edits()$$
);
