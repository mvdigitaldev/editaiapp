-- Função auxiliar para conceder créditos de assinatura com base no plano atual.
-- Pode ser chamada por webhooks de pagamento ou jobs agendados.

CREATE OR REPLACE FUNCTION public.grant_subscription_monthly_credits(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_plan_id uuid;
  v_monthly_credits int;
BEGIN
  SELECT current_plan_id
  INTO v_plan_id
  FROM public.users
  WHERE id = p_user_id;

  IF v_plan_id IS NULL THEN
    RAISE NOTICE 'grant_subscription_monthly_credits: user % has no current_plan_id', p_user_id;
    RETURN;
  END IF;

  SELECT monthly_credits
  INTO v_monthly_credits
  FROM public.plans
  WHERE id = v_plan_id;

  IF v_monthly_credits IS NULL OR v_monthly_credits <= 0 THEN
    RAISE NOTICE 'grant_subscription_monthly_credits: plan % has no monthly_credits configured', v_plan_id;
    RETURN;
  END IF;

  INSERT INTO public.credit_transactions (user_id, type, amount, description, reference_id)
  VALUES (
    p_user_id,
    'subscription_credit',
    v_monthly_credits,
    'Créditos mensais do plano de assinatura',
    v_plan_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.grant_subscription_monthly_credits(uuid) TO authenticated;

