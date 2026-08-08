import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent_factory.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_zone.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/constrained_vertex_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/pilot_warp_displacement.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart';
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

  ConstrainedVertexField fieldFor(Map<String, double> parameters) {
    return engine.composeVertexField(
      parameters: parameters,
      context: contextFor(parameters),
    );
  }

  group('Sprint 34 — pilot intents', () {
    test('factory assigns pilot mode to the three contour pilot tools', () {
      final context = contextFor(const {'face_slim': 1.0});
      final intents = AnatomicalIntentFactory.build(
        parameters: const {
          'face_slim': 1.0,
          'nose_slim': 0.5,
          'eye_scale': 0.8,
        },
        context: context,
      );

      final modes = {
        for (final i in intents) i.toolKey: i.mode,
      };
      expect(modes['face_slim'], DeformationMode.pilot);
      expect(modes['nose_slim'], DeformationMode.pilot);
      expect(modes['eye_scale'], DeformationMode.pilot);
    });

    test('B1 face_slim — eyes rigid, jaw moves inward', () {
      final field = fieldFor(const {'face_slim': 1.0});

      expect(
        field.maxDisplacementInIndices(VertexRoleMap.eyeLeft),
        lessThan(0.5),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.eyeRight),
        lessThan(0.5),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.jawLeft),
        greaterThan(2.0),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.jawRight),
        greaterThan(2.0),
      );
    });

    test('B2 nose_slim — jaw and eyes immobile, nose alae move', () {
      final field = fieldFor(const {'nose_slim': 1.0});

      expect(
        field.maxDisplacementInIndices(VertexRoleMap.jawLeft),
        lessThan(0.5),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.eyeLeft),
        lessThan(0.5),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.noseAlae),
        greaterThan(1.0),
      );
    });

    test('B5 eye_scale — eyes scale per-eye, nose rigid', () {
      final field = fieldFor(const {'eye_scale': 1.0});

      expect(
        field.maxDisplacementInIndices(VertexRoleMap.eyeLeft),
        greaterThan(2.0),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.eyeRight),
        greaterThan(2.0),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.noseAlae),
        lessThan(0.5),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.noseDorsum),
        lessThan(0.5),
      );
    });

    test('eye_scale pilot uses per-eye pivot (not face center)', () {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final context = FaceAnatomyContext(
        face: face,
        imageSize: imageSize,
        mesh: mesh,
      );

      final field = engine.composeVertexField(
        parameters: const {'eye_scale': 1.0},
        context: context,
      );

      // Landmark lateral do olho esquerdo deve mover.
      final outerLeft = field.displacementAt(263);
      expect(outerLeft.dx.abs() + outerLeft.dy.abs(), greaterThan(1.0));

      // Nariz (rigid) permanece imóvel.
      expect(field.displacementAt(1).distance, lessThan(0.5));
      expect(PilotWarpDisplacement.pilotToolKeys, contains('eye_scale'));
    });
  });
}
