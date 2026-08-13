import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Offset;

import '../../models/tri_mesh.dart';

/// Resultado da constraint experimental Jacobian-safe.
class JacobianSafeConstraintResult {
  const JacobianSafeConstraintResult({
    required this.constrainedDeltas,
    required this.vertexScales,
    required this.constrainedTriangleCount,
    required this.constrainedVertexCount,
    required this.triangleScales,
    required this.triangleJacobiansBefore,
    required this.triangleJacobiansAfter,
  });

  final List<Offset> constrainedDeltas;
  final Float32List vertexScales;
  final int constrainedTriangleCount;
  final int constrainedVertexCount;
  final List<double> triangleScales;
  final List<double> triangleJacobiansBefore;
  final List<double> triangleJacobiansAfter;
}

/// Protótipo Fase 8 — constraint geométrica local por triângulo.
///
/// Não usado em produção. [enabled] default false fora deste módulo.
abstract final class JacobianSafeConstraint {
  JacobianSafeConstraint._();

  static const defaultEnabled = false;
  static const jacobianTolerance = 1e-4;

  /// Aplica constraint apenas quando [enabled] && [epsilon] > 0.
  /// Caso contrário retorna [effectiveDeltas] inalterado.
  static JacobianSafeConstraintResult apply({
    required TriMesh mesh,
    required List<Offset> effectiveDeltas,
    required double epsilon,
    bool enabled = true,
    int maxIterations = 8,
  }) {
    final vertexCount = effectiveDeltas.length;
    if (!enabled || epsilon <= 0) {
      return JacobianSafeConstraintResult(
        constrainedDeltas: List<Offset>.from(effectiveDeltas),
        vertexScales: Float32List(vertexCount)..fillRange(0, vertexCount, 1.0),
        constrainedTriangleCount: 0,
        constrainedVertexCount: 0,
        triangleScales: List<double>.filled(mesh.triangleCount, 1.0),
        triangleJacobiansBefore: _allTriangleJacobians(mesh, effectiveDeltas),
        triangleJacobiansAfter: _allTriangleJacobians(mesh, effectiveDeltas),
      );
    }

    final scales = Float32List(vertexCount)..fillRange(0, vertexCount, 1.0);
    final triScales = List<double>.filled(mesh.triangleCount, 1.0);
    final jBefore = List<double>.filled(mesh.triangleCount, 1.0);
    final jAfter = List<double>.filled(mesh.triangleCount, 1.0);

    var constrainedTris = 0;
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 >= vertexCount || i1 >= vertexCount || i2 >= vertexCount) {
        continue;
      }
      jBefore[t] = _triangleJacobian(mesh, effectiveDeltas, i0, i1, i2);
    }

    for (var iter = 0; iter < maxIterations; iter++) {
      var changed = false;
      for (var t = 0; t < mesh.triangleCount; t++) {
        final i0 = mesh.indices[t * 3];
        final i1 = mesh.indices[t * 3 + 1];
        final i2 = mesh.indices[t * 3 + 2];
        if (i0 >= vertexCount || i1 >= vertexCount || i2 >= vertexCount) {
          continue;
        }

        final currentDeltas = [
          Offset(
            effectiveDeltas[i0].dx * scales[i0],
            effectiveDeltas[i0].dy * scales[i0],
          ),
          Offset(
            effectiveDeltas[i1].dx * scales[i1],
            effectiveDeltas[i1].dy * scales[i1],
          ),
          Offset(
            effectiveDeltas[i2].dx * scales[i2],
            effectiveDeltas[i2].dy * scales[i2],
          ),
        ];

        final j = _triangleJacobianFromDeltas(
          mesh,
          currentDeltas[0],
          currentDeltas[1],
          currentDeltas[2],
          i0,
          i1,
          i2,
        );
        if (j >= epsilon - jacobianTolerance) {
          continue;
        }

        final needed = _minUniformScaleForEpsilon(
          mesh: mesh,
          baseDeltas: [
            effectiveDeltas[i0],
            effectiveDeltas[i1],
            effectiveDeltas[i2],
          ],
          vertexScales: [scales[i0], scales[i1], scales[i2]],
          i0: i0,
          i1: i1,
          i2: i2,
          epsilon: epsilon,
        );

        if (needed >= 1.0 - 1e-9) {
          continue;
        }

        triScales[t] = math.min(triScales[t], needed);
        for (final idx in [i0, i1, i2]) {
          final next = math.min(scales[idx], needed);
          if (next < scales[idx] - 1e-9) {
            scales[idx] = next;
            changed = true;
          }
        }
      }
      if (!changed) {
        break;
      }
    }

    final constrained = List<Offset>.generate(
      vertexCount,
      (i) => Offset(
        effectiveDeltas[i].dx * scales[i],
        effectiveDeltas[i].dy * scales[i],
      ),
    );

    final constrainedVerts = <int>{};
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 >= vertexCount || i1 >= vertexCount || i2 >= vertexCount) {
        continue;
      }
      jAfter[t] = _triangleJacobian(mesh, constrained, i0, i1, i2);
      if (triScales[t] < 1.0 - 1e-9) {
        constrainedTris++;
      }
      for (final idx in [i0, i1, i2]) {
        if (scales[idx] < 1.0 - 1e-9) {
          constrainedVerts.add(idx);
        }
      }
    }

    return JacobianSafeConstraintResult(
      constrainedDeltas: constrained,
      vertexScales: scales,
      constrainedTriangleCount: constrainedTris,
      constrainedVertexCount: constrainedVerts.length,
      triangleScales: triScales,
      triangleJacobiansBefore: jBefore,
      triangleJacobiansAfter: jAfter,
    );
  }

  static double _triangleJacobian(
    TriMesh mesh,
    List<Offset> deltas,
    int i0,
    int i1,
    int i2,
  ) {
    return _triangleJacobianFromDeltas(
      mesh,
      deltas[i0],
      deltas[i1],
      deltas[i2],
      i0,
      i1,
      i2,
    );
  }

  static double _triangleJacobianFromDeltas(
    TriMesh mesh,
    Offset d0,
    Offset d1,
    Offset d2,
    int i0,
    int i1,
    int i2,
  ) {
    final p0 = Offset(mesh.vertices[i0 * 2], mesh.vertices[i0 * 2 + 1]);
    final p1 = Offset(mesh.vertices[i1 * 2], mesh.vertices[i1 * 2 + 1]);
    final p2 = Offset(mesh.vertices[i2 * 2], mesh.vertices[i2 * 2 + 1]);

    final q0 = p0 + d0;
    final q1 = p1 + d1;
    final q2 = p2 + d2;

    final t1x = p1.dx - p0.dx;
    final t1y = p1.dy - p0.dy;
    final t2x = p2.dx - p0.dx;
    final t2y = p2.dy - p0.dy;
    final detT = t1x * t2y - t1y * t2x;
    if (detT.abs() < 1e-12) {
      return 0.0;
    }

    final g1x = q1.dx - q0.dx;
    final g1y = q1.dy - q0.dy;
    final g2x = q2.dx - q0.dx;
    final g2y = q2.dy - q0.dy;

    final f00 = (g1x * t2y - g2x * t1y) / detT;
    final f01 = (g2x * t1x - g1x * t2x) / detT;
    final f10 = (g1y * t2y - g2y * t1y) / detT;
    final f11 = (g2y * t1x - g1y * t2x) / detT;

    return f00 * f11 - f01 * f10;
  }

  static double _minUniformScaleForEpsilon({
    required TriMesh mesh,
    required List<Offset> baseDeltas,
    required List<double> vertexScales,
    required int i0,
    required int i1,
    required int i2,
    required double epsilon,
  }) {
    var lo = 0.0;
    var hi = 1.0;

    final d0 = Offset(
      baseDeltas[0].dx * vertexScales[0],
      baseDeltas[0].dy * vertexScales[0],
    );
    final d1 = Offset(
      baseDeltas[1].dx * vertexScales[1],
      baseDeltas[1].dy * vertexScales[1],
    );
    final d2 = Offset(
      baseDeltas[2].dx * vertexScales[2],
      baseDeltas[2].dy * vertexScales[2],
    );

    final jAtHi = _triangleJacobianFromDeltas(mesh, d0, d1, d2, i0, i1, i2);
    if (jAtHi >= epsilon) {
      return 1.0;
    }

    for (var i = 0; i < 32; i++) {
      final mid = (lo + hi) / 2;
      final j = _triangleJacobianFromDeltas(
        mesh,
        Offset(d0.dx * mid, d0.dy * mid),
        Offset(d1.dx * mid, d1.dy * mid),
        Offset(d2.dx * mid, d2.dy * mid),
        i0,
        i1,
        i2,
      );
      if (j >= epsilon) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static List<double> _allTriangleJacobians(
    TriMesh mesh,
    List<Offset> deltas,
  ) {
    final out = List<double>.filled(mesh.triangleCount, 1.0);
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 >= deltas.length || i1 >= deltas.length || i2 >= deltas.length) {
        continue;
      }
      out[t] = _triangleJacobian(mesh, deltas, i0, i1, i2);
    }
    return out;
  }

  static double minTriangleJacobian(List<double> jacobians) {
    if (jacobians.isEmpty) {
      return 1.0;
    }
    return jacobians.reduce(math.min);
  }

  static int countFoldTriangles(List<double> jacobians, {double threshold = 0}) {
    var n = 0;
    for (final j in jacobians) {
      if (j < threshold) {
        n++;
      }
    }
    return n;
  }
}
