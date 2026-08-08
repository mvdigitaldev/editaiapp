import 'dart:typed_data';
import 'dart:ui';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';
import 'package:editaiapp/features/editor/beauty_engine/di/mediapipe_init_coordinator.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/pose/pose_detector_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/pose/pose_landmark_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PoseLandmarkMapper', () {
    test('maps 33 native landmarks to PoseResult', () {
      final native = _fakePoseNativeResult(
        visibilityForAll: 0.9,
      );

      final result = PoseLandmarkMapper.toPoseResult(native);

      expect(result, isNotNull);
      expect(result!.landmarks.length, 33);
      expect(result.isPartial, isFalse);
      expect(result.landmarks.first.normalized, const Offset(0.4, 0.3));
    });

    test('flags partial pose when lower body visibility is low', () {
      final native = _fakePoseNativeResult(
        visibilityForAll: 0.9,
        overrides: {
          25: 0.2,
          26: 0.2,
          27: 0.1,
          28: 0.1,
        },
      );

      final result = PoseLandmarkMapper.toPoseResult(native);

      expect(result, isNotNull);
      expect(result!.isPartial, isTrue);
    });

    test('returns null when landmark count differs from 33', () {
      final native = _fakePoseNativeResult(count: 30);

      expect(PoseLandmarkMapper.toPoseResult(native), isNull);
    });

    test('returns null when no primary landmark is visible', () {
      final native = _fakePoseNativeResult(visibilityForAll: 0.1);

      expect(PoseLandmarkMapper.toPoseResult(native), isNull);
    });

    test('primary landmarks have visibility above threshold in full body', () {
      final native = _fakePoseNativeResult(visibilityForAll: 0.9);
      final result = PoseLandmarkMapper.toPoseResult(native)!;

      for (final index in PoseLandmarkMapper.primaryIndices) {
        final landmark = result.landmarks.firstWhere((item) => item.index == index);
        expect(
          landmark.visibility,
          greaterThanOrEqualTo(PoseLandmarkMapper.visibilityThreshold),
        );
      }
    });
  });

  group('PoseDetectorImpl', () {
    test('returns null when native detects no pose', () async {
      final bindings = BeautyMediapipeBindingsStub();
      final detector = PoseDetectorImpl(
        bindings: bindings,
        coordinator: _coordinator(bindings),
      );

      final result = await detector.detect(
        ImageSource(bytes: Uint8List.fromList([1, 2, 3]), width: 1, height: 1),
      );

      expect(result, isNull);
    });

    test('returns PoseResult when native detects pose', () async {
      final bindings = BeautyMediapipeBindingsStub()
        ..nextPoseResult = _fakePoseNativeResult(visibilityForAll: 0.9);
      final detector = PoseDetectorImpl(
        bindings: bindings,
        coordinator: _coordinator(bindings),
      );

      final result = await detector.detect(
        ImageSource(bytes: Uint8List.fromList([1, 2, 3]), width: 640, height: 480),
      );

      expect(result, isNotNull);
      expect(result!.landmarks.length, PoseResult.expectedLandmarkCount);
      expect(result.isPartial, isFalse);
    });

    test('returns null when initialization fails', () async {
      final bindings = _FailingBindings();
      final detector = PoseDetectorImpl(
        bindings: bindings,
        coordinator: MediapipeInitCoordinator(
          bindings: bindings,
          resolveFaceModelPath: () async => '/tmp/face.task',
          resolvePoseModelPath: () async => throw StateError('model missing'),
        ),
      );

      final result = await detector.detect(
        ImageSource(bytes: Uint8List.fromList([1]), width: 1, height: 1),
      );

      expect(result, isNull);
    });
  });
}

MediapipeInitCoordinator _coordinator(BeautyMediapipeBindings bindings) {
  return MediapipeInitCoordinator(
    bindings: bindings,
    resolveFaceModelPath: () async => '/tmp/face_landmarker.task',
    resolvePoseModelPath: () async => '/tmp/pose_landmarker_lite.task',
  );
}

PoseLandmarkerNativeResult _fakePoseNativeResult({
  int count = 33,
  double visibilityForAll = 0.9,
  Map<int, double> overrides = const {},
}) {
  return PoseLandmarkerNativeResult(
    bboxLeft: 0.1,
    bboxTop: 0.05,
    bboxRight: 0.9,
    bboxBottom: 0.95,
    landmarks: List.generate(
      count,
      (index) => NativePoseLandmark(
        index: index,
        x: 0.4,
        y: 0.3,
        z: 0.01,
        visibility: overrides[index] ?? visibilityForAll,
      ),
    ),
  );
}

class _FailingBindings implements BeautyMediapipeBindings {
  @override
  Future<FaceLandmarkerNativeResult?> detectFace(NativeImageBuffer buffer) async {
    return null;
  }

  @override
  Future<PoseLandmarkerNativeResult?> detectPose(NativeImageBuffer buffer) async {
    throw StateError('not initialized');
  }

  @override
  Future<PersonMaskNativeResult?> detectPersonMask(NativeImageBuffer buffer) async {
    return null;
  }

  @override
  Future<FacePartsNativeResult?> detectFaceParts(
    NativeImageBuffer buffer,
  ) async {
    return null;
  }

  @override
  void dispose() {}

  @override
  Future<void> initialize({
    required String faceModelPath,
    String? poseModelPath,
    String? segmenterModelPath,
    String? facePartsModelPath,
  }) async {
    throw StateError('init failed');
  }
}
