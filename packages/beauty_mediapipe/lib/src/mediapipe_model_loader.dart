import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copia modelos `.task` dos assets Flutter para path absoluto no disco.
class MediapipeModelLoader {
  static const faceModelAsset = 'assets/mediapipe/face_landmarker.task';
  static const poseModelAsset = 'assets/mediapipe/pose_landmarker_lite.task';
  static const segmenterModelAsset = 'assets/mediapipe/selfie_segmenter.tflite';
  static const facePartsModelAsset =
      'assets/mediapipe/selfie_multiclass_256x256.tflite';

  static Future<String> ensureFaceModelOnDisk({
    AssetBundle? bundle,
    String assetPath = faceModelAsset,
  }) async {
    return _ensureModelOnDisk(
      bundle: bundle,
      assetPath: assetPath,
      fileName: 'face_landmarker.task',
    );
  }

  static Future<String> ensurePoseModelOnDisk({
    AssetBundle? bundle,
    String assetPath = poseModelAsset,
  }) async {
    return _ensureModelOnDisk(
      bundle: bundle,
      assetPath: assetPath,
      fileName: 'pose_landmarker_lite.task',
    );
  }

  static Future<String> ensureSegmenterModelOnDisk({
    AssetBundle? bundle,
    String assetPath = segmenterModelAsset,
  }) async {
    return _ensureModelOnDisk(
      bundle: bundle,
      assetPath: assetPath,
      fileName: 'selfie_segmenter.tflite',
    );
  }

  static Future<String> ensureFacePartsModelOnDisk({
    AssetBundle? bundle,
    String assetPath = facePartsModelAsset,
  }) async {
    return _ensureModelOnDisk(
      bundle: bundle,
      assetPath: assetPath,
      fileName: 'selfie_multiclass_256x256.tflite',
    );
  }

  static Future<String> _ensureModelOnDisk({
    required String assetPath,
    required String fileName,
    AssetBundle? bundle,
  }) async {
    final data = await (bundle ?? rootBundle).load(assetPath);
    final dir = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(dir.path, 'mediapipe_models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    final file = File(p.join(modelsDir.path, fileName));
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
