import 'package:flutter/services.dart';

import 'beauty_mediapipe_bindings.dart';
import 'native_image_buffer.dart';

/// Implementação MethodChannel para Android/iOS MediaPipe.
class BeautyMediapipeMethodChannel implements BeautyMediapipeBindings {
  BeautyMediapipeMethodChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.editaiapp/beauty_mediapipe';

  final MethodChannel _channel;
  bool _initialized = false;

  @override
  Future<void> initialize({
    required String faceModelPath,
    String? poseModelPath,
  }) async {
    await _channel.invokeMethod<void>('initialize', {
      'faceModelPath': faceModelPath,
      if (poseModelPath != null) 'poseModelPath': poseModelPath,
    });
    _initialized = true;
  }

  @override
  Future<FaceLandmarkerNativeResult?> detectFace(NativeImageBuffer buffer) async {
    if (!_initialized) {
      throw StateError('BeautyMediapipeMethodChannel not initialized');
    }

    final dynamic raw = await _channel.invokeMethod<dynamic>('detectFace', {
      'bytes': buffer.bytes,
      'rotation': buffer.rotation,
    });

    if (raw == null) {
      return null;
    }

    return _parseFaceResult(raw as Map<dynamic, dynamic>);
  }

  @override
  Future<PoseLandmarkerNativeResult?> detectPose(NativeImageBuffer buffer) async {
    if (!_initialized) {
      throw StateError('BeautyMediapipeMethodChannel not initialized');
    }

    final dynamic raw = await _channel.invokeMethod<dynamic>('detectPose', {
      'bytes': buffer.bytes,
      'rotation': buffer.rotation,
    });

    if (raw == null) {
      return null;
    }

    return _parsePoseResult(raw as Map<dynamic, dynamic>);
  }

  @override
  void dispose() {
    if (_initialized) {
      _channel.invokeMethod<void>('dispose');
      _initialized = false;
    }
  }

  FaceLandmarkerNativeResult _parseFaceResult(Map<dynamic, dynamic> raw) {
    final landmarksRaw = raw['landmarks'] as List<dynamic>;
    final landmarks = landmarksRaw.map((item) {
      final map = item as Map<dynamic, dynamic>;
      return NativeFaceLandmark(
        index: map['index'] as int,
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        z: (map['z'] as num).toDouble(),
        visibility: (map['visibility'] as num?)?.toDouble() ?? 1,
      );
    }).toList();

    final box = raw['boundingBox'] as Map<dynamic, dynamic>;

    return FaceLandmarkerNativeResult(
      landmarks: landmarks,
      confidence: (raw['confidence'] as num?)?.toDouble() ?? 0,
      bboxLeft: (box['left'] as num).toDouble(),
      bboxTop: (box['top'] as num).toDouble(),
      bboxRight: (box['right'] as num).toDouble(),
      bboxBottom: (box['bottom'] as num).toDouble(),
    );
  }

  PoseLandmarkerNativeResult _parsePoseResult(Map<dynamic, dynamic> raw) {
    final landmarksRaw = raw['landmarks'] as List<dynamic>;
    final landmarks = landmarksRaw.map((item) {
      final map = item as Map<dynamic, dynamic>;
      return NativePoseLandmark(
        index: map['index'] as int,
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        z: (map['z'] as num?)?.toDouble() ?? 0,
        visibility: (map['visibility'] as num?)?.toDouble() ?? 0,
      );
    }).toList();

    final box = raw['boundingBox'] as Map<dynamic, dynamic>;

    return PoseLandmarkerNativeResult(
      landmarks: landmarks,
      bboxLeft: (box['left'] as num).toDouble(),
      bboxTop: (box['top'] as num).toDouble(),
      bboxRight: (box['right'] as num).toDouble(),
      bboxBottom: (box['bottom'] as num).toDouble(),
    );
  }
}

/// Stub para testes unitários.
class BeautyMediapipeBindingsStub implements BeautyMediapipeBindings {
  FaceLandmarkerNativeResult? nextFaceResult;
  PoseLandmarkerNativeResult? nextPoseResult;

  @override
  Future<FaceLandmarkerNativeResult?> detectFace(NativeImageBuffer buffer) async {
    return nextFaceResult;
  }

  @override
  Future<PoseLandmarkerNativeResult?> detectPose(NativeImageBuffer buffer) async {
    return nextPoseResult;
  }

  @override
  void dispose() {}

  @override
  Future<void> initialize({
    required String faceModelPath,
    String? poseModelPath,
  }) async {}
}
