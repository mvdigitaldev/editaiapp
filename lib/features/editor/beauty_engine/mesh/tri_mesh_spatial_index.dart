import 'dart:math' as math;
import 'dart:typed_data';

import '../filters/face/face_warp_utils.dart';
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

  double get minWeight => math.min(w0, math.min(w1, w2));
}

/// Índice espacial O(k) para localizar triângulos em [TriMesh].
///
/// Buckets: cada triângulo é registrado em todas as células cujo grid
/// intersecta seu AABB (com margem de 1 célula). Query coleta candidatos
/// numa vizinhança (radius 1 → 3×3, depois 5×5, 7×7) e escolhe o triângulo
/// válido com maior [BarycentricHit.minWeight] (mais “interior”), com
/// desempate por índice menor — evita first-hit arbitrário em shared edges.
class TriMeshSpatialIndex {
  TriMeshSpatialIndex(
    this._mesh, {
    required this.imageWidth,
    required this.imageHeight,
    double barycentricEpsilon = defaultBarycentricEpsilon,
    int bucketMarginCells = 1,
  }) : _barycentricEpsilon = barycentricEpsilon,
       _bucketMarginCells = bucketMarginCells {
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
      final x0 = (minX / cell).floor() - _bucketMarginCells;
      final x1 = (maxX / cell).floor() + _bucketMarginCells;
      final y0 = (minY / cell).floor() - _bucketMarginCells;
      final y1 = (maxY / cell).floor() + _bucketMarginCells;
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          (_triBuckets[SpatialHash2D.pack(x, y)] ??= <int>[]).add(t);
        }
      }
    }
  }

  static const double defaultBarycentricEpsilon = 1e-4;

  final TriMesh _mesh;
  final double imageWidth;
  final double imageHeight;
  final double _barycentricEpsilon;
  final int _bucketMarginCells;
  late final double _cellSize;
  final Map<int, List<int>> _triBuckets = {};

  double get cellSize => _cellSize;

  int get triangleCount => _mesh.triangleCount;

  TriMesh get mesh => _mesh;

  BarycentricHit? locate(
    double px,
    double py, {
    int? coherenceTriangle,
    int? verticalCoherenceTriangle,
    TriMesh? sourceMesh,
    double? preferSourceX,
    double? preferSourceY,
    double? verticalPreferSourceX,
    double? verticalPreferSourceY,
  }) {
    final tri = locateTriangleIndex(
      px,
      py,
      coherenceTriangle: coherenceTriangle,
      verticalCoherenceTriangle: verticalCoherenceTriangle,
      sourceMesh: sourceMesh,
      preferSourceX: preferSourceX,
      preferSourceY: preferSourceY,
      verticalPreferSourceX: verticalPreferSourceX,
      verticalPreferSourceY: verticalPreferSourceY,
    );
    if (tri == null) {
      return null;
    }
    return barycentricInTriangle(tri, px, py);
  }

  /// Índice do triângulo (0…triangleCount-1) que contém o ponto, ou null.
  ///
  /// [coherenceTriangle] — triângulo do pixel anterior na scanline.
  /// [verticalCoherenceTriangle] — triângulo do pixel acima (mesma coluna).
  int? locateTriangleIndex(
    double px,
    double py, {
    int? coherenceTriangle,
    int? verticalCoherenceTriangle,
    TriMesh? sourceMesh,
    double? preferSourceX,
    double? preferSourceY,
    double? verticalPreferSourceX,
    double? verticalPreferSourceY,
  }) {
    final coherencePairs = [
      (coherenceTriangle, preferSourceX, preferSourceY),
      (verticalCoherenceTriangle, verticalPreferSourceX, verticalPreferSourceY),
    ];
    for (final (candidate, prefX, prefY) in coherencePairs) {
      if (candidate == null) {
        continue;
      }
      final hit = barycentricInTriangle(candidate, px, py);
      if (hit == null) {
        continue;
      }
      if (sourceMesh != null &&
          prefX != null &&
          prefY != null &&
          !prefX.isNaN &&
          !prefY.isNaN) {
        final src = _sourceFromHit(sourceMesh, hit);
        if (src != null) {
          final dx = src.srcX - prefX;
          final dy = src.srcY - prefY;
          if (math.sqrt(dx * dx + dy * dy) > 3.0) {
            continue;
          }
        }
      }
      return candidate;
    }

    var valids = _validTrianglesFromBuckets(px, py);
    if (valids.isEmpty) {
      return locateTriangleIndexFullScan(px, py);
    }
    if (valids.length == 1) {
      return valids.first;
    }

    if (sourceMesh != null) {
      final pick = _selectBySourceContinuity(
        sourceMesh: sourceMesh,
        triangles: valids,
        px: px,
        py: py,
        preferSourceX: preferSourceX,
        preferSourceY: preferSourceY,
        verticalPreferSourceX: verticalPreferSourceX,
        verticalPreferSourceY: verticalPreferSourceY,
      );
      if (pick != null) {
        return pick;
      }
    }

    return _selectBestTriangle(valids, px, py);
  }

  List<int> allValidTrianglesAt(double px, double py) =>
      _allValidTriangles(px, py);

  List<int> _allValidTriangles(double px, double py) {
    final valids = <int>[];
    for (var t = 0; t < _mesh.triangleCount; t++) {
      if (barycentricInTriangle(t, px, py) != null) {
        valids.add(t);
      }
    }
    return valids;
  }

  List<int> _validTrianglesFromBuckets(double px, double py) {
    final valids = <int>[];
    final seen = <int>{};
    for (var radius = 1; radius <= 5; radius += 2) {
      for (final t in collectCandidates(px, py, radius: radius)) {
        if (!seen.add(t)) {
          continue;
        }
        if (barycentricInTriangle(t, px, py) != null) {
          valids.add(t);
        }
      }
      if (valids.isNotEmpty) {
        break;
      }
    }
    return valids;
  }

  int? _selectBySourceContinuity({
    required TriMesh sourceMesh,
    required List<int> triangles,
    required double px,
    required double py,
    double? preferSourceX,
    double? preferSourceY,
    double? verticalPreferSourceX,
    double? verticalPreferSourceY,
  }) {
    int? bestTri;
    var bestDist = double.infinity;

    for (final t in triangles) {
      final hit = barycentricInTriangle(t, px, py);
      final src = hit == null ? null : _sourceFromHit(sourceMesh, hit);
      if (src == null) {
        continue;
      }
      var dist = double.infinity;
      if (preferSourceX != null &&
          preferSourceY != null &&
          !preferSourceX.isNaN &&
          !preferSourceY.isNaN) {
        final dx = src.srcX - preferSourceX;
        final dy = src.srcY - preferSourceY;
        dist = math.min(dist, math.sqrt(dx * dx + dy * dy));
      }
      if (verticalPreferSourceX != null &&
          verticalPreferSourceY != null &&
          !verticalPreferSourceX.isNaN &&
          !verticalPreferSourceY.isNaN) {
        final dx = src.srcX - verticalPreferSourceX;
        final dy = src.srcY - verticalPreferSourceY;
        dist = math.min(dist, math.sqrt(dx * dx + dy * dy));
      }
      if (dist == double.infinity) {
        continue;
      }
      if (dist < bestDist - 1e-9 ||
          (dist - bestDist).abs() <= 1e-9 && (bestTri == null || t < bestTri)) {
        bestDist = dist;
        bestTri = t;
      }
    }
    return bestTri ?? _selectBestTriangle(triangles, px, py);
  }

  ({double srcX, double srcY})? _sourceFromHit(
    TriMesh sourceMesh,
    BarycentricHit hit,
  ) {
    final s0 = FaceWarpUtils.vertexAt(sourceMesh, hit.i0);
    final s1 = FaceWarpUtils.vertexAt(sourceMesh, hit.i1);
    final s2 = FaceWarpUtils.vertexAt(sourceMesh, hit.i2);
    if (s0 == null || s1 == null || s2 == null) {
      return null;
    }
    return (
      srcX: hit.w0 * s0.dx + hit.w1 * s1.dx + hit.w2 * s2.dx,
      srcY: hit.w0 * s0.dy + hit.w1 * s1.dy + hit.w2 * s2.dy,
    );
  }

  /// Scan completo — ignora buckets; usado em diagnóstico e paridade.
  int? locateTriangleIndexFullScan(
    double px,
    double py, {
    double? epsilon,
  }) {
    final candidates = List<int>.generate(_mesh.triangleCount, (i) => i);
    return _selectBestTriangle(
      candidates,
      px,
      py,
      epsilon: epsilon ?? _barycentricEpsilon,
    );
  }

  BarycentricHit? locateFullScan(double px, double py, {double? epsilon}) {
    final tri = locateTriangleIndexFullScan(px, py, epsilon: epsilon);
    if (tri == null) {
      return null;
    }
    return barycentricInTriangle(
      tri,
      px,
      py,
      epsilon: epsilon ?? _barycentricEpsilon,
    );
  }

  /// Candidatos determinísticos (ordenados por índice de triângulo).
  List<int> collectCandidates(double px, double py, {int radius = 1}) {
    final cx = (px / _cellSize).floor();
    final cy = (py / _cellSize).floor();
    final seen = <int>{};
    final result = <int>[];
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final bucket = _triBuckets[SpatialHash2D.pack(cx + dx, cy + dy)];
        if (bucket == null) {
          continue;
        }
        for (final t in bucket) {
          if (seen.add(t)) {
            result.add(t);
          }
        }
      }
    }
    result.sort();
    return result;
  }

  ({int cx, int cy}) queryCell(double px, double py) {
    return (cx: (px / _cellSize).floor(), cy: (py / _cellSize).floor());
  }

  BarycentricHit? barycentricInTriangle(
    int t,
    double px,
    double py, {
    double? epsilon,
  }) {
    final eps = epsilon ?? _barycentricEpsilon;
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
    if (w0 < -eps || w1 < -eps || w2 < -eps) {
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

  ({
    double minX,
    double minY,
    double maxX,
    double maxY,
  }) triangleAabb(int t) {
    final i0 = _mesh.indices[t * 3];
    final i1 = _mesh.indices[t * 3 + 1];
    final i2 = _mesh.indices[t * 3 + 2];
    final ax = _mesh.vertices[i0 * 2];
    final ay = _mesh.vertices[i0 * 2 + 1];
    final bx = _mesh.vertices[i1 * 2];
    final by = _mesh.vertices[i1 * 2 + 1];
    final cx = _mesh.vertices[i2 * 2];
    final cy = _mesh.vertices[i2 * 2 + 1];
    return (
      minX: math.min(ax, math.min(bx, cx)),
      minY: math.min(ay, math.min(by, cy)),
      maxX: math.max(ax, math.max(bx, cx)),
      maxY: math.max(ay, math.max(by, cy)),
    );
  }

  int? _selectBestTriangle(
    List<int> candidates,
    double px,
    double py, {
    double? epsilon,
  }) {
    final eps = epsilon ?? _barycentricEpsilon;
    int? bestTri;
    var bestMinW = -1.0;
    var bestArea = double.infinity;

    for (final t in candidates) {
      final hit = barycentricInTriangle(t, px, py, epsilon: eps);
      if (hit == null) {
        continue;
      }
      final minW = hit.minWeight;
      final area = _triangleArea(t);
      if (minW > bestMinW + 1e-9) {
        bestMinW = minW;
        bestArea = area;
        bestTri = t;
      } else if ((minW - bestMinW).abs() <= 1e-9) {
        if (area < bestArea - 1e-9 || (area - bestArea).abs() <= 1e-9 &&
            (bestTri == null || t < bestTri)) {
          bestArea = area;
          bestTri = t;
        }
      }
    }
    return bestTri;
  }

  double _triangleArea(int t) {
    final i0 = _mesh.indices[t * 3];
    final i1 = _mesh.indices[t * 3 + 1];
    final i2 = _mesh.indices[t * 3 + 2];
    final ax = _mesh.vertices[i0 * 2];
    final ay = _mesh.vertices[i0 * 2 + 1];
    final bx = _mesh.vertices[i1 * 2];
    final by = _mesh.vertices[i1 * 2 + 1];
    final cx = _mesh.vertices[i2 * 2];
    final cy = _mesh.vertices[i2 * 2 + 1];
    return ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)).abs() * 0.5;
  }
}
