import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/multi_face_detection.dart';
import 'package:flutter_test/flutter_test.dart';

FaceMeshResult _faceAt(Rect box) {
  return FaceMeshResult(
    landmarks: List.generate(
      FaceMeshResult.expectedLandmarkCount,
      (i) => FaceLandmark(
        index: i,
        normalized: Offset(box.center.dx, box.center.dy),
      ),
    ),
    boundingBox: box,
    confidence: 0.9,
  );
}

void main() {
  group('MultiFaceDetection', () {
    test('indexOfLargest picks biggest bbox', () {
      final faces = [
        _faceAt(const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2)),
        _faceAt(const Rect.fromLTWH(0.5, 0.1, 0.35, 0.35)),
      ];
      expect(MultiFaceDetection.indexOfLargest(faces), 1);
      expect(
        MultiFaceDetection.primaryFace(faces)!.boundingBox,
        faces[1].boundingBox,
      );
    });

    test('indexAtNormalized hit tests expanded boxes', () {
      final faces = [
        _faceAt(const Rect.fromLTWH(0.05, 0.2, 0.2, 0.25)),
        _faceAt(const Rect.fromLTWH(0.55, 0.2, 0.2, 0.25)),
      ];
      expect(
        MultiFaceDetection.indexAtNormalized(faces, const Offset(0.15, 0.3)),
        0,
      );
      expect(
        MultiFaceDetection.indexAtNormalized(faces, const Offset(0.65, 0.3)),
        1,
      );
      expect(
        MultiFaceDetection.indexAtNormalized(faces, const Offset(0.5, 0.9)),
        isNull,
      );
    });
  });
}
