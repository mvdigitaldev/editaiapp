import 'dart:ui';

import '../../models/face_mesh_result.dart';
import '../../models/tri_mesh.dart';

/// Contexto para construção de control points faciais.
class FaceWarpContext {
  const FaceWarpContext({
    required this.mesh,
    required this.face,
    required this.imageSize,
    required this.intensity,
    required this.yawFactor,
    this.linkEyes = true,
  });

  final TriMesh mesh;
  final FaceMeshResult face;
  final Size imageSize;
  final double intensity;
  final double yawFactor;
  final bool linkEyes;

  double get effectiveIntensity => (intensity * yawFactor).clamp(0.0, 1.0);

  double get centerX => imageSize.width * 0.5;
}
