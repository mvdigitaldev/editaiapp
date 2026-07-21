import 'dart:ui';

import 'face_landmark.dart';

/// Resultado da detecção facial MediaPipe (478 landmarks).
class FaceMeshResult {
  static const int expectedLandmarkCount = 478;

  final List<FaceLandmark> landmarks;
  final Rect boundingBox;
  final double confidence;

  const FaceMeshResult({
    required this.landmarks,
    required this.boundingBox,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'landmarks': landmarks.map((l) => l.toJson()).toList(),
        'boundingBox': {
          'left': boundingBox.left,
          'top': boundingBox.top,
          'right': boundingBox.right,
          'bottom': boundingBox.bottom,
        },
        'confidence': confidence,
      };

  factory FaceMeshResult.fromJson(Map<String, dynamic> json) {
    final box = json['boundingBox'] as Map<String, dynamic>;
    return FaceMeshResult(
      landmarks: (json['landmarks'] as List<dynamic>)
          .map((e) => FaceLandmark.fromJson(e as Map<String, dynamic>))
          .toList(),
      boundingBox: Rect.fromLTRB(
        (box['left'] as num).toDouble(),
        (box['top'] as num).toDouble(),
        (box['right'] as num).toDouble(),
        (box['bottom'] as num).toDouble(),
      ),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }
}
