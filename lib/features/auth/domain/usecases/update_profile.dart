import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

class UpdateProfile {
  final AuthRepository repository;

  UpdateProfile(this.repository);

  Future<Either<Failure, User>> call({
    String? displayName,
    String? avatarUrl,
  }) {
    return repository.updateProfile(
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }
}
