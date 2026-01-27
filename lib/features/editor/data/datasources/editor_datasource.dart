import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/error/failures.dart';
import '../models/photo_model.dart';
import '../models/photo_edit_model.dart';

abstract class EditorDataSource {
  Future<PhotoModel> uploadPhoto({
    required String filePath,
    required String filename,
  });

  Future<PhotoEditModel> applyAIEffect({
    required String photoId,
    required String effectType,
    Map<String, dynamic>? params,
  });

  Future<PhotoEditModel> getEditStatus(String editId);

  Future<List<PhotoEditModel>> getPhotoEdits(String photoId);
}

class EditorDataSourceImpl implements EditorDataSource {
  final SupabaseClient _supabase;
  final _uuid = const Uuid();

  EditorDataSourceImpl(this._supabase);

  @override
  Future<PhotoModel> uploadPhoto({
    required String filePath,
    required String filename,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw AuthFailure(message: 'Usuário não autenticado');
      }

      final file = File(filePath);
      final fileSize = await file.length();
      final fileExtension = filename.split('.').last;
      final photoId = _uuid.v4();
      final storagePath = '${user.id}/originals/$photoId.$fileExtension';

      // Upload para Supabase Storage
      await _supabase.storage.from(AppConfig.photosBucket).upload(
            storagePath,
            file,
          );

      // Obter URL pública
      final publicUrl = _supabase.storage
          .from(AppConfig.photosBucket)
          .getPublicUrl(storagePath);

      // Criar registro no banco
      final response = await _supabase.from('photos').insert({
        'id': photoId,
        'user_id': user.id,
        'original_filename': filename,
        'original_storage_path': storagePath,
        'file_size_bytes': fileSize,
        'mime_type': 'image/$fileExtension',
      }).select().single();

      return PhotoModel.fromJson(response);
    } catch (e) {
      throw StorageFailure(message: e.toString());
    }
  }

  @override
  Future<PhotoEditModel> applyAIEffect({
    required String photoId,
    required String effectType,
    Map<String, dynamic>? params,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw AuthFailure(message: 'Usuário não autenticado');
      }

      // Criar job de IA
      final jobId = _uuid.v4();
      await _supabase.from('ai_jobs').insert({
        'id': jobId,
        'user_id': user.id,
        'photo_id': photoId,
        'job_type': effectType,
        'input_params': params ?? {},
        'status': 'queued',
      });

      // Criar registro de edição
      final editId = _uuid.v4();
      final response = await _supabase.from('photos_edits').insert({
        'id': editId,
        'photo_id': photoId,
        'user_id': user.id,
        'edit_type': effectType,
        'edit_params': params,
        'status': 'pending',
        'ai_job_id': jobId,
      }).select().single();

      return PhotoEditModel.fromJson(response);
    } catch (e) {
      throw ServerFailure(message: e.toString());
    }
  }

  @override
  Future<PhotoEditModel> getEditStatus(String editId) async {
    try {
      final response = await _supabase
          .from('photos_edits')
          .select()
          .eq('id', editId)
          .single();

      return PhotoEditModel.fromJson(response);
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
}
