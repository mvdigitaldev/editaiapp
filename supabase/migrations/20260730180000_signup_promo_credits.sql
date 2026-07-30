-- Promoção: contas criadas até 07/08/2026 (America/Sao_Paulo, dia inclusivo)
-- recebem créditos de bônus configuráveis via app_settings.

-- ---------------------------------------------------------------------------
-- 1) Config da promoção (alterável sem redeploy)
-- ---------------------------------------------------------------------------
INSERT INTO public.app_settings (setting_key, setting_value) VALUES
  ('signup_promo_enabled', 'true'),
  ('signup_promo_credits', '50'),
  -- Fim do dia 07/08/2026 em America/Sao_Paulo (= 2026-08-08 02:59:59.999 UTC)
  ('signup_promo_ends_at', '2026-08-08T02:59:59.999Z')
ON CONFLICT (setting_key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2) Concede créditos de promoção de cadastro (idempotente)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.grant_signup_promo_credits(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled text;
  v_credits_raw text;
  v_ends_at_raw text;
  v_credits int;
  v_ends_at timestamptz;
  v_user_created_at timestamptz;
BEGIN
  SELECT setting_value INTO v_enabled
  FROM public.app_settings
  WHERE setting_key = 'signup_promo_enabled';

  SELECT setting_value INTO v_credits_raw
  FROM public.app_settings
  WHERE setting_key = 'signup_promo_credits';

  SELECT setting_value INTO v_ends_at_raw
  FROM public.app_settings
  WHERE setting_key = 'signup_promo_ends_at';

  IF v_enabled IS DISTINCT FROM 'true' THEN
    RETURN;
  END IF;

  IF v_credits_raw IS NULL OR v_ends_at_raw IS NULL THEN
    RETURN;
  END IF;

  BEGIN
    v_credits := v_credits_raw::int;
    v_ends_at := v_ends_at_raw::timestamptz;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'grant_signup_promo_credits: config inválida (% / %)', v_credits_raw, v_ends_at_raw;
      RETURN;
  END;

  IF v_credits IS NULL OR v_credits <= 0 THEN
    RETURN;
  END IF;

  IF now() > v_ends_at THEN
    RETURN;
  END IF;

  SELECT created_at INTO v_user_created_at
  FROM public.users
  WHERE id = p_user_id;

  IF v_user_created_at IS NULL OR v_user_created_at > v_ends_at THEN
    RETURN;
  END IF;

  -- Idempotência: já recebeu este bônus
  IF EXISTS (
    SELECT 1
    FROM public.credit_transactions
    WHERE user_id = p_user_id
      AND type = 'bonus'
      AND description = 'signup_promo_credits'
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.credit_transactions (user_id, type, amount, description)
  VALUES (p_user_id, 'bonus', v_credits, 'signup_promo_credits');
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'grant_signup_promo_credits error for %: %', p_user_id, SQLERRM;
END;
$$;

COMMENT ON FUNCTION public.grant_signup_promo_credits(uuid) IS
  'Concede créditos de promoção de cadastro (app_settings signup_promo_*). Idempotente; uso interno via handle_new_user/backfill.';

REVOKE ALL ON FUNCTION public.grant_signup_promo_credits(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.grant_signup_promo_credits(uuid) FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Integrar no signup (handle_new_user)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  free_plan_id uuid;
  new_referral_code text;
  user_name text;
BEGIN
  -- Nome: prioridade name > full_name > display_name (metadata do Supabase Auth)
  user_name := COALESCE(
    NEW.raw_user_meta_data->>'name',
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'display_name'
  );

  new_referral_code := 'ref_' || substr(replace(NEW.id::text, '-', ''), 1, 10);
  WHILE EXISTS (SELECT 1 FROM users WHERE referral_code = new_referral_code) LOOP
    new_referral_code := 'ref_' || substr(md5(random()::text), 1, 10);
  END LOOP;

  SELECT id INTO free_plan_id FROM plans WHERE name ILIKE 'free' LIMIT 1;
  IF free_plan_id IS NULL THEN
    INSERT INTO plans (name, description, monthly_price, yearly_price, features)
    VALUES ('Free', 'Plano gratuito com créditos limitados', 0, 0, '[]')
    RETURNING id INTO free_plan_id;
  END IF;

  INSERT INTO public.users (id, email, name, role, referral_code, current_plan_id, subscription_status, trial_ends_at)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    user_name,
    'user',
    new_referral_code,
    free_plan_id,
    'trial',
    now() + interval '7 days'
  )
  ON CONFLICT (id) DO UPDATE SET
    email = COALESCE(EXCLUDED.email, users.email),
    name = COALESCE(EXCLUDED.name, users.name),
    updated_at = now();

  PERFORM public.grant_signup_promo_credits(NEW.id);

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'handle_new_user error: %', SQLERRM;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Cria registro em public.users ao cadastrar via Supabase Auth. Preenche name a partir de user_metadata e concede créditos da promoção de cadastro quando elegível.';
