-- Bucket edit-inputs para imagens de entrada antes do processamento (Storage-first).
-- Path: {user_id}/inputs/{uuid}.jpg
-- Lifecycle: 12h (configurar no Dashboard ou via API)
-- Índice para limite de jobs por usuário e coluna started_at em edits.

-- =============================================================================
-- 1. BUCKET edit-inputs
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'edit-inputs',
  'edit-inputs',
  false,
  2097152,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Política: usuário autenticado pode fazer upload apenas no próprio folder
CREATE POLICY "edit_inputs_insert_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'edit-inputs'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Política: usuário pode ler apenas os próprios arquivos
CREATE POLICY "edit_inputs_select_own"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'edit-inputs'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Política: service_role pode ler tudo (worker)
CREATE POLICY "edit_inputs_select_service_role"
ON storage.objects FOR SELECT
TO service_role
USING (bucket_id = 'edit-inputs');

-- Política: usuário pode deletar apenas os próprios arquivos
CREATE POLICY "edit_inputs_delete_own"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'edit-inputs'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- =============================================================================
-- 2. COLUNA started_at EM edits (para métricas e idempotência)
-- =============================================================================

ALTER TABLE public.edits ADD COLUMN IF NOT EXISTS started_at timestamptz;
COMMENT ON COLUMN public.edits.started_at IS 'Quando o worker começou a processar (status=processing)';

-- =============================================================================
-- 3. ÍNDICE PARA LIMITE DE JOBS POR USUÁRIO
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_edits_user_status_created
ON public.edits (user_id, status, created_at)
WHERE status IN ('queued', 'processing');

COMMENT ON INDEX idx_edits_user_status_created IS 'Acelera contagem de jobs ativos (queued/processing) por usuário para limite de concorrência';
