-- Adicionar coluna original_image_url em edits para persistir a imagem original (antes da edição).
-- Preenchida para edit_image, remove_background e edit_model. Usada no slider antes/depois.

ALTER TABLE public.edits ADD COLUMN IF NOT EXISTS original_image_url text;
COMMENT ON COLUMN public.edits.original_image_url IS 'URL pública da imagem original (antes da edição). Preenchida para edit_image, remove_background e edit_model.';
