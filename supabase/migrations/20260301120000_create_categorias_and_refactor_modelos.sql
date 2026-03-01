-- =============================================================================
-- Tabela categorias + refatorar modelos (categoria_id FK, thumbnail_url)
-- =============================================================================

-- 1) Criar tabela categorias
CREATE TABLE IF NOT EXISTS public.categorias (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  slug text NOT NULL UNIQUE,
  ordem int NOT NULL DEFAULT 0,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.categorias IS 'Categorias de modelos de edição (carros, moda, comida, etc.)';

CREATE INDEX IF NOT EXISTS idx_categorias_ativo ON public.categorias (ativo) WHERE ativo = true;

ALTER TABLE public.categorias ENABLE ROW LEVEL SECURITY;

CREATE POLICY "categorias_select_authenticated" ON public.categorias
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- 2) Seed de categorias ( slugs devem coincidir com valores atuais em modelos.categoria )
INSERT INTO public.categorias (nome, slug, ordem) VALUES
  ('Carros', 'carros', 10),
  ('Moda', 'roupas', 20),
  ('Comida', 'comida', 30),
  ('Joias', 'joias', 40),
  ('Objetos', 'objetos', 50),
  ('Outros', 'outros', 60)
ON CONFLICT (slug) DO NOTHING;

-- 3) Adicionar colunas em modelos
ALTER TABLE public.modelos ADD COLUMN IF NOT EXISTS categoria_id uuid REFERENCES public.categorias(id);
ALTER TABLE public.modelos ADD COLUMN IF NOT EXISTS thumbnail_url text;

COMMENT ON COLUMN public.modelos.thumbnail_url IS 'URL da thumbnail para exibição; inserida manualmente no banco';

-- 4) Migrar dados: preencher categoria_id a partir de categoria
UPDATE public.modelos m
SET categoria_id = (SELECT c.id FROM public.categorias c WHERE c.slug = m.categoria)
WHERE m.categoria IS NOT NULL AND m.categoria_id IS NULL;

-- 5) Tornar categoria_id NOT NULL e remover coluna categoria
ALTER TABLE public.modelos ALTER COLUMN categoria_id SET NOT NULL;
ALTER TABLE public.modelos DROP COLUMN IF EXISTS categoria;

-- 6) Índice para busca por categoria
CREATE INDEX IF NOT EXISTS idx_modelos_categoria_id ON public.modelos (categoria_id);
