-- =============================================================================
-- Arquitetura de créditos: deduct, refund, edits estendido, flux_tasks.edit_id
-- Fonte única: users.credits_balance (atualizado via trigger de credit_transactions)
-- =============================================================================

-- 1) Função: desconto atômico de créditos (SELECT FOR UPDATE evita race condition)
CREATE OR REPLACE FUNCTION public.deduct_credits_for_operation(
  p_user_id uuid,
  p_credits int,
  p_description text DEFAULT 'usage',
  p_reference_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance int;
  v_tx_id uuid;
BEGIN
  IF p_credits <= 0 THEN
    RAISE EXCEPTION 'deduct_credits: p_credits must be positive';
  END IF;

  SELECT credits_balance INTO v_balance
  FROM users
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_not_found';
  END IF;

  IF v_balance < p_credits THEN
    RAISE EXCEPTION 'insufficient_credits' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO credit_transactions (user_id, type, amount, description, reference_id)
  VALUES (p_user_id, 'usage', -p_credits, p_description, p_reference_id)
  RETURNING id INTO v_tx_id;

  RETURN v_tx_id;
END;
$$;

COMMENT ON FUNCTION public.deduct_credits_for_operation IS 'Desconto atômico de créditos. Levanta insufficient_credits se saldo insuficiente.';

-- 2) Função: reembolso de créditos (falha na operação)
CREATE OR REPLACE FUNCTION public.refund_credits_for_edit(
  p_user_id uuid,
  p_credits int,
  p_edit_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_credits <= 0 THEN
    RAISE EXCEPTION 'refund_credits: p_credits must be positive';
  END IF;

  INSERT INTO credit_transactions (user_id, type, amount, description, reference_id)
  VALUES (p_user_id, 'usage', p_credits, 'Refund for failed edit', p_edit_id);
END;
$$;

COMMENT ON FUNCTION public.refund_credits_for_edit IS 'Reembolso de créditos quando a operação falha.';

-- 3) Estender edits: image_id nullable, operation_type, task_id
ALTER TABLE edits ALTER COLUMN image_id DROP NOT NULL;
ALTER TABLE edits ALTER COLUMN prompt_text DROP NOT NULL;

ALTER TABLE edits ADD COLUMN IF NOT EXISTS operation_type text;
ALTER TABLE edits ADD COLUMN IF NOT EXISTS task_id text;

COMMENT ON COLUMN edits.operation_type IS 'text_to_image, edit_image, remove_background, multi_image';
COMMENT ON COLUMN edits.task_id IS 'task_id da flux_tasks para vincular resultado assíncrono';

-- Valores default para enums quando não aplicável
ALTER TABLE edits ALTER COLUMN edit_category SET DEFAULT 'other';
ALTER TABLE edits ALTER COLUMN edit_goal SET DEFAULT 'enhance_details';
ALTER TABLE edits ALTER COLUMN desired_style SET DEFAULT 'natural';

-- 4) flux_tasks: adicionar edit_id
ALTER TABLE flux_tasks ADD COLUMN IF NOT EXISTS edit_id uuid REFERENCES edits(id);

COMMENT ON COLUMN flux_tasks.edit_id IS 'Vínculo com edits para auditoria de créditos.';

-- Grant para Edge Functions (service_role)
GRANT EXECUTE ON FUNCTION public.deduct_credits_for_operation(uuid, int, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.refund_credits_for_edit(uuid, int, uuid) TO service_role;
