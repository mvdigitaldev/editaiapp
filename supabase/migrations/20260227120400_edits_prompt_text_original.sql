-- Adicionar coluna prompt_text_original em edits
-- Armazena o prompt original do usuário antes de qualquer otimização (ex: OpenAI)
ALTER TABLE public.edits ADD COLUMN IF NOT EXISTS prompt_text_original text;

COMMENT ON COLUMN public.edits.prompt_text_original IS 'Prompt original do usuário antes de otimização/expansão';
