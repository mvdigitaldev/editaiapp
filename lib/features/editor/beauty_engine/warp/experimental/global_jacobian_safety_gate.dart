import 'package:flutter/material.dart' show Offset;

import '../../models/tri_mesh.dart';
import 'global_jacobian_constraint.dart';
import 'triangle_jacobian_math.dart';

/// Resultado do safety gate experimental (Fase 13).
class GlobalJacobianSafetyGateResult {
  const GlobalJacobianSafetyGateResult({
    required this.outputDeltas,
    required this.passed,
    required this.fallbackUsed,
    required this.phase9Result,
    required this.structuralChecks,
  });

  final List<Offset> outputDeltas;
  final bool passed;
  final String fallbackUsed;
  final GlobalJacobianConstraintResult phase9Result;
  final Map<String, dynamic> structuralChecks;
}

/// Gate experimental de segurança estrutural para Phase 9 (Fases 13–14).
///
/// Autoridade: triangle Jacobian / exact PL. Field FD não participa do PASS/FAIL.
/// NÃO integrado em produção ainda — usado pelo batch validator Fase 14.
abstract final class GlobalJacobianSafetyGate {
  GlobalJacobianSafetyGate._();

  static GlobalJacobianSafetyGateResult validate({
    required TriMesh mesh,
    required List<Offset> originalDelta,
    required double epsilon,
  }) {
    final phase9 = GlobalJacobianConstraint.apply(
      mesh: mesh,
      effectiveDeltas: originalDelta,
      epsilon: epsilon,
      enabled: true,
    );

    final checks = _structuralChecks(
      mesh: mesh,
      deltas: phase9.constrainedDeltas,
      phase9: phase9,
      epsilon: epsilon,
    );

    final passed = checks['allPassed'] == true;

    return GlobalJacobianSafetyGateResult(
      outputDeltas: passed
          ? phase9.constrainedDeltas
          : List<Offset>.from(originalDelta),
      passed: passed,
      fallbackUsed: passed ? 'phase9' : 'original',
      phase9Result: phase9,
      structuralChecks: checks,
    );
  }

  static Map<String, dynamic> _structuralChecks({
    required TriMesh mesh,
    required List<Offset> deltas,
    required GlobalJacobianConstraintResult phase9,
    required double epsilon,
  }) {
    final meshJ = phase9.triangleJacobiansAfter;
    final triFolds = TriangleJacobianMath.countBelow(meshJ, 0);
    final minTriJ = TriangleJacobianMath.minJacobian(meshJ);

    var nanCount = 0;
    var infCount = 0;
    for (final d in deltas) {
      if (d.dx.isNaN || d.dy.isNaN) {
        nanCount++;
      }
      if (d.dx.isInfinite || d.dy.isInfinite) {
        infCount++;
      }
    }

    final checks = {
      'triangleFoldCountZero': triFolds == 0,
      'minTriangleJAboveEpsilon':
          minTriJ >= epsilon - TriangleJacobianMath.jacobianTolerance,
      'nanCountZero': nanCount == 0,
      'infinityCountZero': infCount == 0,
      'converged': phase9.converged,
      'finalViolationCountZero': phase9.finalViolationCount == 0,
      'triangleFoldCount': triFolds,
      'minTriangleJ': minTriJ,
      'nanCount': nanCount,
      'infinityCount': infCount,
      'finalViolationCount': phase9.finalViolationCount,
      'iterations': phase9.iterations,
    };

    checks['allPassed'] =
        checks['triangleFoldCountZero'] == true &&
        checks['minTriangleJAboveEpsilon'] == true &&
        checks['nanCountZero'] == true &&
        checks['infinityCountZero'] == true &&
        checks['converged'] == true &&
        checks['finalViolationCountZero'] == true;

    return checks;
  }
}
