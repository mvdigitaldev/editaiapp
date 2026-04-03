-- Modo de edição por categoria: fixed (prompt do modelo, um passo) vs guided (sugestões IA + montagem).
-- featured: destaque visual na lista de categorias do app.

ALTER TABLE public.categorias
  ADD COLUMN IF NOT EXISTS edit_mode text NOT NULL DEFAULT 'guided'
    CHECK (edit_mode IN ('fixed', 'guided'));

ALTER TABLE public.categorias
  ADD COLUMN IF NOT EXISTS featured boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.categorias.edit_mode IS 'fixed = edição direta com prompt_padrao do modelo; guided = fluxo com sugestões IA e texto do usuário.';
COMMENT ON COLUMN public.categorias.featured IS 'Destaque visual na tela inicial de Modelos (ex.: Retratos / Pessoa).';

-- Ajuste a slug conforme a categoria criada no seu projeto (ex.: após criar "Retratos / Pessoa" no admin).
UPDATE public.categorias
SET edit_mode = 'fixed',
    featured = true
WHERE slug = 'retratos-pessoa';
