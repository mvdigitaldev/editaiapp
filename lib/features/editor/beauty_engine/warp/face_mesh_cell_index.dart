import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../mesh/tri_mesh_spatial_index.dart';
import '../models/tri_mesh.dart';

/// Grade espacial célula → índice de triângulo para lookup GPU piecewise-affine.
class FaceMeshCellIndex {
  const FaceMeshCellIndex({
    required this.gridWidth,
    required this.gridHeight,
    required this.cellSize,
    required this.triangleIndices,
  });

  final int gridWidth;
  final int gridHeight;
  final double cellSize;

  /// `-1` = sem triângulo; caso contrário índice em [TriMesh.indices].
  final Int32List triangleIndices;

  factory FaceMeshCellIndex.build({
    required TriMesh mesh,
    required Size imageSize,
    double? cellSize,
  }) {
    final cell = cellSize ??
        math.max(
          6.0,
          math.min(imageSize.width, imageSize.height) / 48,
        );
    final gridW = math.max(1, (imageSize.width / cell).ceil());
    final gridH = math.max(1, (imageSize.height / cell).ceil());
    final out = Int32List(gridW * gridH);
    final index = TriMeshSpatialIndex(
      mesh,
      imageWidth: imageSize.width,
      imageHeight: imageSize.height,
    );

    for (var gy = 0; gy < gridH; gy++) {
      for (var gx = 0; gx < gridW; gx++) {
        final px = (gx + 0.5) * cell;
        final py = (gy + 0.5) * cell;
        final tri = index.locateTriangleIndex(px, py);
        out[gy * gridW + gx] = tri ?? -1;
      }
    }

    return FaceMeshCellIndex(
      gridWidth: gridW,
      gridHeight: gridH,
      cellSize: cell,
      triangleIndices: out,
    );
  }
}
