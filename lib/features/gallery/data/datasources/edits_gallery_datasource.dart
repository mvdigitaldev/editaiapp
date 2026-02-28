import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/gallery_edit_model.dart';

abstract class EditsGalleryDataSource {
  Future<List<GalleryEditModel>> getEditsForGallery({
    int offset = 0,
    int limit = 20,
  });
}

class EditsGalleryDataSourceImpl implements EditsGalleryDataSource {
  final SupabaseClient _supabase;

  EditsGalleryDataSourceImpl(this._supabase);

  @override
  Future<List<GalleryEditModel>> getEditsForGallery({
    int offset = 0,
    int limit = 20,
  }) async {
    final response = await _supabase
        .from('edits')
        .select('id, image_url, created_at, status, operation_type')
        .not('image_url', 'is', null)
        .eq('status', 'completed')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((json) => GalleryEditModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
