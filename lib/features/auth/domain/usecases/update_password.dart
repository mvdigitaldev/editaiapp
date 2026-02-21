import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../repositories/auth_repository.dart';

class UpdatePassword {
  final AuthRepository repository;

  UpdatePassword(this.repository);

  Future<Either<Failure, void>> call(String newPassword) {
    return repository.updatePassword(newPassword);
  }
}
