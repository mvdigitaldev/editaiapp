import 'package:flutter/services.dart';

class BanubaPhotoEditorService {
  const BanubaPhotoEditorService();

  static const _channel = MethodChannel('pe_sdk_flutter');

  Future<String?> editPhoto({
    required String licenseToken,
    required String sourcePath,
    required bool useDarkTheme,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'startPhotoEditor',
        <String, Object?>{
          'token': licenseToken,
          'mode': 'editor',
          'photoSource': sourcePath,
          'applyDarkTheme': useDarkTheme,
        },
      );

      final outputPath = result?['exportedPhotoSource']?.toString();
      return outputPath == null || outputPath.isEmpty ? null : outputPath;
    } on PlatformException catch (error) {
      if (error.code == 'ERR_PHOTO_EXPORT_CANCEL') return null;
      throw BanubaEditorException.fromPlatform(error);
    }
  }
}

class BanubaEditorException implements Exception {
  const BanubaEditorException(this.message);

  factory BanubaEditorException.fromPlatform(PlatformException error) {
    final message = switch (error.code) {
      'ERR_SDK_NOT_INITIALIZED' =>
        'Não foi possível validar a licença do editor.',
      'ERR_SDK_LICENSE_REVOKED' =>
        'A licença do editor expirou ou foi revogada.',
      'ERR_MISSING_HOST' => 'Não foi possível abrir o editor nesta tela.',
      _ => 'Não foi possível abrir o editor. Tente novamente.',
    };
    return BanubaEditorException(message);
  }

  final String message;

  @override
  String toString() => message;
}
