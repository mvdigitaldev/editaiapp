import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../repositories/gallery_repository.dart';

class DeletePhoto {
  final GalleryRepository repository;

  DeletePhoto(this.repository);

  Future<Either<Failure, void>> call(String photoId) {
    return repository.deletePhoto(photoId);
  }
}
