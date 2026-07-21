import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tri_mesh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TriMesh JSON', () {
    test('round-trip preserves vertices and region buffers', () {
      final original = TriMesh(
        vertices: Float32List.fromList([0, 0, 1, 0, 0.5, 1]),
        uvs: Float32List.fromList([0, 0, 1, 0, 0.5, 1]),
        indices: Uint32List.fromList([0, 1, 2]),
        regionBuffers: {
          MeshRegion.jawLeft: Uint32List.fromList([0, 1, 2]),
        },
      );

      final decoded = TriMesh.fromJson(original.toJson());

      expect(decoded.vertices, original.vertices);
      expect(decoded.uvs, original.uvs);
      expect(decoded.indices, original.indices);
      expect(decoded.region(MeshRegion.jawLeft)?.count, 3);
      expect(decoded.regionIndices(MeshRegion.jawLeft), [0, 1, 2]);
    });
  });
}
