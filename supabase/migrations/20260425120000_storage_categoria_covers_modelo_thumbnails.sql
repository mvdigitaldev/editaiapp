-- Buckets públicos para capas de categorias e thumbnails de modelos (URLs em cover_image_url / thumbnail_url).
-- Upload apenas para usuários com role admin em public.users.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'categoria-covers',
  'categoria-covers',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'modelo-thumbnails',
  'modelo-thumbnails',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- categoria-covers: leitura pública; escrita só admin
CREATE POLICY "categoria_covers_select_public"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'categoria-covers');

CREATE POLICY "categoria_covers_insert_admin"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'categoria-covers'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
);

CREATE POLICY "categoria_covers_update_admin"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'categoria-covers'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
)
WITH CHECK (
  bucket_id = 'categoria-covers'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
);

CREATE POLICY "categoria_covers_delete_admin"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'categoria-covers'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
);

-- modelo-thumbnails: leitura pública; escrita só admin
CREATE POLICY "modelo_thumbnails_select_public"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'modelo-thumbnails');

CREATE POLICY "modelo_thumbnails_insert_admin"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'modelo-thumbnails'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
);

CREATE POLICY "modelo_thumbnails_update_admin"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'modelo-thumbnails'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
)
WITH CHECK (
  bucket_id = 'modelo-thumbnails'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
);

CREATE POLICY "modelo_thumbnails_delete_admin"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'modelo-thumbnails'
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'::public.user_role
  )
);
