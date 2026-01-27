import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/photo_edit.dart';
import '../repositories/editor_repository.dart';

class GetEditStatus {
  final EditorRepository repository;

  GetEditStatus(this.repository);

  Future<Either<Failure, PhotoEdit>> call(String editId) {
    return repository.getEditStatus(editId);
  }
}
