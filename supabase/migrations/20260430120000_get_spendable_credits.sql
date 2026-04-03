-- Créditos disponíveis para nova reserva (mesma lógica que reserve_credits_for_operation).
-- users.credits_balance pode divergir dos lots + reservas pendentes.

CREATE OR REPLACE FUNCTION public.get_spendable_credits()
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_available int := 0;
  v_reserved int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(SUM(remaining_amount), 0)::int
  INTO v_available
  FROM public.credit_lots
  WHERE user_id = v_uid
    AND remaining_amount > 0
    AND (expires_at IS NULL OR expires_at > now());

  SELECT COALESCE(SUM(credits), 0)::int
  INTO v_reserved
  FROM public.credit_reservations
  WHERE user_id = v_uid
    AND status = 'pending'
    AND reserved_until > now();

  RETURN GREATEST(v_available - v_reserved, 0);
END;
$$;

COMMENT ON FUNCTION public.get_spendable_credits() IS
  'Saldo utilizável para reservar créditos (lots ativos menos reservas pendentes).';

GRANT EXECUTE ON FUNCTION public.get_spendable_credits() TO authenticated;
