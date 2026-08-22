import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Raízes graváveis do Device Lab V2. Independente de [ExtendedRoiDumpPaths]
/// e de [FaceWarpV3Config].
abstract final class FacialWarpV2DumpPaths {
  FacialWarpV2DumpPaths._();

  static const desktopRelativeRoot = '.cursor/facial-warp-v2/v2.3';
  static const deviceLeaf = 'facial-warp-v2/v2.3';

  static String? _deviceRoot;
  static String lastResolvedDir = '';
  static String lastResolveError = '';

  static bool get isMobilePlatform =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static void bindDeviceRoot(String path) {
    _deviceRoot = path;
    lastResolveError = '';
  }

  static void clearDeviceRootForTest() {
    _deviceRoot = null;
    lastResolvedDir = '';
    lastResolveError = '';
  }

  static String? get boundDeviceRoot => _deviceRoot;

  static Future<void> bindApplicationDocuments() async {
    if (kIsWeb || !isMobilePlatform) {
      return;
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      bindDeviceRoot('${docs.path}/$deviceLeaf');
      return;
    } catch (e) {
      lastResolveError = e.toString();
    }
    try {
      bindDeviceRoot('${Directory.systemTemp.path}/$deviceLeaf');
    } catch (e) {
      lastResolveError = e.toString();
    }
  }

  static String runDir({
    required String photoId,
    required int intensityPercent,
  }) {
    if (_deviceRoot != null && _deviceRoot!.isNotEmpty) {
      return '$_deviceRoot/$photoId/$intensityPercent';
    }
    if (isMobilePlatform) {
      return '${Directory.systemTemp.path}/$deviceLeaf/$photoId/$intensityPercent';
    }
    return '$desktopRelativeRoot/$photoId/$intensityPercent';
  }

  static String ensureWritable(String preferred) {
    lastResolveError = '';
    try {
      Directory(preferred).createSync(recursive: true);
      lastResolvedDir = preferred;
      return preferred;
    } on FileSystemException catch (e) {
      lastResolveError = e.toString();
      final fallback =
          '${Directory.systemTemp.path}/$deviceLeaf/_live';
      Directory(fallback).createSync(recursive: true);
      lastResolvedDir = fallback;
      return fallback;
    }
  }
}
