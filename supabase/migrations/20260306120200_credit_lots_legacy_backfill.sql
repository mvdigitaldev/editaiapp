-- =============================================================================
-- Legacy backfill: preserve current balance as non-expiring lot.
-- =============================================================================

INSERT INTO public.credit_lots (
  user_id,
  source_transaction_id,
  source_type,
  original_amount,
  remaining_amount,
  granted_at,
  expires_at
)
SELECT
  u.id,
  NULL,
  'legacy_snapshot',
  u.credits_balance,
  u.credits_balance,
  now(),
  NULL
FROM public.users u
WHERE u.credits_balance > 0
  AND NOT EXISTS (
    SELECT 1
    FROM public.credit_lots l
    WHERE l.user_id = u.id
      AND l.source_type = 'legacy_snapshot'
      AND l.source_transaction_id IS NULL
  );
