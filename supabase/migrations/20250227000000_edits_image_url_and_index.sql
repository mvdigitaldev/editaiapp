-- Garantir coluna image_url em edits (URL pública da imagem gerada)
ALTER TABLE public.edits ADD COLUMN IF NOT EXISTS image_url text;

COMMENT ON COLUMN public.edits.image_url IS 'URL pública da imagem gerada (preenchida ao concluir a edição).';

-- Índice composto para paginação da galeria: usuário + created_at DESC
CREATE INDEX IF NOT EXISTS idx_edits_user_created ON public.edits (user_id, created_at DESC);
