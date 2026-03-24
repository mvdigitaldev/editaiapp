-- URL pública da imagem de capa do card de categoria na listagem Modelos (app).

ALTER TABLE public.categorias
  ADD COLUMN IF NOT EXISTS cover_image_url text;

COMMENT ON COLUMN public.categorias.cover_image_url IS
  'URL HTTPS pública da imagem de fundo do card na lista de categorias (ex.: Storage público ou CDN).';
