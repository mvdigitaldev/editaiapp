import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/gallery_photo.dart';
import '../repositories/gallery_repository.dart';

class GetPhotoHistory {
  final GalleryRepository repository;

  GetPhotoHistory(this.repository);

  Future<Either<Failure, List<GalleryPhoto>>> call(String photoId) {
    return repository.getPhotoHistory(photoId);
  }
}
