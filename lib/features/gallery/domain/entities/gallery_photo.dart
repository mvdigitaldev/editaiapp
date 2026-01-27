import '../../../editor/domain/entities/photo.dart';
import '../../../editor/domain/entities/photo_edit.dart';

class GalleryPhoto {
  final Photo photo;
  final List<PhotoEdit> edits;
  final String? signedUrl;

  GalleryPhoto({
    required this.photo,
    required this.edits,
    this.signedUrl,
  });
}
