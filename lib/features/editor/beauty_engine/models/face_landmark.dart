import 'dart:ui';

/// Um landmark facial normalizado (0..1) com profundidade opcional.
class FaceLandmark {
  final int index;
  final Offset normalized;
  final double z;
  final double visibility;

  const FaceLandmark({
    required this.index,
    required this.normalized,
    this.z = 0,
    this.visibility = 1,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'x': normalized.dx,
        'y': normalized.dy,
        'z': z,
        'visibility': visibility,
      };

  factory FaceLandmark.fromJson(Map<String, dynamic> json) {
    return FaceLandmark(
      index: json['index'] as int,
      normalized: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      z: (json['z'] as num?)?.toDouble() ?? 0,
      visibility: (json['visibility'] as num?)?.toDouble() ?? 1,
    );
  }
}
