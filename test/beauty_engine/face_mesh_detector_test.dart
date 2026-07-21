import 'dart:typed_data';
import 'dart:ui';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';
import 'package:editaiapp/features/editor/beauty_engine/di/mediapipe_init_coordinator.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_landmark_mapper.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FaceLandmarkMapper', () {
    test('maps 478 native landmarks to FaceMeshResult', () {
      final native = _fakeFaceNativeResult(count: 478);

      final result = FaceLandmarkMapper.toFaceMeshResult(native);

      expect(result, isNotNull);
      expect(result!.landmarks.length, 478);
      expect(result.landmarks.first.index, 0);
      expect(result.landmarks.first.normalized, const Offset(0.1, 0.2));
      expect(result.confidence, closeTo(0.9, 0.001));
      expect(result.boundingBox, const Rect.fromLTRB(0.05, 0.1, 0.95, 0.9));
    });

    test('returns null when landmark count differs from 478', () {
      final native = _fakeFaceNativeResult(count: 468);

      expect(FaceLandmarkMapper.toFaceMeshResult(native), isNull);
    });
  });

  group('FaceMeshDetectorImpl', () {
    test('returns null when native detects no face', () async {
      final bindings = BeautyMediapipeBindingsStub();
      final detector = FaceMeshDetectorImpl(
        bindings: bindings,
        coordinator: _coordinator(bindings),
      );

      final result = await detector.detect(
        ImageSource(bytes: Uint8List.fromList([1, 2, 3]), width: 1, height: 1),
      );

      expect(result, isNull);
    });

    test('returns FaceMeshResult when native detects face', () async {
      final bindings = BeautyMediapipeBindingsStub()
        ..nextFaceResult = _fakeFaceNativeResult(count: 478);
      final detector = FaceMeshDetectorImpl(
        bindings: bindings,
        coordinator: _coordinator(bindings),
      );

      final result = await detector.detect(
        ImageSource(bytes: Uint8List.fromList([1, 2, 3]), width: 640, height: 480),
      );

      expect(result, isNotNull);
      expect(result!.landmarks.length, FaceMeshResult.expectedLandmarkCount);
    });

    test('returns null when initialization fails', () async {
      final bindings = _FailingBindings();
      final detector = FaceMeshDetectorImpl(
        bindings: bindings,
        coordinator: MediapipeInitCoordinator(
          bindings: bindings,
          resolveFaceModelPath: () async => throw StateError('model missing'),
          resolvePoseModelPath: () async => '/tmp/pose.task',
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

FaceLandmarkerNativeResult _fakeFaceNativeResult({required int count}) {
  return FaceLandmarkerNativeResult(
    confidence: 0.9,
    bboxLeft: 0.05,
    bboxTop: 0.1,
    bboxRight: 0.95,
    bboxBottom: 0.9,
    landmarks: List.generate(
      count,
      (index) => NativeFaceLandmark(
        index: index,
        x: 0.1,
        y: 0.2,
        z: 0.01,
        visibility: 1,
      ),
    ),
  );
}

class _FailingBindings implements BeautyMediapipeBindings {
  @override
  Future<FaceLandmarkerNativeResult?> detectFace(NativeImageBuffer buffer) async {
    throw StateError('not initialized');
  }

  @override
  Future<PoseLandmarkerNativeResult?> detectPose(NativeImageBuffer buffer) async {
    return null;
  }

  @override
  void dispose() {}

  @override
  Future<void> initialize({
    required String faceModelPath,
    String? poseModelPath,
  }) async {
    throw StateError('init failed');
  }
}
