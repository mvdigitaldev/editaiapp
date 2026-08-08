import 'dart:typed_data';
import 'dart:ui';

import '../../filters/face/face_warp_utils.dart';
import '../../models/tri_mesh.dart';

/// Campo de deslocamento por landmark após resolução do ACE.
class ConstrainedVertexField {
  ConstrainedVertexField({
    required this.displacements,
    required this.landmarkCount,
    this.clampedVertices = 0,
    this.foldReducedTriangles = 0,
    this.rigidPinnedVertices = 0,
  }) : assert(displacements.length == landmarkCount * 2);

  final Float32List displacements;
  final int landmarkCount;
  final int clampedVertices;
  final int foldReducedTriangles;
  final int rigidPinnedVertices;

  static ConstrainedVertexField zero({int landmarkCount = 478}) {
    return ConstrainedVertexField(
      displacements: Float32List(landmarkCount * 2),
      landmarkCount: landmarkCount,
    );
  }

  Offset displacementAt(int index) {
    if (index < 0 || index >= landmarkCount) {
      return Offset.zero;
    }
    final i = index * 2;
    return Offset(displacements[i], displacements[i + 1]);
  }

  Offset deformedVertex(TriMesh mesh, int index) {
    final base = FaceWarpUtils.vertexAt(mesh, index);
    if (base == null) {
      return Offset.zero;
    }
    return base + displacementAt(index);
  }

  double maxDisplacementMagnitude() {
    var max = 0.0;
    for (var i = 0; i < landmarkCount; i++) {
      final d = displacementAt(i);
      final mag = d.distance;
      if (mag > max) {
        max = mag;
      }
    }
    return max;
  }

  /// Deslocamento máximo em landmarks de zonas dadas (índices).
  double maxDisplacementInIndices(Set<int> indices) {
    var max = 0.0;
    for (final index in indices) {
      final mag = displacementAt(index).distance;
      if (mag > max) {
        max = mag;
      }
    }
    return max;
  }
}
