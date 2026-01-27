import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/photo_edit.dart';
import '../repositories/editor_repository.dart';

class ApplyAIEffect {
  final EditorRepository repository;

  ApplyAIEffect(this.repository);

  Future<Either<Failure, PhotoEdit>> call({
    required String photoId,
    required String effectType,
    Map<String, dynamic>? params,
  }) {
    return repository.applyAIEffect(
      photoId: photoId,
      effectType: effectType,
      params: params,
    );
  }
}
