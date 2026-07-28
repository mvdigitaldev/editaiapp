import 'dart:typed_data';
import 'dart:ui';

import '../models/mesh_region.dart';
import '../models/pose_result.dart';
import '../models/tri_mesh.dart';
import 'mesh_topology.dart';
import 'mesh_utils.dart';

/// Converte [PoseResult] (33 landmarks) em malha corporal simplificada.
///
/// Mantido para o pipeline MLS legado. Para Body Reshape V2 use
/// AdaptiveMeshGenerator / MeshEngine.buildAdaptiveBodyMesh.
class BodyMeshBuilder {
  const BodyMeshBuilder();

  TriMesh build(PoseResult pose, Size imageSize) {
    final vertexCount = PoseResult.expectedLandmarkCount;
    final vertices = Float32List(vertexCount * 2);
    final uvs = Float32List(vertexCount * 2);

    for (final landmark in pose.landmarks) {
      final i = landmark.index;
      vertices[i * 2] = landmark.normalized.dx * imageSize.width;
      vertices[i * 2 + 1] = landmark.normalized.dy * imageSize.height;
      uvs[i * 2] = landmark.normalized.dx;
      uvs[i * 2 + 1] = landmark.normalized.dy;
    }

    final rawIndices = Uint32List.fromList(MeshTopology.bodyTriangleIndices);
    final indices = MeshUtils.filterDegenerateTriangles(vertices, rawIndices);
    final regionBuffers = _buildRegionBuffers(indices);

    return TriMesh(
      vertices: vertices,
      uvs: uvs,
      indices: indices,
      regionBuffers: regionBuffers,
      isPartial: pose.isPartial,
    );
  }

  Map<MeshRegion, Uint32List> _buildRegionBuffers(Uint32List indices) {
    final regionTriangles = <MeshRegion, List<int>>{};

    for (var t = 0; t < indices.length; t += 3) {
      final a = indices[t];
      final b = indices[t + 1];
      final c = indices[t + 2];
      final meshRegion = _classifyTriangle(a, b, c);
      if (meshRegion == null) {
        continue;
      }
      regionTriangles.putIfAbsent(meshRegion, () => []).addAll([a, b, c]);
    }

    return {
      for (final entry in regionTriangles.entries)
        entry.key: Uint32List.fromList(entry.value),
    };
  }

  MeshRegion? _classifyTriangle(int a, int b, int c) {
    final verts = {a, b, c};
    MeshRegion? best;
    var bestScore = 0;
    var bestSpecificity = 9999;

    for (final entry in MeshTopology.bodyRegionLandmarks.entries) {
      final score = verts.intersection(entry.value).length;
      if (score == 0) {
        continue;
      }
      final specificity = entry.value.length;
      if (score > bestScore ||
          (score == bestScore && specificity < bestSpecificity)) {
        bestScore = score;
        bestSpecificity = specificity;
        best = entry.key;
      }
    }
    return best;
  }
}
