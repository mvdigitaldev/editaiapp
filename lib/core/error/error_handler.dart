import 'package:dio/dio.dart';
import 'failures.dart';

class ErrorHandler {
  static Failure handleError(dynamic error) {
    if (error is DioException) {
      return _handleDioError(error);
    }

    if (error is Exception) {
      return Failure.unknown(message: error.toString());
    }

    return Failure.unknown(message: 'Ocorreu um erro desconhecido');
  }

  static Failure _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Failure.network(
          message: 'Tempo de conexão expirado. Verifique sua internet.',
        );

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final message = error.response?.data?['message'] as String?;

        if (statusCode == 401 || statusCode == 403) {
          return Failure.auth(message: message ?? 'Não autorizado');
        }

        return Failure.server(
          message: message ?? 'Erro no servidor',
          statusCode: statusCode,
        );

      case DioExceptionType.cancel:
        return Failure.network(message: 'Requisição cancelada');

      case DioExceptionType.unknown:
      default:
        return Failure.network(
          message: 'Erro de conexão. Verifique sua internet.',
        );
    }
  }
}
