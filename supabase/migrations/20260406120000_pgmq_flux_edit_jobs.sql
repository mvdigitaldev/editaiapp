-- pgmq extension e fila flux-edit-jobs para processamento assíncrono de edições multi-imagem.
-- Wrappers em public para Edge Functions chamarem via RPC.

CREATE EXTENSION IF NOT EXISTS pgmq;

SELECT pgmq.create('flux-edit-jobs');

-- Enfileirar job (chamado pela função de entrada)
CREATE OR REPLACE FUNCTION public.enqueue_flux_edit_job(p_msg jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pgmq
AS $$
DECLARE
  v_msg_id bigint;
BEGIN
  FOR v_msg_id IN SELECT pgmq.send('flux-edit-jobs', p_msg) LIMIT 1
  LOOP
    RETURN v_msg_id;
  END LOOP;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.enqueue_flux_edit_job(jsonb) IS 'Enfileira job de edição multi-imagem. Chamado pela função de entrada.';

-- Ler uma mensagem (chamado pelo worker)
CREATE OR REPLACE FUNCTION public.read_flux_edit_job()
RETURNS TABLE(msg_id bigint, read_ct bigint, message jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pgmq
AS $$
  SELECT m.msg_id, m.read_ct, m.message
  FROM pgmq.read('flux-edit-jobs', 300, 1) m
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.read_flux_edit_job() IS 'Lê uma mensagem da fila flux-edit-jobs (VT=300s). Worker usa para processar.';

-- Deletar mensagem após processamento bem-sucedido
CREATE OR REPLACE FUNCTION public.delete_flux_edit_message(p_msg_id bigint)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pgmq
AS $$
  SELECT pgmq.delete('flux-edit-jobs', p_msg_id);
$$;

-- Arquivar mensagem (dead letter quando read_ct > 3)
CREATE OR REPLACE FUNCTION public.archive_flux_edit_message(p_msg_id bigint)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pgmq
AS $$
  SELECT pgmq.archive('flux-edit-jobs', p_msg_id);
$$;

-- Métricas da fila (opcional, para monitoramento)
CREATE OR REPLACE FUNCTION public.flux_edit_queue_metrics()
RETURNS TABLE(queue_length bigint, oldest_msg_age_sec integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pgmq
AS $$
  SELECT m.queue_length, m.oldest_msg_age_sec
  FROM pgmq.metrics('flux-edit-jobs') m;
$$;

GRANT EXECUTE ON FUNCTION public.enqueue_flux_edit_job(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_flux_edit_job() TO service_role;
GRANT EXECUTE ON FUNCTION public.delete_flux_edit_message(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.archive_flux_edit_message(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.flux_edit_queue_metrics() TO service_role;
