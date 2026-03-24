-- Bucket público `thumbnail` para capas de categorias e thumbnails de modelos (admin grava via app).
-- Substitui / complementa buckets nomeados em migrations anteriores se o projeto usar só este nome.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'thumbnail',
  'thumbnail',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "thumbnail_select_public" ON storage.objects;
DROP POLICY IF EXISTS "thumbnail_insert_admin" ON storage.objects;
DROP POLICY IF EXISTS "thumbnail_update_admin" ON storage.objects;
DROP POLICY IF EXISTS "thumbnail_delete_admin" ON storage.objects;

CREATE POLICY "thumbnail_select_public"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'thumbnail');

CREATE POLICY "thumbnail_insert_admin"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'thumbnail'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
);

CREATE POLICY "thumbnail_update_admin"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'thumbnail'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
)
WITH CHECK (
  bucket_id = 'thumbnail'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
);

CREATE POLICY "thumbnail_delete_admin"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'thumbnail'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
);
