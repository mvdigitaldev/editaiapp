import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/datasources/editor_datasource.dart';
import '../../data/repositories/editor_repository_impl.dart';
import '../../domain/repositories/editor_repository.dart';
import '../../domain/usecases/apply_ai_effect.dart';
import '../../domain/usecases/get_edit_status.dart';
import '../../domain/usecases/upload_photo.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final editorDataSourceProvider = Provider<EditorDataSource>((ref) {
  return EditorDataSourceImpl(ref.watch(supabaseClientProvider));
});

final editorRepositoryProvider = Provider<EditorRepository>((ref) {
  return EditorRepositoryImpl(ref.watch(editorDataSourceProvider));
});

final uploadPhotoProvider = Provider<UploadPhoto>((ref) {
  return UploadPhoto(ref.watch(editorRepositoryProvider));
});

final applyAIEffectProvider = Provider<ApplyAIEffect>((ref) {
  return ApplyAIEffect(ref.watch(editorRepositoryProvider));
});

final getEditStatusProvider = Provider<GetEditStatus>((ref) {
  return GetEditStatus(ref.watch(editorRepositoryProvider));
});
