import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_warp_utils.dart';
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

  FaceAnatomyContext contextFor({Map<String, double>? parameters}) {
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
      context: contextFor(parameters: parameters),
    );
  }

  group('Sprint 35 — eye + mouth pilot intents', () {
    test('factory assigns pilot mode to all 8 eye/mouth tools', () {
      final context = contextFor();
      final params = {
        for (final key in PilotWarpDisplacement.eyeMouthPilotToolKeys) key: 0.8,
      };
      final intents = AnatomicalIntentFactory.build(
        parameters: params,
        context: context,
      );

      expect(intents.length, PilotWarpDisplacement.eyeMouthPilotToolKeys.length);
      for (final intent in intents) {
        expect(intent.mode, DeformationMode.pilot);
        expect(PilotWarpDisplacement.eyeMouthPilotToolKeys, contains(intent.toolKey));
      }
    });

    test('B5 eye_distance — eyes move apart, nose bridge stretches', () {
      final field = fieldFor(const {'eye_distance': 1.0});

      expect(
        field.maxDisplacementInIndices(VertexRoleMap.eyeLeft),
        greaterThan(1.0),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.eyeRight),
        greaterThan(1.0),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.noseAlae),
        lessThan(0.5),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.noseRoot),
        greaterThan(0.3),
      );

      // Olho esquerdo move para esquerda (dx negativo).
      final leftDisp = field.displacementAt(263);
      expect(leftDisp.dx, lessThan(-0.5));
      final rightDisp = field.displacementAt(33);
      expect(rightDisp.dx, greaterThan(0.5));
    });

    test('B5 eye_height — eyes lift, cheeks rigid', () {
      final field = fieldFor(const {'eye_height': 1.0});

      expect(
        field.maxDisplacementInIndices(VertexRoleMap.eyeLeft),
        greaterThan(1.0),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.cheekLeft),
        lessThan(0.5),
      );
      expect(field.displacementAt(263).dy, lessThan(-0.5));
    });

    test('B5 eye_rotation — per-eye pivot, linkEyes mirrors right eye', () {
      final face = syntheticFace();
      final mesh = const FaceMeshBuilder().build(face, imageSize);
      final linked = engine.composeVertexField(
        parameters: const {'eye_rotation': 1.0},
        context: FaceAnatomyContext(
          face: face,
          imageSize: imageSize,
          mesh: mesh,
          linkEyes: true,
        ),
      );
      final unlinked = engine.composeVertexField(
        parameters: const {'eye_rotation': 1.0},
        context: FaceAnatomyContext(
          face: face,
          imageSize: imageSize,
          mesh: mesh,
          linkEyes: false,
        ),
      );

      expect(
        linked.maxDisplacementInIndices(VertexRoleMap.eyeLeft),
        greaterThan(0.5),
      );
      expect(
        linked.maxDisplacementInIndices(VertexRoleMap.eyeRight),
        greaterThan(0.5),
      );

      final rightLinked = linked.displacementAt(33);
      final rightUnlinked = unlinked.displacementAt(33);
      expect((rightLinked - rightUnlinked).distance, greaterThan(0.1));
    });

    test('double_eyelid moves upper eyelid only', () {
      final field = fieldFor(const {'double_eyelid': 1.0});

      expect(
        field.displacementAt(FaceWarpUtils.upperEyelidLeft.first).dy,
        greaterThan(0.5),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.noseAlae),
        lessThan(0.5),
      );
    });

    test('B6 lip_thickness — lips expand, oral cavity rigid', () {
      final field = fieldFor(const {'lip_thickness': 1.0});

      expect(
        field.maxDisplacementInIndices(VertexRoleMap.upperLip),
        greaterThan(1.0),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.lowerLip),
        greaterThan(1.0),
      );
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.oralCavity),
        lessThan(0.5),
      );

      final upper = field.displacementAt(185);
      expect(upper.dy, lessThan(-0.3));
      expect(field.displacementAt(0).distance, lessThan(0.5),
          reason: 'philtrum/center pinned');
      final lower = field.displacementAt(17);
      expect(lower.distance, lessThan(0.5),
          reason: 'lower lip center pinned');
    });

    test('mouth_width — corners spread horizontally', () {
      final field = fieldFor(const {'mouth_width': 1.0});

      expect(field.displacementAt(61).dx, lessThan(-0.5));
      expect(field.displacementAt(291).dx, greaterThan(0.5));
      expect(field.displacementAt(0).dx.abs(), greaterThan(0.2));
      expect(
        field.maxDisplacementInIndices(VertexRoleMap.jawLeft),
        lessThan(0.5),
      );
    });

    test('smile low intensity — corners only', () {
      final low = fieldFor(const {'smile': 0.4});
      expect(low.displacementAt(61).dy, lessThan(-0.5));
      expect(low.displacementAt(185).distance, lessThan(0.5));
    });

    test('smile high intensity — includes upper lip landmarks', () {
      final high = fieldFor(const {'smile': 1.0});
      expect(high.displacementAt(61).dy, lessThan(-0.5));
      expect(high.displacementAt(185).dy, lessThan(-0.5));
    });
  });
}
