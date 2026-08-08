import 'dart:typed_data';
import 'dart:ui';

import '../models/face_mesh_result.dart';
import '../models/mesh_region.dart';
import '../models/tri_mesh.dart';
import 'mesh_topology.dart';
import 'mesh_utils.dart';

/// Converte [FaceMeshResult] (478 landmarks) em malha triangulada MediaPipe.
class FaceMeshBuilder {
  const FaceMeshBuilder();

  TriMesh build(FaceMeshResult face, Size imageSize) {
    final vertexCount = FaceMeshTopology.landmarkCount;
    final vertices = Float32List(vertexCount * 2);
    final uvs = Float32List(vertexCount * 2);

    for (final landmark in face.landmarks) {
      final i = landmark.index;
      if (i < 0 || i >= vertexCount) {
        continue;
      }
      final px = landmark.normalized.dx * imageSize.width;
      final py = landmark.normalized.dy * imageSize.height;
      vertices[i * 2] = px;
      vertices[i * 2 + 1] = py;
      uvs[i * 2] = landmark.normalized.dx;
      uvs[i * 2 + 1] = landmark.normalized.dy;
    }

    final rawIndices = Uint32List.fromList(FaceMeshTopology.triangleIndices);
    final indices = MeshUtils.filterDegenerateTriangles(vertices, rawIndices);
    final regionBuffers = _buildRegionBuffers(indices);

    return TriMesh(
      vertices: vertices,
      uvs: uvs,
      indices: indices,
      regionBuffers: regionBuffers,
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

    for (final entry in MeshTopology.faceRegionLandmarks.entries) {
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
