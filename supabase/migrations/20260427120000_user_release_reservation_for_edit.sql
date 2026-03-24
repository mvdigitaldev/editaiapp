-- Permite ao app (authenticated) liberar a reserva de créditos da própria edição (ex.: timeout na tela de processamento).

CREATE OR REPLACE FUNCTION public.user_release_pending_reservation_for_edit(
  p_edit_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_res_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.edits e WHERE e.id = p_edit_id AND e.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'edit_not_found_or_forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT r.id
  INTO v_res_id
  FROM public.credit_reservations r
  WHERE r.edit_id = p_edit_id
    AND r.status = 'pending'
  ORDER BY r.created_at DESC
  LIMIT 1;

  IF v_res_id IS NOT NULL THEN
    PERFORM public.release_credit_reservation(
      v_res_id,
      COALESCE(NULLIF(btrim(p_reason), ''), 'client_processing_timeout')
    );
  END IF;
END;
$$;

COMMENT ON FUNCTION public.user_release_pending_reservation_for_edit(uuid, text) IS
  'Libera reserva pendente de créditos para uma edição do usuário autenticado (sem consumir).';

GRANT EXECUTE ON FUNCTION public.user_release_pending_reservation_for_edit(uuid, text) TO authenticated;
