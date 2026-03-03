-- =============================================================================
-- Credit expiration base schema: plan field, lots, reservations, and triggers.
-- =============================================================================

-- 1) Plan-level credit expiration configuration.
ALTER TABLE public.plans
  ADD COLUMN IF NOT EXISTS credit_expiration_days int NOT NULL DEFAULT 30 CHECK (credit_expiration_days >= 1);

COMMENT ON COLUMN public.plans.credit_expiration_days IS
  'Days until expiration for newly granted positive credits.';

-- 2) Extend transaction type for automatic expiration debits.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'credit_transaction_type'
      AND e.enumlabel = 'credit_expiration'
  ) THEN
    ALTER TYPE public.credit_transaction_type ADD VALUE 'credit_expiration';
  END IF;
END;
$$;

-- 3) Track expiration directly on positive transactions.
ALTER TABLE public.credit_transactions
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

COMMENT ON COLUMN public.credit_transactions.expires_at IS
  'Expiration timestamp for positive credit entries. Null for debits.';

CREATE INDEX IF NOT EXISTS idx_credit_transactions_positive_expires_at
  ON public.credit_transactions (user_id, expires_at)
  WHERE amount > 0;

-- 4) Lots table: one row per credit grant source, with remaining amount.
CREATE TABLE IF NOT EXISTS public.credit_lots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  source_transaction_id uuid REFERENCES public.credit_transactions(id) ON DELETE SET NULL,
  source_type text NOT NULL,
  original_amount int NOT NULL CHECK (original_amount > 0),
  remaining_amount int NOT NULL CHECK (remaining_amount >= 0 AND remaining_amount <= original_amount),
  granted_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  expired_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.credit_lots IS
  'Credit lots created from positive entries. Remaining amount is consumed using FEFO.';
COMMENT ON COLUMN public.credit_lots.source_transaction_id IS
  'Transaction that originated this lot. Null only for legacy snapshot lots.';
COMMENT ON COLUMN public.credit_lots.expires_at IS
  'Expiration inherited from the originating positive transaction.';

CREATE INDEX IF NOT EXISTS idx_credit_lots_user_expires_at
  ON public.credit_lots (user_id, expires_at);

CREATE INDEX IF NOT EXISTS idx_credit_lots_available
  ON public.credit_lots (user_id, expires_at, granted_at)
  WHERE remaining_amount > 0;

CREATE UNIQUE INDEX IF NOT EXISTS uq_credit_lots_source_transaction
  ON public.credit_lots (source_transaction_id)
  WHERE source_transaction_id IS NOT NULL;

DROP TRIGGER IF EXISTS credit_lots_updated_at ON public.credit_lots;
CREATE TRIGGER credit_lots_updated_at
  BEFORE UPDATE ON public.credit_lots
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 5) Reservations table: protects against concurrent over-consumption.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'credit_reservation_status'
  ) THEN
    CREATE TYPE public.credit_reservation_status AS ENUM ('pending', 'consumed', 'released', 'expired');
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.credit_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  operation_type text NOT NULL,
  edit_id uuid REFERENCES public.edits(id) ON DELETE SET NULL,
  credits int NOT NULL CHECK (credits > 0),
  status public.credit_reservation_status NOT NULL DEFAULT 'pending',
  reserved_until timestamptz NOT NULL,
  usage_transaction_id uuid REFERENCES public.credit_transactions(id) ON DELETE SET NULL,
  failure_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.credit_reservations IS
  'Temporary credit reservations used to charge only after successful operation start.';

CREATE INDEX IF NOT EXISTS idx_credit_reservations_user_status_until
  ON public.credit_reservations (user_id, status, reserved_until);

CREATE INDEX IF NOT EXISTS idx_credit_reservations_edit_id
  ON public.credit_reservations (edit_id);

DROP TRIGGER IF EXISTS credit_reservations_updated_at ON public.credit_reservations;
CREATE TRIGGER credit_reservations_updated_at
  BEFORE UPDATE ON public.credit_reservations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.credit_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_reservations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'credit_lots'
      AND policyname = 'credit_lots_select_own'
  ) THEN
    CREATE POLICY credit_lots_select_own
      ON public.credit_lots
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'credit_reservations'
      AND policyname = 'credit_reservations_select_own'
  ) THEN
    CREATE POLICY credit_reservations_select_own
      ON public.credit_reservations
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END;
$$;

-- 6) Trigger functions on credit_transactions.
CREATE OR REPLACE FUNCTION public.set_credit_transaction_expires_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days int;
  v_base_ts timestamptz;
BEGIN
  IF NEW.amount > 0 THEN
    IF NEW.expires_at IS NULL THEN
      SELECT COALESCE(p.credit_expiration_days, 30)
      INTO v_days
      FROM public.users u
      LEFT JOIN public.plans p ON p.id = u.current_plan_id
      WHERE u.id = NEW.user_id;

      v_base_ts := COALESCE(NEW.created_at, now());
      NEW.expires_at := v_base_ts + make_interval(days => COALESCE(v_days, 30));
    END IF;
  ELSE
    NEW.expires_at := NULL;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_credit_transaction_expires_at() IS
  'Assigns expires_at for positive credit transactions based on user plan.';

CREATE OR REPLACE FUNCTION public.create_credit_lot_from_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.amount > 0 THEN
    INSERT INTO public.credit_lots (
      user_id,
      source_transaction_id,
      source_type,
      original_amount,
      remaining_amount,
      granted_at,
      expires_at
    )
    VALUES (
      NEW.user_id,
      NEW.id,
      NEW.type::text,
      NEW.amount,
      NEW.amount,
      COALESCE(NEW.created_at, now()),
      NEW.expires_at
    )
    ON CONFLICT (source_transaction_id) WHERE source_transaction_id IS NOT NULL
    DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.create_credit_lot_from_transaction() IS
  'Creates a credit lot for each positive transaction entry.';

DROP TRIGGER IF EXISTS credit_transactions_set_expires_at ON public.credit_transactions;
CREATE TRIGGER credit_transactions_set_expires_at
  BEFORE INSERT ON public.credit_transactions
  FOR EACH ROW EXECUTE FUNCTION public.set_credit_transaction_expires_at();

DROP TRIGGER IF EXISTS credit_transactions_create_credit_lot ON public.credit_transactions;
CREATE TRIGGER credit_transactions_create_credit_lot
  AFTER INSERT ON public.credit_transactions
  FOR EACH ROW EXECUTE FUNCTION public.create_credit_lot_from_transaction();
