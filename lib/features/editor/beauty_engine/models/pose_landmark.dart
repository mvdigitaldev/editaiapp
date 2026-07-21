import 'dart:ui';

/// Landmark corporal MediaPipe Pose (33 pontos).
class PoseLandmark {
  final int index;
  final Offset normalized;
  final double visibility;

  const PoseLandmark({
    required this.index,
    required this.normalized,
    this.visibility = 1,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'x': normalized.dx,
        'y': normalized.dy,
        'visibility': visibility,
      };

  factory PoseLandmark.fromJson(Map<String, dynamic> json) {
    return PoseLandmark(
      index: json['index'] as int,
      normalized: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      visibility: (json['visibility'] as num?)?.toDouble() ?? 1,
    );
  }
}
