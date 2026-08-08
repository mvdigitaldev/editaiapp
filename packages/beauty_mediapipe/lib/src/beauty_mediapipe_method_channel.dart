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
    String? segmenterModelPath,
    String? facePartsModelPath,
  }) async {
    await _channel.invokeMethod<void>('initialize', {
      'faceModelPath': faceModelPath,
      if (poseModelPath != null) 'poseModelPath': poseModelPath,
      if (segmenterModelPath != null) 'segmenterModelPath': segmenterModelPath,
      if (facePartsModelPath != null) 'facePartsModelPath': facePartsModelPath,
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
      'width': buffer.width,
      'height': buffer.height,
      'rotation': buffer.rotation,
    });

    if (raw == null) {
      return null;
    }

    return _parseFaceResult(raw as Map<dynamic, dynamic>);
  }

  @override
  Future<List<FaceLandmarkerNativeResult>> detectFaces(
    NativeImageBuffer buffer,
  ) async {
    if (!_initialized) {
      throw StateError('BeautyMediapipeMethodChannel not initialized');
    }

    try {
      final dynamic raw = await _channel.invokeMethod<dynamic>('detectFaces', {
        'bytes': buffer.bytes,
        'width': buffer.width,
        'height': buffer.height,
        'rotation': buffer.rotation,
      });

      if (raw == null) {
        return const [];
      }

      final list = raw as List<dynamic>;
      return list
          .map((item) => _parseFaceResult(item as Map<dynamic, dynamic>))
          .toList(growable: false);
    } on MissingPluginException {
      // Binário antigo (pré-Sprint 7) — cai no detectFace single-face.
      final single = await detectFace(buffer);
      if (single == null) {
        return const [];
      }
      return [single];
    }
  }

  @override
  Future<PoseLandmarkerNativeResult?> detectPose(NativeImageBuffer buffer) async {
    if (!_initialized) {
      throw StateError('BeautyMediapipeMethodChannel not initialized');
    }

    final dynamic raw = await _channel.invokeMethod<dynamic>('detectPose', {
      'bytes': buffer.bytes,
      'width': buffer.width,
      'height': buffer.height,
      'rotation': buffer.rotation,
    });

    if (raw == null) {
      return null;
    }

    return _parsePoseResult(raw as Map<dynamic, dynamic>);
  }

  @override
  Future<PersonMaskNativeResult?> detectPersonMask(NativeImageBuffer buffer) async {
    if (!_initialized) {
      throw StateError('BeautyMediapipeMethodChannel not initialized');
    }

    final dynamic raw = await _channel.invokeMethod<dynamic>('detectPersonMask', {
      'bytes': buffer.bytes,
      'width': buffer.width,
      'height': buffer.height,
      'rotation': buffer.rotation,
    });

    if (raw == null) {
      return null;
    }

    return _parsePersonMaskResult(raw as Map<dynamic, dynamic>);
  }

  @override
  Future<FacePartsNativeResult?> detectFaceParts(
    NativeImageBuffer buffer,
  ) async {
    if (!_initialized) {
      throw StateError('BeautyMediapipeMethodChannel not initialized');
    }

    final dynamic raw = await _channel.invokeMethod<dynamic>('detectFaceParts', {
      'bytes': buffer.bytes,
      'width': buffer.width,
      'height': buffer.height,
      'rotation': buffer.rotation,
    });

    if (raw == null) {
      return null;
    }

    final map = raw as Map<dynamic, dynamic>;
    final width = map['width'] as int;
    final height = map['height'] as int;
    final classes = _asBytes(map['bytes'], 'face_parts');
    if (classes.length != width * height) {
      throw StateError(
        'face_parts_size_mismatch: got ${classes.length}, '
        'expected ${width * height}',
      );
    }
    return FacePartsNativeResult(
      classes: classes,
      width: width,
      height: height,
    );
  }

  @override
  Future<FaceParsingNativeResult?> detectFaceParsing(
    NativeImageBuffer buffer,
  ) async {
    if (!_initialized) {
      throw StateError('BeautyMediapipeMethodChannel not initialized');
    }

    final dynamic raw = await _channel.invokeMethod<dynamic>(
      'detectFaceParsing',
      {
        'bytes': buffer.bytes,
        'width': buffer.width,
        'height': buffer.height,
        'rotation': buffer.rotation,
      },
    );

    if (raw == null) {
      return null;
    }

    final map = raw as Map<dynamic, dynamic>;
    final width = map['width'] as int;
    final height = map['height'] as int;
    final classes = _asBytes(map['bytes'], 'face_parsing');
    if (classes.length != width * height) {
      throw StateError(
        'face_parsing_size_mismatch: got ${classes.length}, '
        'expected ${width * height}',
      );
    }
    return FaceParsingNativeResult(
      classes: classes,
      width: width,
      height: height,
    );
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

  /// Normaliza o payload de bytes do canal: cada plataforma/versão devolve
  /// `Uint8List`, `ByteData` ou `List<int>`.
  Uint8List _asBytes(Object? raw, String context) {
    if (raw is Uint8List) {
      return raw;
    }
    if (raw is ByteData) {
      return raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    }
    if (raw is List<int>) {
      return Uint8List.fromList(raw);
    }
    throw StateError('${context}_bytes_invalid: ${raw.runtimeType}');
  }

  PersonMaskNativeResult _parsePersonMaskResult(Map<dynamic, dynamic> raw) {
    final width = raw['width'] as int;
    final height = raw['height'] as int;
    final bytes = _asBytes(raw['bytes'], 'person_mask');

    if (bytes.length != width * height) {
      throw StateError(
        'person_mask_size_mismatch: got ${bytes.length}, expected ${width * height}',
      );
    }

    return PersonMaskNativeResult(
      bytes: bytes,
      width: width,
      height: height,
    );
  }
}

/// Stub para testes unitários.
class BeautyMediapipeBindingsStub implements BeautyMediapipeBindings {
  FaceLandmarkerNativeResult? nextFaceResult;
  PoseLandmarkerNativeResult? nextPoseResult;
  PersonMaskNativeResult? nextPersonMaskResult;
  FacePartsNativeResult? nextFacePartsResult;
  FaceParsingNativeResult? nextFaceParsingResult;

  @override
  Future<FaceLandmarkerNativeResult?> detectFace(NativeImageBuffer buffer) async {
    return nextFaceResult;
  }

  @override
  Future<List<FaceLandmarkerNativeResult>> detectFaces(
    NativeImageBuffer buffer,
  ) async {
    final single = nextFaceResult;
    if (single == null) {
      return const [];
    }
    return [single];
  }

  @override
  Future<PoseLandmarkerNativeResult?> detectPose(NativeImageBuffer buffer) async {
    return nextPoseResult;
  }

  @override
  Future<PersonMaskNativeResult?> detectPersonMask(NativeImageBuffer buffer) async {
    return nextPersonMaskResult;
  }

  @override
  Future<FacePartsNativeResult?> detectFaceParts(
    NativeImageBuffer buffer,
  ) async {
    return nextFacePartsResult;
  }

  @override
  Future<FaceParsingNativeResult?> detectFaceParsing(
    NativeImageBuffer buffer,
  ) async {
    return nextFaceParsingResult;
  }

  @override
  void dispose() {}

  @override
  Future<void> initialize({
    required String faceModelPath,
    String? poseModelPath,
    String? segmenterModelPath,
    String? facePartsModelPath,
  }) async {}
}
