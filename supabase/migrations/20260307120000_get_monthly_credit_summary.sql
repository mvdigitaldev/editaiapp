-- Resumo mensal de creditos com fronteira de mes por timezone (padrao: America/Sao_Paulo)

CREATE OR REPLACE FUNCTION public.get_monthly_credit_summary(
  p_year int,
  p_month int,
  p_tz text DEFAULT 'America/Sao_Paulo'
)
RETURNS TABLE (
  total_in int,
  total_out int,
  net_total int,
  usage_out int,
  tx_count int
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_month_start_utc timestamptz;
  v_month_end_utc timestamptz;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN QUERY SELECT 0, 0, 0, 0, 0;
    RETURN;
  END IF;

  IF p_month < 1 OR p_month > 12 THEN
    RAISE EXCEPTION 'p_month must be between 1 and 12';
  END IF;

  v_month_start_utc := make_timestamptz(p_year, p_month, 1, 0, 0, 0, p_tz);
  v_month_end_utc := v_month_start_utc + interval '1 month';

  RETURN QUERY
  SELECT
    COALESCE(SUM(CASE WHEN ct.amount > 0 THEN ct.amount ELSE 0 END), 0)::int AS total_in,
    COALESCE(ABS(SUM(CASE WHEN ct.amount < 0 THEN ct.amount ELSE 0 END)), 0)::int AS total_out,
    COALESCE(SUM(ct.amount), 0)::int AS net_total,
    COALESCE(ABS(SUM(CASE WHEN ct.type = 'usage' AND ct.amount < 0 THEN ct.amount ELSE 0 END)), 0)::int AS usage_out,
    COUNT(*)::int AS tx_count
  FROM public.credit_transactions ct
  WHERE ct.user_id = v_uid
    AND ct.created_at >= v_month_start_utc
    AND ct.created_at < v_month_end_utc;
END;
$$;

COMMENT ON FUNCTION public.get_monthly_credit_summary(int, int, text) IS
  'Retorna resumo mensal de entradas/saidas de creditos para auth.uid(), com fronteira de mes no timezone informado.';

REVOKE ALL ON FUNCTION public.get_monthly_credit_summary(int, int, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_monthly_credit_summary(int, int, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_monthly_credit_summary(int, int, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_monthly_credit_summary(int, int, text) TO service_role;
