import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/photo.dart';
import '../../domain/entities/photo_edit.dart';
import '../../domain/repositories/editor_repository.dart';
import '../datasources/editor_datasource.dart';
import '../models/photo_model.dart';
import '../models/photo_edit_model.dart';

class EditorRepositoryImpl implements EditorRepository {
  final EditorDataSource _dataSource;

  EditorRepositoryImpl(this._dataSource);

  @override
  Future<Either<Failure, Photo>> uploadPhoto({
    required String filePath,
    required String filename,
  }) async {
    try {
      final photoModel = await _dataSource.uploadPhoto(
        filePath: filePath,
        filename: filename,
      );
      return Right(photoModel.toEntity());
    } on StorageFailure catch (e) {
      return Left(e);
    } on AuthFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, PhotoEdit>> applyAIEffect({
    required String photoId,
    required String effectType,
    Map<String, dynamic>? params,
  }) async {
    try {
      final editModel = await _dataSource.applyAIEffect(
        photoId: photoId,
        effectType: effectType,
        params: params,
      );
      return Right(editModel.toEntity());
    } on ServerFailure catch (e) {
      return Left(e);
    } on AuthFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, PhotoEdit>> getEditStatus(String editId) async {
    try {
      final editModel = await _dataSource.getEditStatus(editId);
      return Right(editModel.toEntity());
    } on ServerFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<PhotoEdit>>> getPhotoEdits(
      String photoId) async {
    try {
      final editModels = await _dataSource.getPhotoEdits(photoId);
      return Right(editModels.map((e) => e.toEntity()).toList());
    } on ServerFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }
}
