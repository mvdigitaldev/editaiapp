import 'dart:typed_data';
import 'dart:ui';

import '../models/tri_mesh.dart';
import 'anatomy/constrained_vertex_field.dart';
import 'experimental/global_jacobian_safety_gate.dart';
import 'face_warp_numeric_contract.dart';

/// Resultado do pipeline estrutural obrigatório (Phase 9 + Safety Gate).
class FaceWarpStructuralPipelineResult {
  const FaceWarpStructuralPipelineResult({
    required this.vertexField,
    required this.passed,
    required this.fallbackUsed,
    required this.phase9Iterations,
    required this.converged,
    required this.finalViolationCount,
    required this.minTriangleJacobian,
  });

  final ConstrainedVertexField vertexField;
  final bool passed;
  final String fallbackUsed;
  final int phase9Iterations;
  final bool converged;
  final int finalViolationCount;
  final double minTriangleJacobian;
}

/// Pipeline estrutural congelado — **obrigatório** para deformação facial V3.
///
/// ```
/// displacement → GlobalJacobianConstraint (ε=0.10) → GlobalJacobianSafetyGate
/// ```
///
/// Nenhuma ferramenta facial deve contornar este pipeline.
/// A matemática da Phase 9 permanece em `experimental/` e não é alterada aqui.
abstract final class FaceWarpStructuralPipeline {
  FaceWarpStructuralPipeline._();

  static FaceWarpStructuralPipelineResult apply({
    required TriMesh mesh,
    required ConstrainedVertexField inputField,
    bool enabled = true,
  }) {
    if (!enabled) {
      return FaceWarpStructuralPipelineResult(
        vertexField: inputField,
        passed: true,
        fallbackUsed: 'disabled',
        phase9Iterations: 0,
        converged: true,
        finalViolationCount: 0,
        minTriangleJacobian: double.infinity,
      );
    }

    final vertexCount = _safeVertexCount(mesh, inputField);
    final originalDelta = _fieldToDeltas(inputField, vertexCount);

    final gate = GlobalJacobianSafetyGate.validate(
      mesh: mesh,
      originalDelta: originalDelta,
      epsilon: FaceWarpNumericContract.phase9Epsilon,
    );

    final phase9 = gate.phase9Result;
    final outputField = _deltasToField(
      gate.outputDeltas,
      inputField,
      vertexCount,
    );

    final meshJ = phase9.triangleJacobiansAfter;
    var minJ = double.infinity;
    for (final j in meshJ) {
      if (j < minJ) {
        minJ = j;
      }
    }

    return FaceWarpStructuralPipelineResult(
      vertexField: outputField,
      passed: gate.passed,
      fallbackUsed: gate.fallbackUsed,
      phase9Iterations: phase9.iterations,
      converged: phase9.converged,
      finalViolationCount: phase9.finalViolationCount,
      minTriangleJacobian: minJ.isFinite ? minJ : 0,
    );
  }

  static int _safeVertexCount(TriMesh mesh, ConstrainedVertexField field) {
    final meshVerts = mesh.vertices.length ~/ 2;
    return meshVerts < field.landmarkCount ? meshVerts : field.landmarkCount;
  }

  static List<Offset> _fieldToDeltas(
    ConstrainedVertexField field,
    int vertexCount,
  ) {
    return List.generate(
      vertexCount,
      (i) => field.displacementAt(i),
    );
  }

  static ConstrainedVertexField _deltasToField(
    List<Offset> deltas,
    ConstrainedVertexField source,
    int vertexCount,
  ) {
    final out = Float32List(source.displacements.length);
    out.setRange(0, source.displacements.length, source.displacements);
    for (var i = 0; i < vertexCount && i < deltas.length; i++) {
      final o = i * 2;
      out[o] = deltas[i].dx;
      out[o + 1] = deltas[i].dy;
    }
    return ConstrainedVertexField(
      displacements: out,
      landmarkCount: source.landmarkCount,
      clampedVertices: source.clampedVertices,
      foldReducedTriangles: source.foldReducedTriangles,
      rigidPinnedVertices: source.rigidPinnedVertices,
    );
  }
}
