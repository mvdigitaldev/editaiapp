import 'dart:math' as math;
import 'dart:typed_data';

import '../models/tri_mesh.dart';

/// Hash 2D para buckets espaciais de triângulos.
abstract final class SpatialHash2D {
  static int pack(int x, int y) => (x << 16) ^ (y & 0xFFFF);
}

/// Hit barycentrico dentro de um triângulo da malha.
class BarycentricHit {
  const BarycentricHit({
    required this.i0,
    required this.i1,
    required this.i2,
    required this.w0,
    required this.w1,
    required this.w2,
  });

  final int i0;
  final int i1;
  final int i2;
  final double w0;
  final double w1;
  final double w2;
}

/// Índice espacial O(k) para localizar triângulos em [TriMesh].
class TriMeshSpatialIndex {
  TriMeshSpatialIndex(
    this._mesh, {
    required this.imageWidth,
    required this.imageHeight,
  }) {
    final cell = math.max(
      6.0,
      math.min(imageWidth, imageHeight) / 48,
    );
    _cellSize = cell;
    for (var t = 0; t < _mesh.triangleCount; t++) {
      final i0 = _mesh.indices[t * 3];
      final i1 = _mesh.indices[t * 3 + 1];
      final i2 = _mesh.indices[t * 3 + 2];
      final ax = _mesh.vertices[i0 * 2];
      final ay = _mesh.vertices[i0 * 2 + 1];
      final bx = _mesh.vertices[i1 * 2];
      final by = _mesh.vertices[i1 * 2 + 1];
      final cx = _mesh.vertices[i2 * 2];
      final cy = _mesh.vertices[i2 * 2 + 1];
      final minX = math.min(ax, math.min(bx, cx));
      final maxX = math.max(ax, math.max(bx, cx));
      final minY = math.min(ay, math.min(by, cy));
      final maxY = math.max(ay, math.max(by, cy));
      final x0 = (minX / cell).floor();
      final x1 = (maxX / cell).floor();
      final y0 = (minY / cell).floor();
      final y1 = (maxY / cell).floor();
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          (_triBuckets[SpatialHash2D.pack(x, y)] ??= <int>[]).add(t);
        }
      }
    }
  }

  final TriMesh _mesh;
  final double imageWidth;
  final double imageHeight;
  late final double _cellSize;
  final Map<int, List<int>> _triBuckets = {};

  BarycentricHit? locate(double px, double py) {
    final tri = locateTriangleIndex(px, py);
    if (tri == null) {
      return null;
    }
    return _barycentricInTriangle(tri, px, py);
  }

  /// Índice do triângulo (0…triangleCount-1) que contém o ponto, ou null.
  int? locateTriangleIndex(double px, double py) {
    final cx = (px / _cellSize).floor();
    final cy = (py / _cellSize).floor();
    final candidates = <int>{};
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final bucket = _triBuckets[SpatialHash2D.pack(cx + dx, cy + dy)];
        if (bucket != null) {
          candidates.addAll(bucket);
        }
      }
    }
    for (final t in candidates) {
      if (_barycentricInTriangle(t, px, py) != null) {
        return t;
      }
    }
    return null;
  }

  BarycentricHit? _barycentricInTriangle(int t, double px, double py) {
    final i0 = _mesh.indices[t * 3];
    final i1 = _mesh.indices[t * 3 + 1];
    final i2 = _mesh.indices[t * 3 + 2];
    final ax = _mesh.vertices[i0 * 2];
    final ay = _mesh.vertices[i0 * 2 + 1];
    final bx = _mesh.vertices[i1 * 2];
    final by = _mesh.vertices[i1 * 2 + 1];
    final cxv = _mesh.vertices[i2 * 2];
    final cyv = _mesh.vertices[i2 * 2 + 1];
    final denom = (by - cyv) * (ax - cxv) + (cxv - bx) * (ay - cyv);
    if (denom.abs() < 1e-12) {
      return null;
    }
    final w0 = ((by - cyv) * (px - cxv) + (cxv - bx) * (py - cyv)) / denom;
    final w1 = ((cyv - ay) * (px - cxv) + (ax - cxv) * (py - cyv)) / denom;
    final w2 = 1.0 - w0 - w1;
    if (w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4) {
      return null;
    }
    return BarycentricHit(
      i0: i0,
      i1: i1,
      i2: i2,
      w0: w0,
      w1: w1,
      w2: w2,
    );
  }
}
