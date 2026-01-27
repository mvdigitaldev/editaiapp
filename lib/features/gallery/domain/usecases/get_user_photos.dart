import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/gallery_photo.dart';
import '../repositories/gallery_repository.dart';

class GetUserPhotos {
  final GalleryRepository repository;

  GetUserPhotos(this.repository);

  Future<Either<Failure, List<GalleryPhoto>>> call({
    int limit = 20,
    int offset = 0,
  }) {
    return repository.getUserPhotos(limit: limit, offset: offset);
  }
}
