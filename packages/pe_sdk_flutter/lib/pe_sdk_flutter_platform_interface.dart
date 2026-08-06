import 'package:pe_sdk_flutter/export_result.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'pe_sdk_flutter_method_channel.dart';

abstract class PeSdkFlutterPlatform extends PlatformInterface {
  /// Constructs a PeSdkFlutterPlatform.
  PeSdkFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static PeSdkFlutterPlatform _instance = MethodChannelPeSdkFlutter();

  /// The default instance of [PeSdkFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelPeSdkFlutter].
  static PeSdkFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PeSdkFlutterPlatform] when
  /// they register themselves.
  static set instance(PeSdkFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<ExportResult?> openGalleryScreen(String token, bool applyDarkTheme) {
    throw UnimplementedError('openGalleryScreen() has not been implemented.');
  }

  Future<ExportResult?> openEditorScreen(
      String token, String sourcePhotoPath, bool applyDarkTheme) {
    throw UnimplementedError('openEditorScreen() has not been implemented.');
  }
}
