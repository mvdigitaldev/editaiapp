import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

class SignUp {
  final AuthRepository repository;

  SignUp(this.repository);

  Future<Either<Failure, User>> call({
    required String email,
    required String password,
    String? displayName,
  }) {
    return repository.signUp(
      email: email,
      password: password,
      displayName: displayName,
    );
  }
}
