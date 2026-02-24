-- Função para calcular saldo de créditos por tipo (plano vs extras),
-- usando apenas credit_transactions como fonte de verdade.
-- A função sempre consome créditos extras primeiro, depois créditos do plano.

CREATE OR REPLACE FUNCTION public.get_user_credits_breakdown()
RETURNS TABLE (
  plan_credits_remaining int,
  extra_credits_remaining int,
  total_balance int
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_plan_credits int := 0;
  v_extra_credits int := 0;
  v_to_consume int;
  v_from_extra int;
  v_from_plan int;
  rec record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'get_user_credits_breakdown: auth.uid() is null';
  END IF;

  FOR rec IN
    SELECT type, amount
    FROM public.credit_transactions
    WHERE user_id = v_user_id
    ORDER BY created_at ASC, id ASC
  LOOP
    IF rec.type = 'subscription_credit' THEN
      v_plan_credits := v_plan_credits + rec.amount;
    ELSIF rec.type IN ('extra_purchase', 'bonus', 'referral_bonus') THEN
      v_extra_credits := v_extra_credits + rec.amount;
    ELSIF rec.type = 'usage' THEN
      v_to_consume := -rec.amount;

      IF v_to_consume > 0 THEN
        v_from_extra := LEAST(v_extra_credits, v_to_consume);
        v_extra_credits := v_extra_credits - v_from_extra;
        v_to_consume := v_to_consume - v_from_extra;

        IF v_to_consume > 0 THEN
          v_from_plan := LEAST(v_plan_credits, v_to_consume);
          v_plan_credits := v_plan_credits - v_from_plan;
          v_to_consume := v_to_consume - v_from_plan;
        END IF;
      END IF;
    END IF;
  END LOOP;

  plan_credits_remaining := GREATEST(v_plan_credits, 0);
  extra_credits_remaining := GREATEST(v_extra_credits, 0);
  total_balance := plan_credits_remaining + extra_credits_remaining;

  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_credits_breakdown() TO authenticated, anon;

CREATE INDEX IF NOT EXISTS credit_transactions_user_created_at_idx
  ON public.credit_transactions (user_id, created_at);

