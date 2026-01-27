import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/photo.dart';
import '../entities/photo_edit.dart';

abstract class EditorRepository {
  Future<Either<Failure, Photo>> uploadPhoto({
    required String filePath,
    required String filename,
  });

  Future<Either<Failure, PhotoEdit>> applyAIEffect({
    required String photoId,
    required String effectType,
    Map<String, dynamic>? params,
  });

  Future<Either<Failure, PhotoEdit>> getEditStatus(String editId);

  Future<Either<Failure, List<PhotoEdit>>> getPhotoEdits(String photoId);
}
