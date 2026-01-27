import 'package:freezed_annotation/freezed_annotation.dart';

part 'failures.freezed.dart';

@freezed
class Failure with _$Failure {
  const factory Failure.server({
    String? message,
    int? statusCode,
  }) = ServerFailure;

  const factory Failure.network({
    String? message,
  }) = NetworkFailure;

  const factory Failure.storage({
    String? message,
  }) = StorageFailure;

  const factory Failure.auth({
    String? message,
  }) = AuthFailure;

  const factory Failure.validation({
    String? message,
  }) = ValidationFailure;

  const factory Failure.unknown({
    String? message,
  }) = UnknownFailure;
}
