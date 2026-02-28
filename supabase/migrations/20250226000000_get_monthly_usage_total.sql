-- Total de créditos gastos (uso) no mês para o usuário autenticado.
-- Uso: amount negativo + type = 'usage'.

CREATE OR REPLACE FUNCTION public.get_monthly_usage_total(p_year int, p_month int)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid;
  date_start timestamptz;
  date_end timestamptz;
  total int;
BEGIN
  uid := auth.uid();
  IF uid IS NULL THEN
    RETURN 0;
  END IF;

  date_start := date_trunc('month', make_date(p_year, p_month, 1)) AT TIME ZONE 'UTC';
  date_end   := date_start + interval '1 month';

  SELECT COALESCE(SUM(ABS(amount))::int, 0)
  INTO total
  FROM public.credit_transactions
  WHERE user_id = uid
    AND type = 'usage'
    AND amount < 0
    AND created_at >= date_start
    AND created_at < date_end;

  RETURN total;
END;
$$;

COMMENT ON FUNCTION public.get_monthly_usage_total(int, int) IS
  'Retorna o total de créditos gastos (usage) no mês para o usuário autenticado.';
