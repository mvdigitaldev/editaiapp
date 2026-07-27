import 'dart:typed_data';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';
import 'package:editaiapp/features/editor/beauty_engine/di/mediapipe_init_coordinator.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask_detector_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PersonMask', () {
    test('sampleNormalized returns center pixel alpha', () {
      final bytes = Uint8List(4 * 4);
      bytes[2 * 4 + 2] = 200;
      final mask = PersonMask(bytes: bytes, width: 4, height: 4);
      // Bilinear no centro exato do pixel (2,2) → ~200/255.
      expect(mask.sampleNormalized(2 / 3, 2 / 3), closeTo(200 / 255.0, 0.05));
      expect(mask.sampleNormalized(0, 0), 0);
    });
  });

  group('PersonMaskDetectorImpl', () {
    test('maps native mask bytes', () async {
      final bindings = BeautyMediapipeBindingsStub()
        ..nextPersonMaskResult = PersonMaskNativeResult(
          bytes: Uint8List.fromList([0, 128, 255, 64]),
          width: 2,
          height: 2,
        );
      final detector = PersonMaskDetectorImpl(
        bindings: bindings,
        coordinator: MediapipeInitCoordinator(
          bindings: bindings,
          resolveFaceModelPath: () async => '/tmp/face.task',
          resolvePoseModelPath: () async => '/tmp/pose.task',
          resolveSegmenterModelPath: () async => '/tmp/seg.tflite',
        ),
      );

      final mask = await detector.detect(
        ImageSource(bytes: Uint8List.fromList([1]), width: 1, height: 1),
      );

      expect(mask, isNotNull);
      expect(mask!.width, 2);
      expect(mask.height, 2);
      expect(mask.bytes[2], 255);
    });

    test('returns null when bindings fail init', () async {
      final detector = PersonMaskDetectorImpl(
        bindings: _FailingBindings(),
        coordinator: MediapipeInitCoordinator(
          bindings: _FailingBindings(),
          resolveFaceModelPath: () async => '/tmp/face.task',
          resolvePoseModelPath: () async => '/tmp/pose.task',
        ),
      );

      final mask = await detector.detect(
        ImageSource(bytes: Uint8List.fromList([1]), width: 1, height: 1),
      );
      expect(mask, isNull);
    });
  });
}

class _FailingBindings implements BeautyMediapipeBindings {
  @override
  Future<FaceLandmarkerNativeResult?> detectFace(NativeImageBuffer buffer) async =>
      null;

  @override
  Future<PoseLandmarkerNativeResult?> detectPose(NativeImageBuffer buffer) async =>
      null;

  @override
  Future<PersonMaskNativeResult?> detectPersonMask(NativeImageBuffer buffer) async =>
      null;

  @override
  void dispose() {}

  @override
  Future<void> initialize({
    required String faceModelPath,
    String? poseModelPath,
    String? segmenterModelPath,
  }) async {
    throw StateError('init failed');
  }
}
