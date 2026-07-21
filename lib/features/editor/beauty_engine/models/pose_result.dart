import 'dart:ui';

import 'pose_landmark.dart';

/// Resultado da detecção de pose (33 landmarks).
class PoseResult {
  static const int expectedLandmarkCount = 33;

  final List<PoseLandmark> landmarks;
  final Rect boundingBox;

  /// `true` quando joelhos/tornozelos não são visíveis (ex.: foto busto).
  final bool isPartial;

  const PoseResult({
    required this.landmarks,
    required this.boundingBox,
    this.isPartial = false,
  });

  Map<String, dynamic> toJson() => {
        'landmarks': landmarks.map((l) => l.toJson()).toList(),
        'boundingBox': {
          'left': boundingBox.left,
          'top': boundingBox.top,
          'right': boundingBox.right,
          'bottom': boundingBox.bottom,
        },
        'isPartial': isPartial,
      };

  factory PoseResult.fromJson(Map<String, dynamic> json) {
    final box = json['boundingBox'] as Map<String, dynamic>;
    return PoseResult(
      landmarks: (json['landmarks'] as List<dynamic>)
          .map((e) => PoseLandmark.fromJson(e as Map<String, dynamic>))
          .toList(),
      boundingBox: Rect.fromLTRB(
        (box['left'] as num).toDouble(),
        (box['top'] as num).toDouble(),
        (box['right'] as num).toDouble(),
        (box['bottom'] as num).toDouble(),
      ),
      isPartial: json['isPartial'] as bool? ?? false,
    );
  }
}
