-- Reverte descricoes para ingles no banco; traducao fica apenas na UI.

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
  VALUES (
    v_res.user_id,
    'usage',
    -v_res.credits,
    COALESCE(NULLIF(btrim(p_description), ''), 'usage'),
    p_reference_id
  )
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

-- Reverte dados ja traduzidos para ingles no banco.
UPDATE public.credit_transactions
SET description = 'usage'
WHERE type = 'usage'
  AND lower(COALESCE(description, '')) IN ('uso em edicao', 'uso em edição');

UPDATE public.credit_transactions
SET description = 'Expired unused credits'
WHERE type = 'credit_expiration'
  AND lower(COALESCE(description, '')) LIKE 'creditos expirados nao utilizados%';
