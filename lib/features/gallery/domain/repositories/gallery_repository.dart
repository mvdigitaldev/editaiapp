import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/gallery_photo.dart';

abstract class GalleryRepository {
  Future<Either<Failure, List<GalleryPhoto>>> getUserPhotos({
    int limit = 20,
    int offset = 0,
  });

  Future<Either<Failure, GalleryPhoto>> getPhotoDetails(String photoId);

  Future<Either<Failure, void>> deletePhoto(String photoId);

  Future<Either<Failure, List<GalleryPhoto>>> getPhotoHistory(String photoId);
}
