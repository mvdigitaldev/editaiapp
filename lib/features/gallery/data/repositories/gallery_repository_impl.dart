import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/gallery_photo.dart';
import '../../domain/repositories/gallery_repository.dart';
import '../datasources/gallery_datasource.dart';
import '../../../editor/domain/entities/photo.dart';
import '../../../editor/domain/entities/photo_edit.dart';
import '../../../editor/data/models/photo_model.dart';
import '../../../editor/data/models/photo_edit_model.dart';

class GalleryRepositoryImpl implements GalleryRepository {
  final GalleryDataSource _dataSource;

  GalleryRepositoryImpl(this._dataSource);

  @override
  Future<Either<Failure, List<GalleryPhoto>>> getUserPhotos({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final photos = await _dataSource.getUserPhotos(
        limit: limit,
        offset: offset,
      );

      final galleryPhotos = await Future.wait(
        photos.map((photo) async {
          final edits = await _dataSource.getPhotoEdits(photo.id);
          String? signedUrl;
          try {
            signedUrl = await _dataSource.getSignedUrl(photo.originalStoragePath);
          } catch (_) {
            signedUrl = null;
          }

          return GalleryPhoto(
            photo: photo.toEntity(),
            edits: edits.map((e) => e.toEntity()).toList(),
            signedUrl: signedUrl,
          );
        }),
      );

      return Right(galleryPhotos);
    } on ServerFailure catch (e) {
      return Left(e);
    } on StorageFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, GalleryPhoto>> getPhotoDetails(String photoId) async {
    try {
      final photo = await _dataSource.getPhotoDetails(photoId);
      final edits = await _dataSource.getPhotoEdits(photoId);
      String? signedUrl;
      try {
        signedUrl = await _dataSource.getSignedUrl(photo.originalStoragePath);
      } catch (_) {
        signedUrl = null;
      }

      return Right(
        GalleryPhoto(
          photo: photo.toEntity(),
          edits: edits.map((e) => e.toEntity()).toList(),
          signedUrl: signedUrl,
        ),
      );
    } on ServerFailure catch (e) {
      return Left(e);
    } on StorageFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deletePhoto(String photoId) async {
    try {
      await _dataSource.deletePhoto(photoId);
      return const Right(null);
    } on ServerFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<GalleryPhoto>>> getPhotoHistory(
      String photoId) async {
    try {
      final photo = await _dataSource.getPhotoDetails(photoId);
      final edits = await _dataSource.getPhotoEdits(photoId);

      final galleryPhotos = await Future.wait(
        edits.map((edit) async {
          String? signedUrl;
          if (edit.editedStoragePath != null) {
            try {
              signedUrl = await _dataSource.getSignedUrl(edit.editedStoragePath!);
            } catch (_) {
              signedUrl = null;
            }
          } else {
            signedUrl = null;
          }

          return GalleryPhoto(
            photo: photo.toEntity(),
            edits: [edit.toEntity()],
            signedUrl: signedUrl,
          );
        }),
      );

      return Right(galleryPhotos);
    } on ServerFailure catch (e) {
      return Left(e);
    } on StorageFailure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }
}
