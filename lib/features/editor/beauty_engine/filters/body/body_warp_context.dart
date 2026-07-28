import 'dart:ui';

import '../../models/pose_result.dart';
import '../../models/tri_mesh.dart';
import '../../segment/person_mask.dart';

/// Contexto para filtros warp corporais (Sprint 18–20).
class BodyWarpContext {
  const BodyWarpContext({
    required this.mesh,
    required this.pose,
    required this.imageSize,
    required this.intensity,
    required this.confidenceFactor,
    this.personMask,
  });

  final TriMesh mesh;
  final PoseResult pose;
  final Size imageSize;
  final double intensity;
  final double confidenceFactor;
  final PersonMask? personMask;

  double get effectiveIntensity =>
      (intensity * confidenceFactor).clamp(0.0, 1.0);

  double get centerX => imageSize.width * 0.5;
}
