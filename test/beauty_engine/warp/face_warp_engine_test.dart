import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/config/face_warp_v3_config.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_warp_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_warp_vacancy_fill.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/experimental/global_jacobian_constraint.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/experimental/global_jacobian_safety_gate.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_mvp_operations.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_numeric_contract.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_structural_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  const engine = FaceMeshDeformationEngine();

  FaceAnatomyContext contextFor(Map<String, double> parameters) {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);
    return FaceAnatomyContext(
      face: face,
      imageSize: imageSize,
      mesh: mesh,
    );
  }

  setUp(() {
    FaceWarpV3Config.enabled = true;
    FaceWarpV3Config.useMeshWarpV3 = true;
  });

  group('FaceWarpNumericContract', () {
    test('minimumAcceptedJacobian = epsilon - tolerance', () {
      expect(
        FaceWarpNumericContract.minimumAcceptedJacobian,
        closeTo(0.10 - 1e-6, 1e-12),
      );
    });

    test('accepts Jacobian at epsilon boundary', () {
      expect(
        FaceWarpNumericContract.isJacobianAccepted(
          FaceWarpNumericContract.minimumAcceptedJacobian,
        ),
        isTrue,
      );
    });
  });

  group('FaceWarpMvpOperations', () {
    test('registers 7 MVP operations', () {
      expect(FaceWarpMvpOperations.all.length, 7);
    });

    test('usesMvpMeshPath with combined MVP sliders', () {
      expect(
        FaceWarpMvpOperations.usesMvpMeshPath(const {
          'face_slim': 0.76,
          'narrow_face': 0.80,
        }),
        isTrue,
      );
    });

    test('usesMvpMeshPath false when nose active', () {
      expect(
        FaceWarpMvpOperations.usesMvpMeshPath(const {
          'face_slim': 0.5,
          'nose_slim': 0.3,
        }),
        isFalse,
      );
    });
  });

  group('FaceWarpEngine', () {
    test('intensity 0 produces zero displacement', () {
      final ctx = contextFor(const {'face_slim': 0});
      final mesh = ctx.mesh;
      final field = FaceWarpEngine.composeVertexField(
        parameters: const {'face_slim': 0},
        context: ctx,
        mesh: mesh,
      );
      expect(field.maxDisplacementMagnitude(), lessThan(1e-6));
    });

    test('deterministic — same input same output', () {
      const params = {'face_slim': 0.85};
      final ctx = contextFor(params);
      final mesh = ctx.mesh;

      final a = FaceWarpEngine.composeVertexField(
        parameters: params,
        context: ctx,
        mesh: mesh,
      );
      final b = FaceWarpEngine.composeVertexField(
        parameters: params,
        context: ctx,
        mesh: mesh,
      );

      expect(a.displacements.length, b.displacements.length);
      for (var i = 0; i < a.displacements.length; i++) {
        expect(a.displacements[i], closeTo(b.displacements[i], 1e-9));
      }
    });

    test('multi-tool additive — face_slim preserved when narrow_face added', () {
      const slimOnly = {'face_slim': 0.76};
      const combined = {'face_slim': 0.76, 'narrow_face': 0.80};

      final ctx = contextFor(combined);
      final mesh = ctx.mesh;

      final fieldSlim = engine.composeVertexField(
        parameters: slimOnly,
        context: ctx,
        mesh: mesh,
        applyStructuralPipeline: false,
      );
      final fieldCombined = engine.composeVertexField(
        parameters: combined,
        context: ctx,
        mesh: mesh,
        applyStructuralPipeline: false,
      );

      // Mandíbula: só face_slim atua — displacement deve permanecer.
      final jawIndex = VertexRoleMap.jawLeft.first;
      expect(
        fieldCombined.displacementAt(jawIndex).distance,
        closeTo(fieldSlim.displacementAt(jawIndex).distance, 0.5),
      );

      // Bochecha: narrow_face adiciona componente — combined difere de slim-only.
      final cheekIndex = VertexRoleMap.cheekLeft.first;
      expect(
        fieldCombined.displacementAt(cheekIndex).distance,
        isNot(closeTo(fieldSlim.displacementAt(cheekIndex).distance, 0.01)),
      );
    });

    test('structural pipeline — safety gate passes for face_slim', () {
      const params = {'face_slim': 0.9};
      final ctx = contextFor(params);
      final mesh = ctx.mesh;

      final raw = engine.composeVertexField(
        parameters: params,
        context: ctx,
        mesh: mesh,
        applyStructuralPipeline: false,
      );

      final result = FaceWarpStructuralPipeline.apply(
        mesh: mesh,
        inputField: raw,
      );

      expect(result.passed, isTrue);
      expect(result.fallbackUsed, 'phase9');
      expect(result.minTriangleJacobian,
          greaterThanOrEqualTo(FaceWarpNumericContract.minimumAcceptedJacobian));
      expect(result.converged, isTrue);
      expect(result.finalViolationCount, 0);
    });

    test('Phase 9 solver unchanged — direct call matches gate phase9', () {
      const params = {'face_slim': 0.9};
      final ctx = contextFor(params);
      final mesh = ctx.mesh;
      final raw = engine.composeVertexField(
        parameters: params,
        context: ctx,
        mesh: mesh,
        applyStructuralPipeline: false,
      );

      final vertexCount = mesh.vertices.length ~/ 2;
      final deltas = List.generate(
        vertexCount,
        (i) => raw.displacementAt(i),
      );

      final direct = GlobalJacobianConstraint.apply(
        mesh: mesh,
        effectiveDeltas: deltas,
        epsilon: FaceWarpNumericContract.phase9Epsilon,
      );

      final gate = GlobalJacobianSafetyGate.validate(
        mesh: mesh,
        originalDelta: deltas,
        epsilon: FaceWarpNumericContract.phase9Epsilon,
      );

      expect(gate.phase9Result.iterations, direct.iterations);
      expect(gate.phase9Result.converged, direct.converged);
      expect(
        gate.phase9Result.finalViolationCount,
        direct.finalViolationCount,
      );
      for (var i = 0; i < vertexCount; i++) {
        expect(
          gate.phase9Result.constrainedDeltas[i].dx,
          closeTo(direct.constrainedDeltas[i].dx, 1e-9),
        );
        expect(
          gate.phase9Result.constrainedDeltas[i].dy,
          closeTo(direct.constrainedDeltas[i].dy, 1e-9),
        );
      }
    });
  });

  group('FaceWarpVacancyFill MVP routing', () {
    test('combined MVP uses mesh path', () {
      expect(
        FaceWarpVacancyFill.usesMvpMeshPath(const {
          'face_slim': 0.76,
          'narrow_face': 0.80,
        }),
        isTrue,
      );
    });
  });
}
