-- Limite unificado de armazenamento: max_stored_photos conta todas as fotos
-- salvas (IA + manual). Não há limite separado por tipo de edição.

CREATE OR REPLACE FUNCTION get_user_plan_photo_limits(p_user_id uuid)
RETURNS TABLE(max_photos int, stored_photos_count bigint) AS $$
  SELECT
    COALESCE(p.max_stored_photos, 10),
    (
      SELECT count(*)
      FROM edits e
      WHERE e.user_id = p_user_id
        AND e.status = 'completed'
        AND e.image_url IS NOT NULL
        AND (e.expires_at IS NULL OR e.expires_at > now())
    )
  FROM users u
  LEFT JOIN plans p ON p.id = u.current_plan_id
  WHERE u.id = p_user_id
    AND auth.uid() = p_user_id;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_user_plan_photo_limits(uuid) IS
  'Limite de armazenamento do plano (todas as edições completed com image_url)';

GRANT EXECUTE ON FUNCTION get_user_plan_photo_limits(uuid) TO authenticated;
