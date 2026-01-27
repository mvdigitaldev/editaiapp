import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/error/failures.dart';
import '../../../editor/data/models/photo_model.dart';
import '../../../editor/data/models/photo_edit_model.dart';

abstract class GalleryDataSource {
  Future<List<PhotoModel>> getUserPhotos({
    int limit = 20,
    int offset = 0,
  });

  Future<PhotoModel> getPhotoDetails(String photoId);

  Future<void> deletePhoto(String photoId);

  Future<List<PhotoEditModel>> getPhotoEdits(String photoId);

  Future<String> getSignedUrl(String storagePath, {int expiresIn = 3600});
}

class GalleryDataSourceImpl implements GalleryDataSource {
  final SupabaseClient _supabase;

  GalleryDataSourceImpl(this._supabase);

  @override
  Future<List<PhotoModel>> getUserPhotos({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('photos')
          .select()
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((json) => PhotoModel.fromJson(json))
          .toList();
    } catch (e) {
      throw ServerFailure(message: e.toString());
    }
  }

  @override
  Future<PhotoModel> getPhotoDetails(String photoId) async {
    try {
      final response = await _supabase
          .from('photos')
          .select()
          .eq('id', photoId)
          .single();

      return PhotoModel.fromJson(response);
    } catch (e) {
      throw ServerFailure(message: e.toString());
    }
  }

  @override
  Future<void> deletePhoto(String photoId) async {
    try {
      // Buscar foto para obter o storage path
      final photo = await getPhotoDetails(photoId);

      // Deletar do storage
      await _supabase.storage
          .from(AppConfig.photosBucket)
          .remove([photo.originalStoragePath]);

      // Deletar do banco (cascade vai deletar edits e jobs relacionados)
      await _supabase.from('photos').delete().eq('id', photoId);
    } catch (e) {
      throw ServerFailure(message: e.toString());
    }
  }

  @override
  Future<List<PhotoEditModel>> getPhotoEdits(String photoId) async {
    try {
      final response = await _supabase
          .from('photos_edits')
          .select()
          .eq('photo_id', photoId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => PhotoEditModel.fromJson(json))
          .toList();
    } catch (e) {
      throw ServerFailure(message: e.toString());
    }
  }

  @override
  Future<String> getSignedUrl(String storagePath, {int expiresIn = 3600}) async {
    try {
      final response = await _supabase.storage
          .from(AppConfig.photosBucket)
          .createSignedUrl(storagePath, expiresIn);

      return response;
    } catch (e) {
      throw StorageFailure(message: e.toString());
    }
  }
}
