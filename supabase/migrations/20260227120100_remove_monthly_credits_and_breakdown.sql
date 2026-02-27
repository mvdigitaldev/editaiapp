-- =============================================================================
-- Limpeza: monthly_credits não utilizado; get_user_credits_breakdown obsoleto
-- Fonte única de saldo: users.credits_balance
-- =============================================================================

-- 1) Remover coluna monthly_credits de plans
ALTER TABLE plans DROP COLUMN IF EXISTS monthly_credits;

-- 2) Remover função get_user_credits_breakdown (obsoleta)
DROP FUNCTION IF EXISTS public.get_user_credits_breakdown();

-- 3) Remover grant_subscription_monthly_credits (dependia de monthly_credits)
DROP FUNCTION IF EXISTS public.grant_subscription_monthly_credits(uuid);
