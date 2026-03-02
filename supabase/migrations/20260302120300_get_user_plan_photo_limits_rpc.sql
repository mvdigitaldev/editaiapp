-- =============================================================================
-- RPC para frontend obter limites de fotos e contagem atual
-- =============================================================================

CREATE OR REPLACE FUNCTION get_user_plan_photo_limits(p_user_id uuid)
RETURNS TABLE(max_photos int, stored_photos_count bigint) AS $$
  SELECT
    COALESCE(p.max_stored_photos, 10),
    (SELECT count(*) FROM edits e
     WHERE e.user_id = p_user_id
       AND e.status = 'completed'
       AND e.image_url IS NOT NULL
       AND (e.expires_at IS NULL OR e.expires_at > now()))
  FROM users u
  LEFT JOIN plans p ON p.id = u.current_plan_id
  WHERE u.id = p_user_id
    AND auth.uid() = p_user_id;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_user_plan_photo_limits(uuid) IS 'Retorna max_photos e stored_photos_count para o frontend';

GRANT EXECUTE ON FUNCTION get_user_plan_photo_limits(uuid) TO authenticated;
