import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Offset;

import '../../models/tri_mesh.dart';
import 'global_jacobian_constraint.dart';
import 'triangle_jacobian_math.dart';

/// Resultado do smoothing Fase 10.
class JacobianScaleSmoothingResult {
  const JacobianScaleSmoothingResult({
    required this.constrainedDeltas,
    required this.vertexScales,
    required this.scalesBeforeSmoothing,
    required this.smoothingIterations,
    required this.projectionIterations,
    required this.converged,
    required this.triangleJacobiansAfter,
    required this.safetyViolationCount,
  });

  final List<Offset> constrainedDeltas;
  final Float32List vertexScales;
  final Float32List scalesBeforeSmoothing;
  final int smoothingIterations;
  final int projectionIterations;
  final bool converged;
  final List<double> triangleJacobiansAfter;
  final int safetyViolationCount;
}

/// Fase 10 — regularização espacial de escalas pós-GlobalJacobianConstraint.
abstract final class JacobianScaleSmoothing {
  JacobianScaleSmoothing._();

  static const defaultEnabled = false;
  static const defaultMaxSmoothingIterations = 10;

  /// [enabled]=false retorna [phase9Scales] inalterado (baseline Phase 9).
  static JacobianScaleSmoothingResult apply({
    required TriMesh mesh,
    required List<Offset> originalDelta,
    required Float32List phase9Scales,
    required double epsilon,
    double alpha = 0.20,
    bool enabled = true,
    int maxSmoothingIterations = defaultMaxSmoothingIterations,
  }) {
    final vertexCount = originalDelta.length;
    final scales = Float32List.fromList(phase9Scales);
    final beforeSmooth = Float32List.fromList(phase9Scales);

    if (!enabled || alpha <= 0) {
      final deltas = _deltasFromScales(originalDelta, scales);
      final jAfter = TriangleJacobianMath.allMeshJacobians(mesh, deltas);
      return JacobianScaleSmoothingResult(
        constrainedDeltas: deltas,
        vertexScales: scales,
        scalesBeforeSmoothing: beforeSmooth,
        smoothingIterations: 0,
        projectionIterations: 0,
        converged: true,
        triangleJacobiansAfter: jAfter,
        safetyViolationCount: 0,
      );
    }

    final neighbors = _buildVertexNeighbors(mesh, vertexCount);
    var smoothIters = 0;

    for (var iter = 0; iter < maxSmoothingIterations; iter++) {
      smoothIters = iter + 1;
      final old = Float32List.fromList(scales);
      var changed = false;

      for (var v = 0; v < vertexCount; v++) {
        final nbs = neighbors[v];
        if (nbs.isEmpty) {
          continue;
        }

        final smoothed = _weightedNeighborAverage(
          mesh: mesh,
          vertex: v,
          scales: old,
          neighbors: nbs,
          alpha: alpha,
        );

        // Nunca aumentar acima do candidato local sem projection posterior;
        // clamp [0,1] e permitir movimento em direção aos vizinhos.
        final next = smoothed.clamp(0.0, 1.0);
        if ((next - old[v]).abs() > 1e-10) {
          scales[v] = next;
          changed = true;
        }
      }

      final projected = _projectScalesToSafe(
        mesh: mesh,
        originalDelta: originalDelta,
        candidateScales: scales,
        epsilon: epsilon,
      );
      scales.setRange(0, vertexCount, projected.scales);
      if (!changed && projected.converged) {
        break;
      }
    }

    final finalProjection = _projectScalesToSafe(
      mesh: mesh,
      originalDelta: originalDelta,
      candidateScales: scales,
      epsilon: epsilon,
    );
    scales.setRange(0, vertexCount, finalProjection.scales);

    final deltas = _deltasFromScales(originalDelta, scales);
    final jAfter = TriangleJacobianMath.allMeshJacobians(mesh, deltas);
    final violations = TriangleJacobianMath.countBelow(
      jAfter,
      epsilon - TriangleJacobianMath.jacobianTolerance,
    );

    return JacobianScaleSmoothingResult(
      constrainedDeltas: deltas,
      vertexScales: scales,
      scalesBeforeSmoothing: beforeSmooth,
      smoothingIterations: smoothIters,
      projectionIterations: finalProjection.iterations,
      converged: violations == 0 && finalProjection.converged,
      triangleJacobiansAfter: jAfter,
      safetyViolationCount: violations,
    );
  }

  /// Pipeline completo: Phase 9 → smoothing opcional.
  static JacobianScaleSmoothingResult applyPipeline({
    required TriMesh mesh,
    required List<Offset> originalDelta,
    required double epsilon,
    double alpha = 0.20,
    bool smoothingEnabled = true,
    int maxSmoothingIterations = defaultMaxSmoothingIterations,
    List<int>? triangleOrder,
  }) {
    final phase9 = GlobalJacobianConstraint.apply(
      mesh: mesh,
      effectiveDeltas: originalDelta,
      epsilon: epsilon,
      enabled: true,
      triangleOrder: triangleOrder,
    );

    return apply(
      mesh: mesh,
      originalDelta: originalDelta,
      phase9Scales: phase9.vertexScales,
      epsilon: epsilon,
      alpha: alpha,
      enabled: smoothingEnabled,
      maxSmoothingIterations: maxSmoothingIterations,
    );
  }

  /// Extrai scale[v] a partir de original/constrained.
  static Float32List scalesFromDeltas({
    required List<Offset> originalDelta,
    required List<Offset> constrainedDelta,
  }) {
    final scales = Float32List(originalDelta.length);
    for (var i = 0; i < originalDelta.length; i++) {
      scales[i] = _vertexScale(originalDelta[i], constrainedDelta[i]);
    }
    return scales;
  }

  static double _vertexScale(Offset original, Offset constrained) {
    final oMag = original.distance;
    if (oMag < 1e-9) {
      return constrained.distance < 1e-9 ? 1.0 : 0.0;
    }
    return constrained.distance / oMag;
  }

  static List<Offset> _deltasFromScales(
    List<Offset> original,
    Float32List scales,
  ) {
    return List<Offset>.generate(
      original.length,
      (i) => Offset(
        original[i].dx * scales[i],
        original[i].dy * scales[i],
      ),
    );
  }

  static double _weightedNeighborAverage({
    required TriMesh mesh,
    required int vertex,
    required Float32List scales,
    required Set<int> neighbors,
    required double alpha,
  }) {
    final vx = mesh.vertices[vertex * 2];
    final vy = mesh.vertices[vertex * 2 + 1];
    var weightSum = 1.0;
    var accum = scales[vertex];

    for (final n in neighbors) {
      final dx = mesh.vertices[n * 2] - vx;
      final dy = mesh.vertices[n * 2 + 1] - vy;
      final dist = math.sqrt(dx * dx + dy * dy);
      final w = 1.0 / (dist + 1.0);
      accum += w * scales[n];
      weightSum += w;
    }

    final neighborAvg = accum / weightSum;
    return (1 - alpha) * scales[vertex] + alpha * neighborAvg;
  }

  /// Projeção Jacobi: reduz escalas candidatas até J≥epsilon (nunca aumenta).
  static ({
    Float32List scales,
    int iterations,
    bool converged,
  }) _projectScalesToSafe({
    required TriMesh mesh,
    required List<Offset> originalDelta,
    required Float32List candidateScales,
    required double epsilon,
  }) {
    final vertexCount = originalDelta.length;
    final scales = Float32List.fromList(candidateScales);
    final triOrder = List.generate(mesh.triangleCount, (i) => i);

    var iterations = 0;
    var converged = false;

    for (var iter = 0; iter < GlobalJacobianConstraint.defaultMaxIterations; iter++) {
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

        final deltas = _deltasFromScales(originalDelta, oldScales);
        final j = TriangleJacobianMath.meshTriangleJacobian(
          mesh,
          deltas,
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
          baseDeltas: originalDelta,
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
        if (proposals[i] < oldScales[i] - GlobalJacobianConstraint.convergenceTolerance) {
          scales[i] = proposals[i];
          changed = true;
        }
      }

      if (!changed) {
        break;
      }
    }

    return (scales: scales, iterations: iterations, converged: converged);
  }

  static List<Set<int>> _buildVertexNeighbors(TriMesh mesh, int vertexCount) {
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

  /// Assert de segurança — lança se algum triângulo viola epsilon.
  static void assertTriangleSafety({
    required TriMesh mesh,
    required List<Offset> deltas,
    required double epsilon,
    List<int>? failedTrianglesOut,
  }) {
    final failed = <int>[];
    for (var t = 0; t < mesh.triangleCount; t++) {
      final i0 = mesh.indices[t * 3];
      final i1 = mesh.indices[t * 3 + 1];
      final i2 = mesh.indices[t * 3 + 2];
      if (i0 >= deltas.length || i1 >= deltas.length || i2 >= deltas.length) {
        continue;
      }
      final j = TriangleJacobianMath.meshTriangleJacobian(
        mesh,
        deltas,
        i0,
        i1,
        i2,
      );
      if (j < epsilon - TriangleJacobianMath.jacobianTolerance) {
        failed.add(t);
      }
    }
    if (failedTrianglesOut != null) {
      failedTrianglesOut.clear();
      failedTrianglesOut.addAll(failed);
    }
    if (failed.isNotEmpty) {
      throw StateError(
        'jacobian_safety_violation: ${failed.length} triangles below epsilon=$epsilon',
      );
    }
  }
}
