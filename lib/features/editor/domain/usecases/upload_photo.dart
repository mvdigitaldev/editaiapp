import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/photo.dart';
import '../repositories/editor_repository.dart';

class UploadPhoto {
  final EditorRepository repository;

  UploadPhoto(this.repository);

  Future<Either<Failure, Photo>> call({
    required String filePath,
    required String filename,
  }) {
    return repository.uploadPhoto(
      filePath: filePath,
      filename: filename,
    );
  }
}
