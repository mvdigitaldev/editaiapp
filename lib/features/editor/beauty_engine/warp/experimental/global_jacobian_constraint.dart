import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Offset;

import '../../models/tri_mesh.dart';
import 'triangle_jacobian_math.dart';

/// Resultado da constraint global Fase 9.
class GlobalJacobianConstraintResult {
  const GlobalJacobianConstraintResult({
    required this.constrainedDeltas,
    required this.vertexScales,
    required this.constrainedTriangleCount,
    required this.constrainedVertexCount,
    required this.triangleJacobiansBefore,
    required this.triangleJacobiansAfter,
    required this.iterations,
    required this.converged,
    required this.finalViolationCount,
  });

  final List<Offset> constrainedDeltas;
  final Float32List vertexScales;
  final int constrainedTriangleCount;
  final int constrainedVertexCount;
  final List<double> triangleJacobiansBefore;
  final List<double> triangleJacobiansAfter;
  final int iterations;
  final bool converged;
  final int finalViolationCount;
}

/// Fase 9 — solver global Jacobi por escalas de vértice.
///
/// Iteração simultânea (ordem-independente): todos os triângulos leem
/// escalas do início da iteração e propõem reduções via min().
abstract final class GlobalJacobianConstraint {
  GlobalJacobianConstraint._();

  static const defaultEnabled = false;
  static const defaultMaxIterations = 128;
  static const convergenceTolerance = 1e-8;

  static GlobalJacobianConstraintResult apply({
    required TriMesh mesh,
    required List<Offset> effectiveDeltas,
    required double epsilon,
    bool enabled = true,
    int maxIterations = defaultMaxIterations,
    List<int>? triangleOrder,
  }) {
    final vertexCount = effectiveDeltas.length;
    final jBefore = TriangleJacobianMath.allMeshJacobians(mesh, effectiveDeltas);

    if (!enabled || epsilon <= 0) {
      return GlobalJacobianConstraintResult(
        constrainedDeltas: List<Offset>.from(effectiveDeltas),
        vertexScales: Float32List(vertexCount)..fillRange(0, vertexCount, 1.0),
        constrainedTriangleCount: 0,
        constrainedVertexCount: 0,
        triangleJacobiansBefore: jBefore,
        triangleJacobiansAfter: jBefore,
        iterations: 0,
        converged: true,
        finalViolationCount: 0,
      );
    }

    final scales = Float32List(vertexCount)..fillRange(0, vertexCount, 1.0);
    final triOrder = triangleOrder ?? List.generate(mesh.triangleCount, (i) => i);

    var iterations = 0;
    var converged = false;

    for (var iter = 0; iter < maxIterations; iter++) {
      iterations = iter + 1;
      final oldScales = Float32List.fromList(scales);
      final proposals = Float32List.fromList(oldScales);

      var violations = 0;
      for (final t in triOrder) {
        final i0 = mesh.indices[t * 3];
        final i1 = mesh.indices[t * 3 + 1];
        final i2 = mesh.indices[t * 3 + 2];
        if (i0 >= vertexCount || i1 >= vertexCount || i2 >= vertexCount) {
          continue;
        }

        final currentDeltas = _scaledDeltas(
          effectiveDeltas,
          oldScales,
          [i0, i1, i2],
        );
        final j = TriangleJacobianMath.meshTriangleJacobian(
          mesh,
          _fullFromPartial(effectiveDeltas, currentDeltas, [i0, i1, i2]),
          i0,
          i1,
          i2,
        );

        if (j >= epsilon - TriangleJacobianMath.jacobianTolerance) {
          continue;
        }
        violations++;

        final needed = TriangleJacobianMath.minUniformScaleForTriangle(
          mesh: mesh,
          baseDeltas: effectiveDeltas,
          vertexScales: oldScales,
          i0: i0,
          i1: i1,
          i2: i2,
          epsilon: epsilon,
        );

        if (needed >= 1.0 - 1e-9) {
          continue;
        }

        for (final idx in [i0, i1, i2]) {
          proposals[idx] = math.min(proposals[idx], oldScales[idx] * needed);
        }
      }

      if (violations == 0) {
        converged = true;
        break;
      }

      var changed = false;
      for (var i = 0; i < vertexCount; i++) {
        if (proposals[i] < oldScales[i] - convergenceTolerance) {
          scales[i] = proposals[i];
          changed = true;
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

    final jAfter = TriangleJacobianMath.allMeshJacobians(mesh, constrained);
    final finalViolations = TriangleJacobianMath.countBelow(
      jAfter,
      epsilon - TriangleJacobianMath.jacobianTolerance,
    );

    if (finalViolations == 0) {
      converged = true;
    }

    final constrainedVerts = <int>{};
    var constrainedTris = 0;
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 >= vertexCount || i1 >= vertexCount || i2 >= vertexCount) {
        continue;
      }
      var triConstrained = false;
      for (final idx in [i0, i1, i2]) {
        if (scales[idx] < 1.0 - 1e-9) {
          constrainedVerts.add(idx);
          triConstrained = true;
        }
      }
      if (triConstrained) {
        constrainedTris++;
      }
    }

    return GlobalJacobianConstraintResult(
      constrainedDeltas: constrained,
      vertexScales: scales,
      constrainedTriangleCount: constrainedTris,
      constrainedVertexCount: constrainedVerts.length,
      triangleJacobiansBefore: jBefore,
      triangleJacobiansAfter: jAfter,
      iterations: iterations,
      converged: converged && finalViolations == 0,
      finalViolationCount: finalViolations,
    );
  }

  static List<Offset> _scaledDeltas(
    List<Offset> base,
    Float32List scales,
    List<int> indices,
  ) {
    return indices
        .map(
          (i) => Offset(
            base[i].dx * scales[i],
            base[i].dy * scales[i],
          ),
        )
        .toList();
  }

  static List<Offset> _fullFromPartial(
    List<Offset> base,
    List<Offset> partial,
    List<int> indices,
  ) {
    final out = List<Offset>.from(base);
    for (var k = 0; k < indices.length; k++) {
      out[indices[k]] = partial[k];
    }
    return out;
  }
}
