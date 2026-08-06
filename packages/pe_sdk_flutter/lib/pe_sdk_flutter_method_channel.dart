import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pe_sdk_flutter/export_result.dart';

import 'pe_sdk_flutter_platform_interface.dart';

/// An implementation of [PeSdkFlutterPlatform] that uses method channels.
class MethodChannelPeSdkFlutter extends PeSdkFlutterPlatform {
  // Channel and method
  static const String _channelName = 'pe_sdk_flutter';
  static const String _methodStart = 'startPhotoEditor';

  // Input params
  static const String _inputParamToken = 'token';
  static const String _inputParamMode = 'mode';
  static const String _inputParamPhotoSource = 'photoSource';
  static const String _inputParamApplyDarkTheme = 'applyDarkTheme';

  // Modes
  static const String _modeGallery = 'gallery';
  static const String _modeEditor = 'editor';

  static const String _exportedPhotoSource = 'exportedPhotoSource';

  @visibleForTesting
  final methodChannel = const MethodChannel(_channelName);

  @override
  Future<ExportResult?> openGalleryScreen(String token, bool applyDarkTheme) =>
      _open(token, _modeGallery, "", applyDarkTheme);

  @override
  Future<ExportResult?> openEditorScreen(
          String token, String sourcePhotoPath, bool applyDarkTheme) =>
      _open(token, _modeEditor, sourcePhotoPath, applyDarkTheme);

  Future<ExportResult?> _open(
      String token, String mode, String sourcePhotoPath, bool applyDarkTheme) async {
    final inputParams = {
      _inputParamToken: token,
      _inputParamMode: mode,
      _inputParamPhotoSource: sourcePhotoPath,
      _inputParamApplyDarkTheme: applyDarkTheme,
    };

    debugPrint('Start photo editor with params = $inputParams');

    dynamic exportedData =
    await methodChannel.invokeMethod(_methodStart, inputParams);

    if (exportedData == null) {
      return null;
    } else {
      String? source = exportedData[_exportedPhotoSource] as String?;
      String photoSource = source.toString();

      return ExportResult(photoSource: photoSource);
    }
  }
}
