import 'dart:typed_data';

import 'mesh_region.dart';

/// Malha triangulada compartilhada (vertices + UVs + indices).
///
/// Ponte comum entre face MLS, body legado e AdaptiveBodyMesh.toTriMesh().
class TriMesh {
  final Float32List vertices;
  final Float32List uvs;
  final Uint32List indices;

  /// Indices de triangulos (vertex indices) agrupados por regiao.
  final Map<MeshRegion, Uint32List> regionBuffers;

  /// Pose parcial quando malha inclui corpo.
  final bool isPartial;

  const TriMesh({
    required this.vertices,
    required this.uvs,
    required this.indices,
    this.regionBuffers = const {},
    this.isPartial = false,
  });

  /// Intervalo dentro do buffer da regiao (start=0, count=len).
  IndexRange? region(MeshRegion meshRegion) {
    final buffer = regionBuffers[meshRegion];
    if (buffer == null || buffer.isEmpty) {
      return null;
    }
    return IndexRange(start: 0, count: buffer.length);
  }

  /// Indices de triangulos (vertex indices) da regiao.
  Uint32List regionIndices(MeshRegion meshRegion) {
    return regionBuffers[meshRegion] ?? Uint32List(0);
  }

  int get triangleCount => indices.length ~/ 3;

  bool hasDegenerateTriangles() {
    const epsilon = 1e-8;
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

  Map<String, dynamic> toJson() => {
        'vertices': vertices.toList(),
        'uvs': uvs.toList(),
        'indices': indices.toList(),
        'isPartial': isPartial,
        'regionBuffers': {
          for (final entry in regionBuffers.entries)
            entry.key.name: entry.value.toList(),
        },
      };

  factory TriMesh.fromJson(Map<String, dynamic> json) {
    final regionsJson = json['regionBuffers'] as Map<String, dynamic>? ?? {};
    return TriMesh(
      vertices: Float32List.fromList(
        (json['vertices'] as List<dynamic>).cast<num>().map((e) => e.toDouble()).toList(),
      ),
      uvs: Float32List.fromList(
        (json['uvs'] as List<dynamic>).cast<num>().map((e) => e.toDouble()).toList(),
      ),
      indices: Uint32List.fromList(
        (json['indices'] as List<dynamic>).cast<num>().map((e) => e.toInt()).toList(),
      ),
      isPartial: json['isPartial'] as bool? ?? false,
      regionBuffers: regionsJson.map(
        (key, value) => MapEntry(
          MeshRegion.values.byName(key),
          Uint32List.fromList((value as List<dynamic>).cast<int>()),
        ),
      ),
    );
  }
}
