-- =============================================================================
-- Reservation-based credit charging and lot expiration RPCs.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reserve_credits_for_operation(
  p_user_id uuid,
  p_credits int,
  p_operation_type text,
  p_edit_id uuid,
  p_ttl_seconds int DEFAULT 900
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_available int := 0;
  v_reserved int := 0;
  v_reservation_id uuid;
  v_ttl_seconds int := GREATEST(COALESCE(p_ttl_seconds, 900), 1);
BEGIN
  IF p_credits <= 0 THEN
    RAISE EXCEPTION 'reserve_credits: p_credits must be positive';
  END IF;

  IF p_operation_type IS NULL OR btrim(p_operation_type) = '' THEN
    RAISE EXCEPTION 'reserve_credits: p_operation_type is required';
  END IF;

  PERFORM 1
  FROM public.users
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_not_found';
  END IF;

  -- Expire stale reservations for this user before availability check.
  UPDATE public.credit_reservations
  SET
    status = 'expired',
    failure_reason = COALESCE(failure_reason, 'reservation_ttl_expired'),
    updated_at = now()
  WHERE user_id = p_user_id
    AND status = 'pending'
    AND reserved_until <= now();

  -- Lock active lots for deterministic availability under concurrency.
  PERFORM 1
  FROM public.credit_lots
  WHERE user_id = p_user_id
    AND remaining_amount > 0
    AND (expires_at IS NULL OR expires_at > now())
  FOR UPDATE;

  SELECT COALESCE(SUM(remaining_amount), 0)::int
  INTO v_available
  FROM public.credit_lots
  WHERE user_id = p_user_id
    AND remaining_amount > 0
    AND (expires_at IS NULL OR expires_at > now());

  SELECT COALESCE(SUM(credits), 0)::int
  INTO v_reserved
  FROM public.credit_reservations
  WHERE user_id = p_user_id
    AND status = 'pending'
    AND reserved_until > now();

  IF v_available - v_reserved < p_credits THEN
    RAISE EXCEPTION 'insufficient_credits' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.credit_reservations (
    user_id,
    operation_type,
    edit_id,
    credits,
    status,
    reserved_until
  )
  VALUES (
    p_user_id,
    p_operation_type,
    p_edit_id,
    p_credits,
    'pending',
    now() + make_interval(secs => v_ttl_seconds)
  )
  RETURNING id INTO v_reservation_id;

  RETURN v_reservation_id;
END;
$$;

COMMENT ON FUNCTION public.reserve_credits_for_operation(uuid, int, text, uuid, int) IS
  'Reserves credits atomically for an operation without creating a debit transaction yet.';

CREATE OR REPLACE FUNCTION public.consume_reserved_credits(
  p_reservation_id uuid,
  p_reference_id uuid,
  p_description text DEFAULT 'usage'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res public.credit_reservations%ROWTYPE;
  v_lot record;
  v_to_consume int;
  v_take int;
  v_usage_tx_id uuid;
BEGIN
  SELECT *
  INTO v_res
  FROM public.credit_reservations
  WHERE id = p_reservation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reservation_not_found';
  END IF;

  IF v_res.status = 'consumed' THEN
    RETURN v_res.usage_transaction_id;
  END IF;

  IF v_res.status <> 'pending' THEN
    RAISE EXCEPTION 'reservation_not_pending';
  END IF;

  IF v_res.reserved_until <= now() THEN
    UPDATE public.credit_reservations
    SET
      status = 'expired',
      failure_reason = COALESCE(failure_reason, 'reservation_ttl_expired'),
      updated_at = now()
    WHERE id = v_res.id;
    RAISE EXCEPTION 'reservation_expired' USING ERRCODE = 'P0001';
  END IF;

  PERFORM 1
  FROM public.users
  WHERE id = v_res.user_id
  FOR UPDATE;

  v_to_consume := v_res.credits;

  FOR v_lot IN
    SELECT id, remaining_amount
    FROM public.credit_lots
    WHERE user_id = v_res.user_id
      AND remaining_amount > 0
      AND (expires_at IS NULL OR expires_at > now())
    ORDER BY expires_at ASC NULLS LAST, granted_at ASC, created_at ASC
    FOR UPDATE
  LOOP
    EXIT WHEN v_to_consume = 0;

    v_take := LEAST(v_lot.remaining_amount, v_to_consume);

    UPDATE public.credit_lots
    SET
      remaining_amount = remaining_amount - v_take,
      updated_at = now()
    WHERE id = v_lot.id;

    v_to_consume := v_to_consume - v_take;
  END LOOP;

  IF v_to_consume > 0 THEN
    UPDATE public.credit_reservations
    SET
      status = 'expired',
      failure_reason = 'reserved_credits_unavailable',
      updated_at = now()
    WHERE id = v_res.id;
    RAISE EXCEPTION 'insufficient_credits' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.credit_transactions (user_id, type, amount, description, reference_id)
  VALUES (v_res.user_id, 'usage', -v_res.credits, COALESCE(p_description, 'usage'), p_reference_id)
  RETURNING id INTO v_usage_tx_id;

  UPDATE public.credit_reservations
  SET
    status = 'consumed',
    usage_transaction_id = v_usage_tx_id,
    updated_at = now()
  WHERE id = v_res.id;

  RETURN v_usage_tx_id;
END;
$$;

COMMENT ON FUNCTION public.consume_reserved_credits(uuid, uuid, text) IS
  'Consumes a pending reservation and creates one usage debit transaction.';

CREATE OR REPLACE FUNCTION public.release_credit_reservation(
  p_reservation_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_res public.credit_reservations%ROWTYPE;
BEGIN
  SELECT *
  INTO v_res
  FROM public.credit_reservations
  WHERE id = p_reservation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reservation_not_found';
  END IF;

  IF v_res.status = 'pending' THEN
    UPDATE public.credit_reservations
    SET
      status = CASE WHEN v_res.reserved_until <= now() THEN 'expired' ELSE 'released' END,
      failure_reason = COALESCE(
        p_reason,
        CASE WHEN v_res.reserved_until <= now() THEN 'reservation_ttl_expired' ELSE 'released_by_handler' END
      ),
      updated_at = now()
    WHERE id = v_res.id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.release_credit_reservation(uuid, text) IS
  'Releases a pending reservation with no debit transaction.';

CREATE OR REPLACE FUNCTION public.expire_credit_lots(p_limit int DEFAULT 2000)
RETURNS TABLE(expired_lots int, expired_credits int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_limit int := GREATEST(COALESCE(p_limit, 2000), 1);
  v_expired_lots int := 0;
  v_expired_credits int := 0;
BEGIN
  FOR v_row IN
    SELECT l.id, l.user_id, l.remaining_amount
    FROM public.credit_lots l
    WHERE l.remaining_amount > 0
      AND l.expires_at IS NOT NULL
      AND l.expires_at <= now()
      AND NOT EXISTS (
        SELECT 1
        FROM public.credit_reservations r
        WHERE r.user_id = l.user_id
          AND r.status = 'pending'
          AND r.reserved_until > now()
      )
    ORDER BY l.expires_at ASC, l.created_at ASC
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO public.credit_transactions (user_id, type, amount, description, reference_id)
    VALUES (
      v_row.user_id,
      'credit_expiration',
      -v_row.remaining_amount,
      'Expired unused credits',
      v_row.id
    );

    UPDATE public.credit_lots
    SET
      remaining_amount = 0,
      expired_at = COALESCE(expired_at, now()),
      updated_at = now()
    WHERE id = v_row.id;

    v_expired_lots := v_expired_lots + 1;
    v_expired_credits := v_expired_credits + v_row.remaining_amount;
  END LOOP;

  RETURN QUERY
  SELECT v_expired_lots, v_expired_credits;
END;
$$;

COMMENT ON FUNCTION public.expire_credit_lots(int) IS
  'Expires remaining balances from due lots and records debit transactions.';

CREATE OR REPLACE FUNCTION public.cleanup_stale_credit_reservations(p_limit int DEFAULT 5000)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit int := GREATEST(COALESCE(p_limit, 5000), 1);
  v_count int := 0;
BEGIN
  WITH stale AS (
    SELECT id
    FROM public.credit_reservations
    WHERE status = 'pending'
      AND reserved_until <= now()
    ORDER BY reserved_until ASC
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.credit_reservations r
  SET
    status = 'expired',
    failure_reason = COALESCE(r.failure_reason, 'reservation_ttl_expired'),
    updated_at = now()
  WHERE r.id IN (SELECT id FROM stale);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.cleanup_stale_credit_reservations(int) IS
  'Marks stale pending reservations as expired.';

GRANT EXECUTE ON FUNCTION public.reserve_credits_for_operation(uuid, int, text, uuid, int) TO service_role;
GRANT EXECUTE ON FUNCTION public.consume_reserved_credits(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.release_credit_reservation(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.expire_credit_lots(int) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_stale_credit_reservations(int) TO service_role;

REVOKE EXECUTE ON FUNCTION public.deduct_credits_for_operation(uuid, int, text, uuid) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.refund_credits_for_edit(uuid, int, uuid) FROM service_role;
