import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset;

import '../../models/tri_mesh.dart';
import 'constrained_displacement_math.dart';
import 'global_jacobian_constraint.dart';
import 'triangle_jacobian_math.dart';

/// Resultado Fase 11 — otimização global de displacement.
class GlobalJacobianDisplacementOptimizerResult {
  const GlobalJacobianDisplacementOptimizerResult({
    required this.constrainedDeltas,
    required this.iterations,
    required this.converged,
    required this.finalObjective,
    required this.triangleJacobiansAfter,
    required this.alteredVertexCount,
    required this.iterationLog,
  });

  final List<Offset> constrainedDeltas;
  final int iterations;
  final bool converged;
  final double finalObjective;
  final List<double> triangleJacobiansAfter;
  final int alteredVertexCount;
  final List<Map<String, dynamic>> iterationLog;
}

/// Fase 11 — otimização direta sobre dx com restrições lineares (dy=0).
abstract final class GlobalJacobianDisplacementOptimizer {
  GlobalJacobianDisplacementOptimizer._();

  static const defaultEnabled = false;
  static const defaultLambda = 0.5;
  static const defaultPreserveStep = 0.35;
  static const defaultSmoothStep = 0.25;
  static const defaultMaxIterations = 32;
  static const convergenceTol = 1e-5;
  static const marginRef = 0.15;

  static GlobalJacobianDisplacementOptimizerResult apply({
    required TriMesh mesh,
    required List<Offset> originalDelta,
    required double epsilon,
    bool enabled = true,
    double lambda = defaultLambda,
    double preserveStep = defaultPreserveStep,
    double smoothStep = defaultSmoothStep,
    int maxIterations = defaultMaxIterations,
    List<int>? triangleOrder,
  }) {
    final vertexCount = originalDelta.length;
    final origDx = List<double>.generate(vertexCount, (i) => originalDelta[i].dx);

    final phase9 = GlobalJacobianConstraint.apply(
      mesh: mesh,
      effectiveDeltas: originalDelta,
      epsilon: epsilon,
      enabled: epsilon > 0,
      triangleOrder: triangleOrder,
    );

    if (!enabled || epsilon <= 0) {
      return _resultFromDeltas(
        phase9.constrainedDeltas,
        iterations: 0,
        converged: true,
        objective: _objective(
          dx: List<double>.generate(vertexCount, (i) => phase9.constrainedDeltas[i].dx),
          origDx: origDx,
          mesh: mesh,
          lambda: lambda,
        ),
        mesh: mesh,
        phase9Dx: List<double>.generate(vertexCount, (i) => phase9.constrainedDeltas[i].dx),
        log: const [],
      );
    }

    if (origDx.every((v) => v.abs() < 1e-12)) {
      final zero = List<Offset>.filled(vertexCount, Offset.zero);
      return _resultFromDeltas(
        zero,
        iterations: 0,
        converged: true,
        objective: 0,
        mesh: mesh,
        phase9Dx: origDx,
        log: const [],
      );
    }

    final constraints =
        ConstrainedDisplacementMath.buildLinearTriangleConstraints(mesh);
    final neighbors =
        ConstrainedDisplacementMath.buildVertexNeighbors(mesh, vertexCount);
    final triOrder = triangleOrder ?? List.generate(constraints.length, (i) => i);

    var dx = List<double>.generate(vertexCount, (i) => phase9.constrainedDeltas[i].dx);
    final phase9Dx = List<double>.from(dx);
    final log = <Map<String, dynamic>>[];
    var converged = false;

    for (var iter = 0; iter < maxIterations; iter++) {
      final dxStart = List<double>.from(dx);

      final margins = ConstrainedDisplacementMath.vertexMargins(
        constraints: constraints,
        dx: dx,
        epsilon: epsilon,
        vertexCount: vertexCount,
      );

      for (var v = 0; v < vertexCount; v++) {
        if (origDx[v].abs() < 1e-9) {
          continue;
        }
        final margin = margins[v];
        if (!margin.isFinite || margin <= marginRef * 0.25) {
          continue;
        }
        final w = (margin / (margin + marginRef)).clamp(0.0, 1.0);
        dx[v] += preserveStep * w * (origDx[v] - dx[v]);
      }

      final smoothProposals = List<double>.from(dx);
      for (var v = 0; v < vertexCount; v++) {
        final nbs = neighbors[v];
        if (nbs.isEmpty) {
          continue;
        }
        if (origDx[v].abs() < 1e-9 && dx[v].abs() < 1e-9) {
          continue;
        }

        var weightSum = 0.0;
        var accum = 0.0;
        final vx = mesh.vertices[v * 2];
        final vy = mesh.vertices[v * 2 + 1];
        for (final n in nbs) {
          final dist = math.sqrt(
            math.pow(mesh.vertices[n * 2] - vx, 2) +
                math.pow(mesh.vertices[n * 2 + 1] - vy, 2),
          );
          final w = 1.0 / (dist + 1.0);
          accum += w * dx[n];
          weightSum += w;
        }
        if (weightSum > 0) {
          final avg = accum / weightSum;
          smoothProposals[v] = dx[v] + smoothStep * lambda * (avg - dx[v]);
        }
      }
      dx = smoothProposals;

      for (var proj = 0; proj < 8; proj++) {
        final oldDx = List<double>.from(dx);
        final proposals = List<double>.from(oldDx);
        var violations = 0;

        for (final t in triOrder) {
          final c = constraints[t];
          final j = c.jFromDx(oldDx);
          if (j >= epsilon - TriangleJacobianMath.jacobianTolerance) {
            continue;
          }
          violations++;
          final deficit = epsilon - j + TriangleJacobianMath.jacobianTolerance;
          final cpy = List<double>.from(proposals);
          ConstrainedDisplacementMath.applyMinimalLinearCorrection(
            constraint: c,
            dx: cpy,
            deficit: deficit,
          );
          for (var k = 0; k < 3; k++) {
            final v = c.vertices[k];
            if (origDx[v].abs() > 1e-9) {
              // Correção de segurança move dx em direção a zero (menos extremo).
              if (origDx[v] < 0) {
                proposals[v] = math.max(proposals[v], cpy[v]);
              } else if (origDx[v] > 0) {
                proposals[v] = math.min(proposals[v], cpy[v]);
              } else {
                proposals[v] = cpy[v];
              }
            } else {
              proposals[v] = 0.0;
            }
          }
        }

        if (violations == 0) {
          break;
        }

        var changed = false;
        for (var i = 0; i < vertexCount; i++) {
          if ((proposals[i] - oldDx[i]).abs() > 1e-10) {
            dx[i] = proposals[i];
            changed = true;
          }
        }
        if (!changed) {
          break;
        }
      }

      final obj = _objective(dx: dx, origDx: origDx, mesh: mesh, lambda: lambda);
      var maxDelta = 0.0;
      for (var i = 0; i < vertexCount; i++) {
        maxDelta = math.max(maxDelta, (dx[i] - dxStart[i]).abs());
      }

      log.add({
        'iteration': iter + 1,
        'objective': obj,
        'maxDelta': maxDelta,
        'minJ': _minJ(mesh, dx),
      });

      if (maxDelta < convergenceTol) {
        converged = true;
        break;
      }

      if (ConstrainedDisplacementMath.hasNaNOrInf(dx)) {
        dx = List<double>.from(phase9Dx);
        break;
      }
    }

    _finalSafetyProject(
      dx: dx,
      constraints: constraints,
      epsilon: epsilon,
      origDx: origDx,
      triOrder: triOrder,
    );

    final deltas = ConstrainedDisplacementMath.dxToDeltas(dx);
    final jAfter = TriangleJacobianMath.allMeshJacobians(mesh, deltas);
    final violations = TriangleJacobianMath.countBelow(
      jAfter,
      epsilon - TriangleJacobianMath.jacobianTolerance,
    );

    return _resultFromDeltas(
      deltas,
      iterations: log.length,
      converged: converged && violations == 0,
      objective: _objective(dx: dx, origDx: origDx, mesh: mesh, lambda: lambda),
      mesh: mesh,
      phase9Dx: phase9Dx,
      log: log,
    );
  }

  static void _finalSafetyProject({
    required List<double> dx,
    required List<TriangleLinearJ> constraints,
    required double epsilon,
    required List<double> origDx,
    required List<int> triOrder,
  }) {
    for (var iter = 0; iter < 32; iter++) {
      final oldDx = List<double>.from(dx);
      final proposals = List<double>.from(oldDx);
      var violations = 0;

      for (final t in triOrder) {
        final c = constraints[t];
        final j = c.jFromDx(oldDx);
        if (j >= epsilon - TriangleJacobianMath.jacobianTolerance) {
          continue;
        }
        violations++;
        final deficit = epsilon - j + TriangleJacobianMath.jacobianTolerance;
        final cpy = List<double>.from(proposals);
        ConstrainedDisplacementMath.applyMinimalLinearCorrection(
          constraint: c,
          dx: cpy,
          deficit: deficit,
        );
        for (var k = 0; k < 3; k++) {
          final v = c.vertices[k];
          if (origDx[v].abs() > 1e-9) {
            if (origDx[v] < 0) {
              proposals[v] = math.max(proposals[v], cpy[v]);
            } else if (origDx[v] > 0) {
              proposals[v] = math.min(proposals[v], cpy[v]);
            } else {
              proposals[v] = cpy[v];
            }
          } else {
            proposals[v] = 0.0;
          }
        }
      }

      if (violations == 0) {
        return;
      }

      var changed = false;
      for (var i = 0; i < dx.length; i++) {
        if ((proposals[i] - oldDx[i]).abs() > 1e-10) {
          dx[i] = proposals[i];
          changed = true;
        }
      }
      if (!changed) {
        return;
      }
    }
  }

  static double _objective({
    required List<double> dx,
    required List<double> origDx,
    required TriMesh mesh,
    required double lambda,
  }) {
    var preserve = 0.0;
    for (var i = 0; i < dx.length; i++) {
      final d = dx[i] - origDx[i];
      preserve += d * d;
    }

    final neighbors =
        ConstrainedDisplacementMath.buildVertexNeighbors(mesh, dx.length);
    var smooth = 0.0;
    var edgeCount = 0;
    for (var i = 0; i < dx.length; i++) {
      for (final j in neighbors[i]) {
        if (j > i) {
          final diff = dx[i] - dx[j];
          smooth += diff * diff;
          edgeCount++;
        }
      }
    }

    return preserve + lambda * smooth / math.max(edgeCount, 1);
  }

  static double _minJ(TriMesh mesh, List<double> dx) {
    final deltas = ConstrainedDisplacementMath.dxToDeltas(dx);
    return TriangleJacobianMath.minJacobian(
      TriangleJacobianMath.allMeshJacobians(mesh, deltas),
    );
  }

  static GlobalJacobianDisplacementOptimizerResult _resultFromDeltas(
    List<Offset> deltas, {
    required int iterations,
    required bool converged,
    required double objective,
    required TriMesh mesh,
    required List<double> phase9Dx,
    required List<Map<String, dynamic>> log,
  }) {
    final jAfter = TriangleJacobianMath.allMeshJacobians(mesh, deltas);
    var altered = 0;
    for (var i = 0; i < deltas.length; i++) {
      if ((deltas[i].dx - phase9Dx[i]).abs() > 1e-6) {
        altered++;
      }
    }

    return GlobalJacobianDisplacementOptimizerResult(
      constrainedDeltas: deltas,
      iterations: iterations,
      converged: converged,
      finalObjective: objective,
      triangleJacobiansAfter: jAfter,
      alteredVertexCount: altered,
      iterationLog: log,
    );
  }
}
