-- Garantir que o nome informado no cadastro (enviado como display_name nos user_metadata)
-- seja salvo na coluna name da tabela public.users.

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
    INSERT INTO plans (name, description, monthly_price, yearly_price, monthly_credits, features)
    VALUES ('Free', 'Plano gratuito com créditos limitados', 0, 0, 5, '[]')
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

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'handle_new_user error: %', SQLERRM;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user() IS 'Cria registro em public.users ao cadastrar via Supabase Auth. Preenche name a partir de user_metadata (name, full_name ou display_name).';
