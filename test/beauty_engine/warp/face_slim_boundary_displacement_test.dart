import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/influence_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tri_mesh.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/constrained_vertex_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_matte_roi.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_forward_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_render_contract.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  const engine = FaceMeshDeformationEngine();
  const supportParams = DeformationSupportParams();

  ({
    ConstrainedVertexField field,
    TriMesh mesh,
    InfluenceMap influence,
  }) faceSlimContextAt(double intensity) {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);
    final field = engine.composeVertexField(
      parameters: {'face_slim': intensity},
      context: FaceAnatomyContext(
        face: face,
        imageSize: imageSize,
        mesh: mesh,
      ),
    );
    final influence = FaceMatteRoi.buildInfluenceMap(
      face: face,
      imageSize: imageSize,
      lateralRadiusExpand: 0.07,
    );
    return (field: field, mesh: mesh, influence: influence);
  }

  Float32List supportWeightsFor({
    required ConstrainedVertexField field,
    required TriMesh mesh,
    required InfluenceMap influence,
  }) {
    return GeometricSupport.computeWeights(
      mesh: mesh,
      coreField: field,
      influenceMap: influence,
      params: supportParams,
      imageWidth: imageSize.width.round(),
      imageHeight: imageSize.height.round(),
    );
  }

  ConstrainedVertexField faceSlimFieldAt(double intensity) =>
      faceSlimContextAt(intensity).field;

  group('Face Slim Boundary Displacement — baseline Fase 0', () {
    test('478 ACE slots vs 468 mesh vertices', () {
      final ctx = faceSlimContextAt(0.9);
      expect(ctx.field.landmarkCount, 478);
      expect(ctx.mesh.vertices.length ~/ 2, 468);
      expect(
        FaceWarpFieldMetrics.safeVertexCount(field: ctx.field, mesh: ctx.mesh),
        468,
      );
    });

    test('rigid regions immobile at 100%', () {
      final field = faceSlimFieldAt(1.0);
      for (final indices in [
        VertexRoleMap.eyeLeft,
        VertexRoleMap.eyeRight,
        VertexRoleMap.noseTip,
        VertexRoleMap.upperLip,
      ]) {
        expect(
          field.maxDisplacementInIndices(indices),
          lessThan(0.5),
          reason: 'rigid zone $indices',
        );
      }
    });

    test('jaw lateral displacement at 100%', () {
      final field = faceSlimFieldAt(1.0);
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.jawLeft),
        greaterThan(2.0),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.jawRight),
        greaterThan(2.0),
      );
    });

    test('coreDelta at jaw is predominantly horizontal (inward)', () {
      final ctx = faceSlimContextAt(1.0);
      var maxHoriz = 0.0;
      for (final index in VertexRoleMap.jawLeft) {
        if (index >= FaceWarpFieldMetrics.safeVertexCount(
          field: ctx.field,
          mesh: ctx.mesh,
        )) {
          continue;
        }
        final d = ctx.field.displacementAt(index);
        if (d.dx.abs() > maxHoriz) {
          maxHoriz = d.dx.abs();
        }
        if (d.distance > 0.5) {
          expect(d.dx.abs(), greaterThan(d.dy.abs()),
              reason: 'jaw $index should move horizontally');
        }
      }
      expect(maxHoriz, greaterThan(1.0));
    });

    test('requested field metrics baseline (supportWeight=1)', () {
      final ctx = faceSlimContextAt(0.9);
      final metrics = FaceWarpFieldMetrics.baselineFieldMetrics(
        coreField: ctx.field,
        mesh: ctx.mesh,
        rigidIndices: VertexRoleMap.eyeLeft,
      );

      expect(metrics.requestedDisplacement, greaterThan(2.0));
      expect(metrics.effectiveDisplacement, metrics.requestedDisplacement);
      expect(metrics.displacementRetentionRatio, closeTo(1.0, 1e-6));
      expect(metrics.maxRigidDisplacementPx, lessThan(0.5));
      expect(metrics.displacementContinuityError, isNotNull);

      // ignore: avoid_print
      print('PHASE0_BASELINE face_slim@90%: ${metrics.toJson()}');
    });

    test('retentionRatio N/A on zero-displacement rigid vertices', () {
      final ctx = faceSlimContextAt(1.0);
      for (final index in VertexRoleMap.eyeLeft) {
        final core = ctx.field.displacementAt(index);
        expect(core.distance, lessThan(0.5));
        expect(
          FaceWarpFieldMetrics.retentionRatio(core.distance, 0),
          isNull,
        );
      }
    });

    test('displacement scales monotonically with slider intensity', () {
      final low = faceSlimFieldAt(0.25);
      final high = faceSlimFieldAt(1.0);
      expect(
        high.maxDisplacementInIndices(VertexRoleMap.jawLeft),
        greaterThan(low.maxDisplacementInIndices(VertexRoleMap.jawLeft)),
      );
    });
  });

  group('Face Slim Boundary Displacement — Geometric Support (Fase 2)', () {
    test('supportWeight falls toward zero at exterior', () {
      final ctx = faceSlimContextAt(0.9);
      final weights = supportWeightsFor(
        field: ctx.field,
        mesh: ctx.mesh,
        influence: ctx.influence,
      );
      final count = weights.length;

      final radialPairs = <({double radial, double weight})>[];
      for (var i = 0; i < count; i++) {
        final radial = GeometricSupport.radialNormAt(
          mesh: ctx.mesh,
          vertexIndex: i,
          imageWidth: imageSize.width.round(),
          imageHeight: imageSize.height.round(),
        );
        radialPairs.add((radial: radial, weight: weights[i]));
      }
      radialPairs.sort((a, b) => a.radial.compareTo(b.radial));

      final inner = radialPairs
          .where((p) => p.radial <= 0.75)
          .map((p) => p.weight)
          .toList();
      final outer = radialPairs
          .where((p) => p.radial >= 0.95)
          .map((p) => p.weight)
          .toList();

      expect(inner, isNotEmpty);
      expect(outer, isNotEmpty);
      expect(
        outer.reduce((a, b) => a + b) / outer.length,
        lessThan(inner.reduce((a, b) => a + b) / inner.length),
      );
      expect(outer.every((w) => w < 0.35), isTrue);
    });

    test('effectiveDisplacement < requestedDisplacement in support transition band',
        () {
      final ctx = faceSlimContextAt(0.9);
      final weights = supportWeightsFor(
        field: ctx.field,
        mesh: ctx.mesh,
        influence: ctx.influence,
      );
      final count = FaceWarpFieldMetrics.safeVertexCount(
        field: ctx.field,
        mesh: ctx.mesh,
      );

      var found = false;
      for (var i = 0; i < count; i++) {
        final core = ctx.field.displacementAt(i);
        final requested = core.distance;
        if (requested < 1.0) {
          continue;
        }
        final w = weights[i];
        if (w <= 0.05 || w >= 0.95) {
          continue;
        }
        final effective =
            FaceWarpFieldMetrics.effectiveMagnitude(core, w);
        expect(effective, lessThan(requested));
        found = true;
      }
      expect(found, isTrue, reason: 'transition band with partial support');
    });

    test('no abrupt Support/Zero binary classification jumps', () {
      final ctx = faceSlimContextAt(0.9);
      final weights = supportWeightsFor(
        field: ctx.field,
        mesh: ctx.mesh,
        influence: ctx.influence,
      );
      final count = FaceWarpFieldMetrics.safeVertexCount(
        field: ctx.field,
        mesh: ctx.mesh,
      );
      final mesh = ctx.mesh;
      final seen = <int>{};

      for (var t = 0; t < mesh.indices.length; t += 3) {
        final pairs = [
          (mesh.indices[t], mesh.indices[t + 1]),
          (mesh.indices[t + 1], mesh.indices[t + 2]),
          (mesh.indices[t + 2], mesh.indices[t]),
        ];
        for (final pair in pairs) {
          if (pair.$1 >= count || pair.$2 >= count) {
            continue;
          }
          final key = pair.$1 < pair.$2
              ? pair.$1 * count + pair.$2
              : pair.$2 * count + pair.$1;
          if (seen.contains(key)) {
            continue;
          }
          seen.add(key);
          final jump = (weights[pair.$1] - weights[pair.$2]).abs();
          expect(jump, lessThan(0.55),
              reason: 'edge ${pair.$1}-${pair.$2} jump=$jump');
        }
      }
    });

    test('displacement monotonic toward exterior in support region', () {
      final ctx = faceSlimContextAt(0.9);
      final weights = supportWeightsFor(
        field: ctx.field,
        mesh: ctx.mesh,
        influence: ctx.influence,
      );
      final count = weights.length;

      final bins = List.generate(5, (_) => <double>[]);
      for (var i = 0; i < count; i++) {
        final radial = GeometricSupport.radialNormAt(
          mesh: ctx.mesh,
          vertexIndex: i,
          imageWidth: imageSize.width.round(),
          imageHeight: imageSize.height.round(),
        );
        if (radial < 0.72) {
          continue;
        }
        final bin = ((radial - 0.72) / 0.07).floor().clamp(0, 4);
        bins[bin].add(weights[i]);
      }

      double avg(List<double> xs) =>
          xs.isEmpty ? double.nan : xs.reduce((a, b) => a + b) / xs.length;

      for (var b = 0; b < bins.length - 1; b++) {
        if (bins[b].isEmpty || bins[b + 1].isEmpty) {
          continue;
        }
        expect(avg(bins[b + 1]), lessThanOrEqualTo(avg(bins[b]) + 1e-6),
            reason: 'bin $b → ${b + 1}');
      }
    });

    test('effectiveDelta remains parallel to coreDelta', () {
      final ctx = faceSlimContextAt(0.9);
      final weights = supportWeightsFor(
        field: ctx.field,
        mesh: ctx.mesh,
        influence: ctx.influence,
      );
      final count = FaceWarpFieldMetrics.safeVertexCount(
        field: ctx.field,
        mesh: ctx.mesh,
      );

      for (var i = 0; i < count; i++) {
        final core = ctx.field.displacementAt(i);
        expect(
          FaceWarpFieldMetrics.preservesDirection(core, weights[i]),
          isTrue,
          reason: 'vertex $i',
        );
      }
    });

    test('rigid vertices remain immobile with support applied', () {
      final ctx = faceSlimContextAt(0.9);
      final weights = supportWeightsFor(
        field: ctx.field,
        mesh: ctx.mesh,
        influence: ctx.influence,
      );
      final metrics = FaceWarpFieldMetrics.computeFieldMetrics(
        coreField: ctx.field,
        mesh: ctx.mesh,
        supportWeights: weights,
        rigidIndices: VertexRoleMap.eyeLeft,
      );
      expect(metrics.maxRigidDisplacementPx, lessThan(0.5));
    });

    test('identity at slider 0 does not alter pixels', () {
      final ctx = faceSlimContextAt(0);
      const w = 640;
      const h = 960;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 120;
        rgba[i + 1] = 80;
        rgba[i + 2] = 40;
        rgba[i + 3] = 255;
      }
      final payload = FaceMeshForwardPayload(
        mesh: ctx.mesh,
        vertexField: ctx.field,
        influenceMap: ctx.influence,
      );
      final out = FaceMeshForwardWarp.apply(
        rgba: rgba,
        width: w,
        height: h,
        payload: payload,
      );
      expect(out, equals(rgba));
    });

    test('increasing face_slim does not invert jaw direction', () {
      final low = faceSlimContextAt(0.3);
      final high = faceSlimContextAt(0.9);
      for (final index in VertexRoleMap.jawLeft) {
        if (index >= 468) {
          continue;
        }
        final dLow = low.field.displacementAt(index);
        final dHigh = high.field.displacementAt(index);
        if (dLow.distance < 0.5 || dHigh.distance < 0.5) {
          continue;
        }
        expect(dLow.dx.sign, equals(dHigh.dx.sign),
            reason: 'jaw $index horizontal sign');
      }
    });

    test('phase2 field metrics at 90% (with support)', () {
      final ctx = faceSlimContextAt(0.9);
      final weights = supportWeightsFor(
        field: ctx.field,
        mesh: ctx.mesh,
        influence: ctx.influence,
      );
      final metrics = FaceWarpFieldMetrics.computeFieldMetrics(
        coreField: ctx.field,
        mesh: ctx.mesh,
        supportWeights: weights,
        rigidIndices: VertexRoleMap.eyeLeft,
      );

      expect(metrics.requestedDisplacement, greaterThan(2.0));
      expect(metrics.effectiveDisplacement, lessThanOrEqualTo(
        metrics.requestedDisplacement!,
      ));
      expect(metrics.displacementRetentionRatio, lessThan(1.0));
      expect(metrics.maxRigidDisplacementPx, lessThan(0.5));

      const w = 640;
      const h = 960;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 100;
        rgba[i + 1] = 120;
        rgba[i + 2] = 140;
        rgba[i + 3] = 255;
      }
      final render = FaceWarpRenderer.renderFromPayload(
        rgba: rgba,
        width: w,
        height: h,
        payload: FaceMeshForwardPayload(
          mesh: ctx.mesh,
          vertexField: ctx.field,
          influenceMap: ctx.influence,
        ),
      );

      // ignore: avoid_print
      print('PHASE2_METRICS face_slim@90%: ${metrics.toJson()}');
      // ignore: avoid_print
      print('PHASE2_COVERAGE face_slim@90%: ${render.metrics.toJson()}');
    });
  });
}
