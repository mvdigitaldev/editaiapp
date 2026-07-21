import 'dart:ui';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';

import '../models/face_landmark.dart';
import '../models/face_mesh_result.dart';

/// Converte resultado nativo MediaPipe → modelo Dart do Beauty Engine.
class FaceLandmarkMapper {
  const FaceLandmarkMapper._();

  static FaceMeshResult? toFaceMeshResult(FaceLandmarkerNativeResult native) {
    if (native.landmarks.length != FaceMeshResult.expectedLandmarkCount) {
      return null;
    }

    final landmarks = native.landmarks
        .map(
          (landmark) => FaceLandmark(
            index: landmark.index,
            normalized: Offset(landmark.x, landmark.y),
            z: landmark.z,
            visibility: landmark.visibility,
          ),
        )
        .toList(growable: false);

    return FaceMeshResult(
      landmarks: landmarks,
      boundingBox: Rect.fromLTRB(
        native.bboxLeft,
        native.bboxTop,
        native.bboxRight,
        native.bboxBottom,
      ),
      confidence: native.confidence,
    );
  }
}
