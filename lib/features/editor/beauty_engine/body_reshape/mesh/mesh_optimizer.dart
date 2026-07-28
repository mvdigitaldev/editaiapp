import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/body_region.dart';
import 'adaptive_body_mesh.dart';
import 'mesh_constraints.dart';

/// Deslocamentos por vértice (dx, dy intercalados) — sem control points.
class VertexDisplacementField {
  final Float32List deltas;
  final int vertexCount;
  final bool hadInversionsBeforeOptimize;
  final int antiFoldPassesUsed;
  final int clampedVertices;

  const VertexDisplacementField({
    required this.deltas,
    required this.vertexCount,
    this.hadInversionsBeforeOptimize = false,
    this.antiFoldPassesUsed = 0,
    this.clampedVertices = 0,
  }) : assert(deltas.length == vertexCount * 2);

  bool get isIdentity {
    for (final value in deltas) {
      if (value.abs() > 1e-8) {
        return false;
      }
    }
    return true;
  }

  Offset deltaAt(int index) {
    if (index < 0 || index >= vertexCount) {
      return Offset.zero;
    }
    return Offset(deltas[index * 2], deltas[index * 2 + 1]);
  }

  double magnitudeAt(int index) => deltaAt(index).distance;
}

/// Resultado da otimização: malha deformada + metadados.
class OptimizedMeshResult {
  final AdaptiveBodyMesh mesh;
  final VertexDisplacementField displacements;
  final bool hasInvertedTriangles;

  const OptimizedMeshResult({
    required this.mesh,
    required this.displacements,
    required this.hasInvertedTriangles,
  });
}

/// Torna deslocamentos seguros: clamp regional, bordas fixas, anti-fold.
class MeshOptimizer {
  const MeshOptimizer({
    this.constraints = const MeshConstraints(),
  });

  final MeshConstraints constraints;

  OptimizedMeshResult optimize({
    required AdaptiveBodyMesh source,
    required Float32List rawDeltas,
  }) {
    assert(rawDeltas.length == source.vertexCount * 2);

    final deltas = Float32List.fromList(rawDeltas);
    final fixed = _fixedVertexMask(source);
    _pinFixedVertices(deltas, fixed);

    final clamped = _clampByRegion(source, deltas);
    _pinFixedVertices(deltas, fixed);

    if (constraints.laplacianPasses > 0 && constraints.laplacianBlend > 0) {
      _laplacianSmooth(source, deltas, fixed);
      _pinFixedVertices(deltas, fixed);
      _clampByRegion(source, deltas);
      _pinFixedVertices(deltas, fixed);
    }

    final hadInversion = _hasOrientationFlip(source, deltas);
    final antiFoldPasses = _resolveInversions(source, deltas, fixed);

    final deformed = _apply(source, deltas);
    final field = VertexDisplacementField(
      deltas: deltas,
      vertexCount: source.vertexCount,
      hadInversionsBeforeOptimize: hadInversion,
      antiFoldPassesUsed: antiFoldPasses,
      clampedVertices: clamped,
    );

    return OptimizedMeshResult(
      mesh: deformed,
      displacements: field,
      hasInvertedTriangles: _hasOrientationFlip(source, deltas),
    );
  }

  List<bool> _fixedVertexMask(AdaptiveBodyMesh mesh) {
    final fixed = List<bool>.filled(mesh.vertexCount, false);
    final threshold = constraints.boundaryPinWeightThreshold;
    for (var i = 0; i < mesh.vertexCount; i++) {
      if (mesh.weights[i] <= threshold) {
        fixed[i] = true;
      }
    }
    return fixed;
  }

  void _pinFixedVertices(Float32List deltas, List<bool> fixed) {
    for (var i = 0; i < fixed.length; i++) {
      if (!fixed[i]) {
        continue;
      }
      deltas[i * 2] = 0;
      deltas[i * 2 + 1] = 0;
    }
  }

  int _clampByRegion(AdaptiveBodyMesh mesh, Float32List deltas) {
    var clamped = 0;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      final maxPx = constraints.maxDisplacementPx(region, mesh.imageSize);
      final dx = deltas[i * 2];
      final dy = deltas[i * 2 + 1];
      final mag = math.sqrt(dx * dx + dy * dy);
      if (mag <= maxPx || mag < 1e-12) {
        continue;
      }
      final scale = maxPx / mag;
      deltas[i * 2] = dx * scale;
      deltas[i * 2 + 1] = dy * scale;
      clamped++;
    }
    return clamped;
  }

  void _laplacianSmooth(
    AdaptiveBodyMesh mesh,
    Float32List deltas,
    List<bool> fixed,
  ) {
    final neighbors = _buildAdjacency(mesh);
    final blend = constraints.laplacianBlend;
    for (var pass = 0; pass < constraints.laplacianPasses; pass++) {
      final next = Float32List.fromList(deltas);
      for (var i = 0; i < mesh.vertexCount; i++) {
        if (fixed[i]) {
          continue;
        }
        final adj = neighbors[i];
        if (adj.isEmpty) {
          continue;
        }
        var sx = 0.0;
        var sy = 0.0;
        for (final j in adj) {
          sx += deltas[j * 2];
          sy += deltas[j * 2 + 1];
        }
        sx /= adj.length;
        sy /= adj.length;
        next[i * 2] = deltas[i * 2] * (1 - blend) + sx * blend;
        next[i * 2 + 1] = deltas[i * 2 + 1] * (1 - blend) + sy * blend;
      }
      for (var i = 0; i < deltas.length; i++) {
        deltas[i] = next[i];
      }
    }
  }

  List<List<int>> _buildAdjacency(AdaptiveBodyMesh mesh) {
    final neighbors = List.generate(mesh.vertexCount, (_) => <int>{});
    final indices = mesh.indices;
    for (var t = 0; t < indices.length; t += 3) {
      final a = indices[t];
      final b = indices[t + 1];
      final c = indices[t + 2];
      neighbors[a]
        ..add(b)
        ..add(c);
      neighbors[b]
        ..add(a)
        ..add(c);
      neighbors[c]
        ..add(a)
        ..add(b);
    }
    return [
      for (final set in neighbors) set.toList(growable: false),
    ];
  }

  int _resolveInversions(
    AdaptiveBodyMesh mesh,
    Float32List deltas,
    List<bool> fixed,
  ) {
    var passes = 0;
    for (var iter = 0; iter < constraints.antiFoldIterations; iter++) {
      if (!_hasOrientationFlip(mesh, deltas) &&
          !_hasDegenerate(mesh, deltas)) {
        break;
      }
      passes++;
      // Escala global suave; bordas já pinadas.
      for (var i = 0; i < mesh.vertexCount; i++) {
        if (fixed[i]) {
          continue;
        }
        deltas[i * 2] *= 0.7;
        deltas[i * 2 + 1] *= 0.7;
      }
    }
    return passes;
  }

  bool _hasOrientationFlip(AdaptiveBodyMesh mesh, Float32List deltas) {
    final indices = mesh.indices;
    final verts = mesh.vertices;
    for (var t = 0; t < indices.length; t += 3) {
      final a = indices[t];
      final b = indices[t + 1];
      final c = indices[t + 2];
      final oArea = _area2(
        verts[a * 2],
        verts[a * 2 + 1],
        verts[b * 2],
        verts[b * 2 + 1],
        verts[c * 2],
        verts[c * 2 + 1],
      );
      if (oArea.abs() <= 1e-12) {
        continue;
      }
      final ax = verts[a * 2] + deltas[a * 2];
      final ay = verts[a * 2 + 1] + deltas[a * 2 + 1];
      final bx = verts[b * 2] + deltas[b * 2];
      final by = verts[b * 2 + 1] + deltas[b * 2 + 1];
      final cx = verts[c * 2] + deltas[c * 2];
      final cy = verts[c * 2 + 1] + deltas[c * 2 + 1];
      final nArea = _area2(ax, ay, bx, by, cx, cy);
      if (oArea * nArea < 0) {
        return true;
      }
    }
    return false;
  }

  bool _hasDegenerate(AdaptiveBodyMesh mesh, Float32List deltas) {
    final indices = mesh.indices;
    final verts = mesh.vertices;
    final minArea = constraints.minTriangleArea2;
    for (var t = 0; t < indices.length; t += 3) {
      final a = indices[t];
      final b = indices[t + 1];
      final c = indices[t + 2];
      final ax = verts[a * 2] + deltas[a * 2];
      final ay = verts[a * 2 + 1] + deltas[a * 2 + 1];
      final bx = verts[b * 2] + deltas[b * 2];
      final by = verts[b * 2 + 1] + deltas[b * 2 + 1];
      final cx = verts[c * 2] + deltas[c * 2];
      final cy = verts[c * 2 + 1] + deltas[c * 2 + 1];
      if (_area2(ax, ay, bx, by, cx, cy).abs() <= minArea) {
        return true;
      }
    }
    return false;
  }

  AdaptiveBodyMesh _apply(AdaptiveBodyMesh source, Float32List deltas) {
    final vertices = Float32List(source.vertices.length);
    for (var i = 0; i < source.vertexCount; i++) {
      vertices[i * 2] = source.vertices[i * 2] + deltas[i * 2];
      vertices[i * 2 + 1] = source.vertices[i * 2 + 1] + deltas[i * 2 + 1];
    }
    return AdaptiveBodyMesh(
      vertices: vertices,
      uvs: source.uvs,
      indices: source.indices,
      weights: source.weights,
      vertexRegionCodes: source.vertexRegionCodes,
      regionTriangleIndices: source.regionTriangleIndices,
      profile: source.profile,
      imageSize: source.imageSize,
      bounds: source.bounds,
      isPartial: source.isPartial,
    );
  }

  double _area2(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
  ) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  }
}
