import 'dart:ui';

import 'package:beauty_mediapipe/beauty_mediapipe.dart';

import '../models/pose_landmark.dart';
import '../models/pose_result.dart';

/// Converte resultado nativo MediaPipe → modelo Dart do Beauty Engine.
class PoseLandmarkMapper {
  const PoseLandmarkMapper._();

  /// Limiar de visibility para landmarks inferiores (joelhos/tornozelos).
  static const double visibilityThreshold = 0.5;

  /// Índices MediaPipe Pose — parte inferior do corpo.
  static const lowerBodyIndices = <int>[25, 26, 27, 28];

  /// Índices principais (ombros + quadril) para validar detecção útil.
  static const primaryIndices = <int>[11, 12, 23, 24];

  static PoseResult? toPoseResult(PoseLandmarkerNativeResult native) {
    if (native.landmarks.length != PoseResult.expectedLandmarkCount) {
      return null;
    }

    final landmarks = native.landmarks
        .map(
          (landmark) => PoseLandmark(
            index: landmark.index,
            normalized: Offset(landmark.x, landmark.y),
            visibility: landmark.visibility,
          ),
        )
        .toList(growable: false);

    if (!_hasVisiblePrimaryLandmarks(landmarks)) {
      return null;
    }

    return PoseResult(
      landmarks: landmarks,
      boundingBox: Rect.fromLTRB(
        native.bboxLeft,
        native.bboxTop,
        native.bboxRight,
        native.bboxBottom,
      ),
      isPartial: _isPartialPose(landmarks),
    );
  }

  static bool _hasVisiblePrimaryLandmarks(List<PoseLandmark> landmarks) {
    for (final index in primaryIndices) {
      final landmark = landmarks.firstWhere(
        (item) => item.index == index,
        orElse: () => const PoseLandmark(
          index: -1,
          normalized: Offset.zero,
          visibility: 0,
        ),
      );
      if (landmark.visibility >= visibilityThreshold) {
        return true;
      }
    }
    return false;
  }

  static bool _isPartialPose(List<PoseLandmark> landmarks) {
    for (final index in lowerBodyIndices) {
      final landmark = landmarks.firstWhere(
        (item) => item.index == index,
        orElse: () => const PoseLandmark(
          index: -1,
          normalized: Offset.zero,
          visibility: 0,
        ),
      );
      if (landmark.visibility < visibilityThreshold) {
        return true;
      }
    }
    return false;
  }
}
