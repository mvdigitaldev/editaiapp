import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/datasources/edits_gallery_datasource.dart';
import '../../data/datasources/gallery_datasource.dart';
import '../../data/models/gallery_edit_model.dart';
import '../../data/repositories/gallery_repository_impl.dart';
import '../../domain/repositories/gallery_repository.dart';
import '../../domain/usecases/delete_photo.dart';
import '../../domain/usecases/get_photo_history.dart';
import '../../domain/usecases/get_user_photos.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final galleryDataSourceProvider = Provider<GalleryDataSource>((ref) {
  return GalleryDataSourceImpl(ref.watch(supabaseClientProvider));
});

final editsGalleryDataSourceProvider = Provider<EditsGalleryDataSource>((ref) {
  return EditsGalleryDataSourceImpl(ref.watch(supabaseClientProvider));
});

/// Edições recentes para a home. Invalidar após criar edição/geração/composição/remoção.
final recentEditsProvider = FutureProvider<List<GalleryEditModel>>((ref) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) return [];
  final ds = ref.watch(editsGalleryDataSourceProvider);
  return ds.getEditsForGallery(offset: 0, limit: 4);
});

final galleryRepositoryProvider = Provider<GalleryRepository>((ref) {
  return GalleryRepositoryImpl(ref.watch(galleryDataSourceProvider));
});

final getUserPhotosProvider = Provider<GetUserPhotos>((ref) {
  return GetUserPhotos(ref.watch(galleryRepositoryProvider));
});

final deletePhotoProvider = Provider<DeletePhoto>((ref) {
  return DeletePhoto(ref.watch(galleryRepositoryProvider));
});

final getPhotoHistoryProvider = Provider<GetPhotoHistory>((ref) {
  return GetPhotoHistory(ref.watch(galleryRepositoryProvider));
});
