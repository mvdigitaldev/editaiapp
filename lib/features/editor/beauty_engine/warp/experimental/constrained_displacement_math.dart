import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset;

import '../../models/tri_mesh.dart';
import 'triangle_jacobian_math.dart';

/// Coeficientes lineares J = 1 + c0·dx0 + c1·dx1 + c2·dx2 (dy=0).
class TriangleLinearJ {
  const TriangleLinearJ({
    required this.triangleId,
    required this.vertices,
    required this.coefficients,
  });

  final int triangleId;
  final List<int> vertices;
  final List<double> coefficients;

  double jFromDx(List<double> dx) {
    var j = 1.0;
    for (var k = 0; k < 3; k++) {
      j += coefficients[k] * dx[vertices[k]];
    }
    return j;
  }
}

/// Matemática da otimização de displacement (Fase 11, dy=0).
abstract final class ConstrainedDisplacementMath {
  ConstrainedDisplacementMath._();

  static List<TriangleLinearJ> buildLinearTriangleConstraints(TriMesh mesh) {
    final out = <TriangleLinearJ>[];
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];

      final p0x = mesh.vertices[i0 * 2];
      final p0y = mesh.vertices[i0 * 2 + 1];
      final p1x = mesh.vertices[i1 * 2];
      final p1y = mesh.vertices[i1 * 2 + 1];
      final p2x = mesh.vertices[i2 * 2];
      final p2y = mesh.vertices[i2 * 2 + 1];

      final area2 = (p1x - p0x) * (p2y - p0y) - (p2x - p0x) * (p1y - p0y);
      if (area2.abs() < 1e-12) {
        out.add(
          TriangleLinearJ(
            triangleId: t,
            vertices: [i0, i1, i2],
            coefficients: [0, 0, 0],
          ),
        );
        continue;
      }

      final dw0dx = (p1y - p2y) / area2;
      final dw1dx = (p2y - p0y) / area2;
      final dw2dx = (p0y - p1y) / area2;

      out.add(
        TriangleLinearJ(
          triangleId: t,
          vertices: [i0, i1, i2],
          coefficients: [dw0dx, dw1dx, dw2dx],
        ),
      );
    }
    return out;
  }

  static double meshJFromDx(
    TriMesh mesh,
    List<double> dx,
    int i0,
    int i1,
    int i2,
  ) {
    final deltas = List<Offset>.generate(
      dx.length,
      (i) => Offset(dx[i], 0),
    );
    return TriangleJacobianMath.meshTriangleJacobian(mesh, deltas, i0, i1, i2);
  }

  /// Correção mínima L2: Δ = deficit · c / ‖c‖².
  static void applyMinimalLinearCorrection({
    required TriangleLinearJ constraint,
    required List<double> dx,
    required double deficit,
  }) {
    final c = constraint.coefficients;
    final norm = c[0] * c[0] + c[1] * c[1] + c[2] * c[2];
    if (norm < 1e-18) {
      return;
    }
    for (var k = 0; k < 3; k++) {
      final v = constraint.vertices[k];
      dx[v] += deficit * c[k] / norm;
    }
  }

  static List<Set<int>> buildVertexNeighbors(TriMesh mesh, int vertexCount) {
    final neighbors = List.generate(vertexCount, (_) => <int>{});
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 < vertexCount && i1 < vertexCount && i2 < vertexCount) {
        neighbors[i0].addAll([i1, i2]);
        neighbors[i1].addAll([i0, i2]);
        neighbors[i2].addAll([i0, i1]);
      }
    }
    return neighbors;
  }

  static List<double> vertexMargins({
    required List<TriangleLinearJ> constraints,
    required List<double> dx,
    required double epsilon,
    required int vertexCount,
  }) {
    final margins = List<double>.filled(vertexCount, double.infinity);
    for (final c in constraints) {
      final j = c.jFromDx(dx);
      final margin = j - epsilon;
      for (final v in c.vertices) {
        if (margin < margins[v]) {
          margins[v] = margin;
        }
      }
    }
    for (var i = 0; i < vertexCount; i++) {
      if (margins[i].isInfinite) {
        margins[i] = double.infinity;
      }
    }
    return margins;
  }

  static List<Offset> dxToDeltas(List<double> dx) {
    return dx.map((v) => Offset(v, 0)).toList();
  }

  static bool hasNaNOrInf(List<double> dx) {
    for (final v in dx) {
      if (v.isNaN || v.isInfinite) {
        return true;
      }
    }
    return false;
  }
}
