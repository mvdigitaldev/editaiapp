import 'dart:ui';

import '../../models/face_mesh_result.dart';
import '../../models/tri_mesh.dart';
import 'face_warp_utils.dart';

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

  /// Centro geométrico do rosto (landmarks 1/168/152), não o centro da imagem.
  Offset get faceCenter =>
      FaceWarpUtils.faceCenter(face, imageSize) ??
      Offset(imageSize.width * 0.5, imageSize.height * 0.5);

  double get centerX => faceCenter.dx;
}
