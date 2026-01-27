import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/user.dart' as domain;
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthDataSource _dataSource;

  AuthRepositoryImpl(this._dataSource);

  @override
  Future<Either<Failure, domain.User>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final userModel = await _dataSource.signIn(
        email: email,
        password: password,
      );
      return Right(userModel.toEntity());
    } on AuthFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, domain.User>> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final userModel = await _dataSource.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
      return Right(userModel.toEntity());
    } on AuthFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> signOut() async {
    try {
      await _dataSource.signOut();
      return const Right(null);
    } on AuthFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, domain.User?>> getCurrentUser() async {
    try {
      final userModel = await _dataSource.getCurrentUser();
      return Right(userModel?.toEntity());
    } on AuthFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> resetPassword(String email) async {
    try {
      await _dataSource.resetPassword(email);
      return const Right(null);
    } on AuthFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }
}
