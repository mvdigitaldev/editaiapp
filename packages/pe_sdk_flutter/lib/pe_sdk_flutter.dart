import 'package:pe_sdk_flutter/export_result.dart';
import 'pe_sdk_flutter_platform_interface.dart';

class PeSdkFlutter {
  Future<ExportResult?> openGalleryScreen(
    String token, {
    bool applyDarkTheme = false,
  }) =>
      PeSdkFlutterPlatform.instance
          .openGalleryScreen(token, applyDarkTheme);

  Future<ExportResult?> openEditorScreen(
    String token,
    String sourcePhotoPath, {
    bool applyDarkTheme = false,
  }) =>
      PeSdkFlutterPlatform.instance
          .openEditorScreen(token, sourcePhotoPath, applyDarkTheme);
}
