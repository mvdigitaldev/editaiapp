-- Adicionar metadata da imagem em edits (file_size, mime_type, width, height)
-- Preenchidos a partir da imagem relacionada (images) ou dos dados da requisição
ALTER TABLE public.edits ADD COLUMN IF NOT EXISTS file_size bigint;
ALTER TABLE public.edits ADD COLUMN IF NOT EXISTS mime_type text;
ALTER TABLE public.edits ADD COLUMN IF NOT EXISTS width int;
ALTER TABLE public.edits ADD COLUMN IF NOT EXISTS height int;

COMMENT ON COLUMN public.edits.file_size IS 'Tamanho da imagem em bytes (fonte: images ou requisição)';
COMMENT ON COLUMN public.edits.mime_type IS 'Tipo MIME da imagem (fonte: images ou requisição)';
COMMENT ON COLUMN public.edits.width IS 'Largura da imagem em pixels (fonte: images ou requisição)';
COMMENT ON COLUMN public.edits.height IS 'Altura da imagem em pixels (fonte: images ou requisição)';
