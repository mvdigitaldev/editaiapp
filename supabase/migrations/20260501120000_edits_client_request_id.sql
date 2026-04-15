ALTER TABLE public.edits
  ADD COLUMN IF NOT EXISTS client_request_id text;

COMMENT ON COLUMN public.edits.client_request_id IS
  'Idempotency key supplied by the client for safe submit retries.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_edits_user_client_request_id
  ON public.edits (user_id, client_request_id)
  WHERE client_request_id IS NOT NULL;
