import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/edit_detail_model.dart';
import '../models/gallery_edit_model.dart';

abstract class EditsGalleryDataSource {
  Future<List<GalleryEditModel>> getEditsForGallery({
    int offset = 0,
    int limit = 20,
  });

  Future<EditDetailModel?> getEditById(String id);
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

  static const _editDetailColumns =
      'id,user_id,image_id,prompt_text,prompt_text_original,edit_category,edit_goal,desired_style,status,ai_processing_time_ms,credits_used,created_at,updated_at,operation_type,task_id,image_url,file_size,mime_type,width,height';

  @override
  Future<EditDetailModel?> getEditById(String id) async {
    final response = await _supabase
        .from('edits')
        .select(_editDetailColumns)
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return EditDetailModel.fromJson(response as Map<String, dynamic>);
  }
}
