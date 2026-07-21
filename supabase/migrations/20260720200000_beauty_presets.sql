-- Sprint 23/24 — Beauty presets cloud sync + marketplace público.

CREATE TABLE IF NOT EXISTS public.beauty_presets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL
    CONSTRAINT beauty_presets_user_id_fkey
    REFERENCES public.users(id) ON DELETE CASCADE,
  client_id text NOT NULL,
  name text NOT NULL,
  preset_json jsonb NOT NULL,
  is_public boolean NOT NULL DEFAULT false,
  thumbnail_url text,
  install_count integer NOT NULL DEFAULT 0 CHECK (install_count >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT beauty_presets_user_client_unique UNIQUE (user_id, client_id)
);

COMMENT ON TABLE public.beauty_presets IS
  'Presets de beauty do usuario; client_id mapeia o id local (user_*).';

CREATE INDEX IF NOT EXISTS idx_beauty_presets_user_updated
  ON public.beauty_presets (user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_beauty_presets_public_marketplace
  ON public.beauty_presets (updated_at DESC)
  WHERE is_public = true;

CREATE OR REPLACE FUNCTION public.set_beauty_presets_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS beauty_presets_updated_at ON public.beauty_presets;
CREATE TRIGGER beauty_presets_updated_at
BEFORE UPDATE ON public.beauty_presets
FOR EACH ROW
EXECUTE FUNCTION public.set_beauty_presets_updated_at();

ALTER TABLE public.beauty_presets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS beauty_presets_select_own ON public.beauty_presets;
DROP POLICY IF EXISTS beauty_presets_select_public ON public.beauty_presets;
DROP POLICY IF EXISTS beauty_presets_insert_own ON public.beauty_presets;
DROP POLICY IF EXISTS beauty_presets_update_own ON public.beauty_presets;
DROP POLICY IF EXISTS beauty_presets_delete_own ON public.beauty_presets;

CREATE POLICY beauty_presets_select_own
ON public.beauty_presets FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY beauty_presets_select_public
ON public.beauty_presets FOR SELECT
TO authenticated
USING (is_public = true);

CREATE POLICY beauty_presets_insert_own
ON public.beauty_presets FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY beauty_presets_update_own
ON public.beauty_presets FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY beauty_presets_delete_own
ON public.beauty_presets FOR DELETE
TO authenticated
USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.increment_beauty_preset_install_count(p_preset_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.beauty_presets
  SET install_count = install_count + 1
  WHERE id = p_preset_id
    AND is_public = true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_beauty_preset_install_count(uuid)
  TO authenticated;

CREATE OR REPLACE VIEW public.beauty_presets_marketplace AS
SELECT
  bp.id,
  bp.user_id AS author_id,
  COALESCE(NULLIF(btrim(u.name), ''), 'Usuário') AS author_name,
  bp.name,
  bp.preset_json,
  bp.thumbnail_url,
  bp.install_count,
  bp.updated_at
FROM public.beauty_presets bp
JOIN public.users u ON u.id = bp.user_id
WHERE bp.is_public = true;

COMMENT ON VIEW public.beauty_presets_marketplace IS
  'Presets publicos para browse/install no marketplace (Sprint 24).';

GRANT SELECT ON public.beauty_presets_marketplace TO authenticated;

-- Thumbnails de presets (público para marketplace; escrita apenas na pasta do dono).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'beauty-preset-thumbnails',
  'beauty-preset-thumbnails',
  true,
  524288,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS beauty_preset_thumbs_select_public ON storage.objects;
DROP POLICY IF EXISTS beauty_preset_thumbs_insert_own ON storage.objects;
DROP POLICY IF EXISTS beauty_preset_thumbs_update_own ON storage.objects;
DROP POLICY IF EXISTS beauty_preset_thumbs_delete_own ON storage.objects;

CREATE POLICY beauty_preset_thumbs_select_public
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'beauty-preset-thumbnails');

CREATE POLICY beauty_preset_thumbs_insert_own
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'beauty-preset-thumbnails'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY beauty_preset_thumbs_update_own
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'beauty-preset-thumbnails'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'beauty-preset-thumbnails'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY beauty_preset_thumbs_delete_own
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'beauty-preset-thumbnails'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
