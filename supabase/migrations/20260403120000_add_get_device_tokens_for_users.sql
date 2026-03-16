-- RPC para buscar device_tokens por lista de user_ids (evita limite de URL do PostgREST)
-- Uso: supabase.rpc('get_device_tokens_for_users', { user_ids: ['uuid1', 'uuid2', ...] })
-- O array vai no body da requisição, não na URL, evitando o erro "URI too long"
CREATE OR REPLACE FUNCTION get_device_tokens_for_users(user_ids uuid[])
RETURNS TABLE (token text, platform text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT dt.token, dt.platform
  FROM device_tokens dt
  WHERE dt.user_id = ANY(user_ids);
$$;

GRANT EXECUTE ON FUNCTION get_device_tokens_for_users(uuid[]) TO service_role;
GRANT EXECUTE ON FUNCTION get_device_tokens_for_users(uuid[]) TO authenticated;
