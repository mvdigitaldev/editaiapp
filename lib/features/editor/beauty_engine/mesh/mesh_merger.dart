import 'dart:typed_data';

import '../models/mesh_region.dart';
import '../models/tri_mesh.dart';
import 'mesh_topology.dart';
import 'mesh_utils.dart';

/// Combina malha facial + corporal com ponte de pescoco.
class MeshMerger {
  const MeshMerger();

  TriMesh merge(TriMesh face, TriMesh body) {
    if (body.vertices.isEmpty) {
      return face;
    }
    if (face.vertices.isEmpty) {
      return body;
    }

    final faceVertexCount = face.vertices.length ~/ 2;
    final bodyVertexCount = body.vertices.length ~/ 2;

    final mergedVertices = Float32List(face.vertices.length + body.vertices.length);
    mergedVertices.setRange(0, face.vertices.length, face.vertices);
    mergedVertices.setRange(face.vertices.length, mergedVertices.length, body.vertices);

    final mergedUvs = Float32List(face.uvs.length + body.uvs.length);
    mergedUvs.setRange(0, face.uvs.length, face.uvs);
    mergedUvs.setRange(face.uvs.length, mergedUvs.length, body.uvs);

    final mergedIndices = <int>[
      ...face.indices,
      for (final index in body.indices) index + faceVertexCount,
    ];

    final neckTriangles = <int>[];
    const chin = 152;
    const jawLeft = 377;
    const jawRight = 400;
    final leftShoulder = faceVertexCount + 11;
    final rightShoulder = faceVertexCount + 12;

    if (chin < faceVertexCount &&
        leftShoulder < faceVertexCount + bodyVertexCount &&
        rightShoulder < faceVertexCount + bodyVertexCount) {
      neckTriangles.addAll([chin, leftShoulder, rightShoulder]);
      if (jawLeft < faceVertexCount) {
        neckTriangles.addAll([jawLeft, chin, leftShoulder]);
      }
      if (jawRight < faceVertexCount) {
        neckTriangles.addAll([jawRight, chin, rightShoulder]);
      }
    }

    for (final entry in MeshTopology.neckBridgePairs.entries) {
      final faceIdx = entry.key;
      final poseIdx = entry.value;
      if (faceIdx >= faceVertexCount || poseIdx >= bodyVertexCount || faceIdx == chin) {
        continue;
      }
      neckTriangles.addAll([faceIdx, faceVertexCount + poseIdx, chin]);
    }

    mergedIndices.addAll(neckTriangles);

    final filtered = MeshUtils.filterDegenerateTriangles(
      mergedVertices,
      Uint32List.fromList(mergedIndices),
    );

    final mergedRegionBuffers = _mergeRegionBuffers(
      face,
      body,
      faceVertexCount,
      neckTriangles,
    );

    return TriMesh(
      vertices: mergedVertices,
      uvs: mergedUvs,
      indices: filtered,
      regionBuffers: mergedRegionBuffers,
      isPartial: body.isPartial,
    );
  }

  Map<MeshRegion, Uint32List> _mergeRegionBuffers(
    TriMesh face,
    TriMesh body,
    int faceVertexOffset,
    List<int> neckTriangles,
  ) {
    final merged = <MeshRegion, Uint32List>{
      for (final entry in face.regionBuffers.entries) entry.key: entry.value,
    };

    for (final entry in body.regionBuffers.entries) {
      final offsetIndices = entry.value.map((i) => i + faceVertexOffset).toList();
      merged[entry.key] = Uint32List.fromList(offsetIndices);
    }

    if (neckTriangles.isNotEmpty) {
      merged[MeshRegion.neck] = Uint32List.fromList(neckTriangles);
    }

    return merged;
  }
}
