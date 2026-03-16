-- RPC para retornar estatísticas de edições do usuário (admin)
CREATE OR REPLACE FUNCTION get_user_edit_stats(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total', COUNT(*),
    'completed', COUNT(*) FILTER (WHERE status = 'completed'),
    'failed', COUNT(*) FILTER (WHERE status = 'failed'),
    'credits_used', COALESCE(SUM(credits_used), 0),
    'last_activity', MAX(created_at),
    'by_operation', COALESCE((
      SELECT jsonb_object_agg(COALESCE(operation_type, 'unknown'), cnt)
      FROM (
        SELECT operation_type, COUNT(*)::int as cnt
        FROM edits WHERE user_id = p_user_id AND status = 'completed'
        GROUP BY operation_type
      ) t
    ), '{}'::jsonb),
    'by_category', COALESCE((
      SELECT jsonb_object_agg(edit_category, cnt)
      FROM (
        SELECT edit_category, COUNT(*)::int as cnt
        FROM edits WHERE user_id = p_user_id AND status = 'completed'
        GROUP BY edit_category
      ) t
    ), '{}'::jsonb),
    'by_goal', COALESCE((
      SELECT jsonb_object_agg(edit_goal, cnt)
      FROM (
        SELECT edit_goal, COUNT(*)::int as cnt
        FROM edits WHERE user_id = p_user_id AND status = 'completed'
        GROUP BY edit_goal
      ) t
    ), '{}'::jsonb)
  )
  INTO result
  FROM edits
  WHERE user_id = p_user_id;

  RETURN COALESCE(result, '{"total":0,"completed":0,"failed":0,"credits_used":0,"last_activity":null,"by_operation":{},"by_category":{},"by_goal":{}}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_edit_stats(uuid) TO service_role;
