-- =============================================================================
-- Tabela modelos: prompts prontos cadastrados no banco (editáveis sem deploy)
-- Usada pela página de Modelos e pela Edge Function editar-imagem-modelo
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.modelos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  descricao text,
  categoria text NOT NULL,
  prompt_padrao text NOT NULL,
  ativo boolean NOT NULL DEFAULT true,
  ordem int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.modelos IS 'Modelos de edição por nicho (carros, roupas, comida, etc.) com prompts dinâmicos';
COMMENT ON COLUMN public.modelos.prompt_padrao IS 'Prompt em inglês para FLUX, editável no banco sem alterar frontend';
COMMENT ON COLUMN public.modelos.categoria IS 'Nicho: carros, roupas, comida, joias, objetos, outros';

CREATE INDEX IF NOT EXISTS idx_modelos_ativo ON public.modelos (ativo) WHERE ativo = true;

ALTER TABLE public.modelos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "modelos_select_authenticated" ON public.modelos
  FOR SELECT USING (auth.uid() IS NOT NULL);
