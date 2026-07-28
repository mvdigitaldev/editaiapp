import 'dart:typed_data';
import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../models/tri_mesh.dart';
import '../models/body_region.dart';
import 'mesh_resolution_profile.dart';

/// Malha corporal densa, indexada e anotada por região.
class AdaptiveBodyMesh {
  final Float32List vertices;
  final Float32List uvs;
  final Uint32List indices;
  final Float32List weights;
  final Int32List vertexRegionCodes;
  final Map<BodyRegion, Uint32List> regionTriangleIndices;
  final MeshResolutionProfile profile;
  final Size imageSize;
  final bool isPartial;
  final Rect bounds;

  const AdaptiveBodyMesh({
    required this.vertices,
    required this.uvs,
    required this.indices,
    required this.weights,
    required this.vertexRegionCodes,
    required this.regionTriangleIndices,
    required this.profile,
    required this.imageSize,
    required this.bounds,
    this.isPartial = false,
  });

  int get vertexCount => vertices.length ~/ 2;

  int get triangleCount => indices.length ~/ 3;

  BodyRegion regionAtVertex(int index) {
    if (index < 0 || index >= vertexRegionCodes.length) {
      return BodyRegion.torso;
    }
    final code = vertexRegionCodes[index];
    if (code < 0 || code >= BodyRegion.values.length) {
      return BodyRegion.torso;
    }
    return BodyRegion.values[code];
  }

  bool hasDegenerateTriangles({double epsilon = 1e-8}) {
    for (var t = 0; t < indices.length; t += 3) {
      final a = indices[t];
      final b = indices[t + 1];
      final c = indices[t + 2];
      if (a == b || b == c || a == c) {
        return true;
      }
      final ax = vertices[a * 2];
      final ay = vertices[a * 2 + 1];
      final bx = vertices[b * 2];
      final by = vertices[b * 2 + 1];
      final cx = vertices[c * 2];
      final cy = vertices[c * 2 + 1];
      final area2 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
      if (area2.abs() <= epsilon) {
        return true;
      }
    }
    return false;
  }

  /// Densidade média por região (vértices / área normalizada aproximada).
  Map<BodyRegion, int> vertexCountsByRegion() {
    final counts = <BodyRegion, int>{
      for (final region in BodyRegion.values) region: 0,
    };
    for (final code in vertexRegionCodes) {
      if (code >= 0 && code < BodyRegion.values.length) {
        final region = BodyRegion.values[code];
        counts[region] = (counts[region] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Ponte para o contrato legado usado pelo face/body MLS atual.
  TriMesh toTriMesh() {
    final legacyRegions = <MeshRegion, List<int>>{};
    for (final entry in regionTriangleIndices.entries) {
      final legacy = _toMeshRegion(entry.key);
      if (legacy == null) {
        continue;
      }
      legacyRegions.putIfAbsent(legacy, () => []).addAll(entry.value);
    }

    return TriMesh(
      vertices: vertices,
      uvs: uvs,
      indices: indices,
      isPartial: isPartial,
      regionBuffers: {
        for (final entry in legacyRegions.entries)
          entry.key: Uint32List.fromList(entry.value),
      },
    );
  }

  static MeshRegion? _toMeshRegion(BodyRegion region) {
    return switch (region) {
      BodyRegion.torso ||
      BodyRegion.chest ||
      BodyRegion.waist ||
      BodyRegion.hip ||
      BodyRegion.butt ||
      BodyRegion.shoulders =>
        MeshRegion.torso,
      BodyRegion.leftArm || BodyRegion.leftForearm => MeshRegion.leftArm,
      BodyRegion.rightArm || BodyRegion.rightForearm => MeshRegion.rightArm,
      BodyRegion.leftThigh || BodyRegion.leftCalf => MeshRegion.leftLeg,
      BodyRegion.rightThigh || BodyRegion.rightCalf => MeshRegion.rightLeg,
      BodyRegion.neck => MeshRegion.neck,
    };
  }
}
