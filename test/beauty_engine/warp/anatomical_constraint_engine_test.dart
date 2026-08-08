import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_constraint_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_zone.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  const ace = AnatomicalConstraintEngine();

  FaceAnatomyContext ctx() {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);
    return FaceAnatomyContext(face: face, imageSize: imageSize, mesh: mesh);
  }

  AnatomicalIntent faceSlimIntent({double magnitude = 1.0}) {
    return AnatomicalIntent(
      toolKey: 'face_slim',
      primaryZone: AnatomicalZone.cheekLeft,
      mode: DeformationMode.radialInward,
      magnitude: magnitude,
      affectedZones: {
        AnatomicalZone.cheekLeft,
        AnatomicalZone.cheekRight,
        AnatomicalZone.jawLeft,
        AnatomicalZone.jawRight,
      },
      priority: 1,
    );
  }

  test('face_slim pins eyes — zero displacement in eye zones', () {
    final field = ace.compose(
      intents: [faceSlimIntent()],
      context: ctx(),
    );

    expect(
      field.maxDisplacementInIndices(VertexRoleMap.eyeLeft),
      lessThan(0.5),
    );
    expect(
      field.maxDisplacementInIndices(VertexRoleMap.eyeRight),
      lessThan(0.5),
    );
    expect(
      field.maxDisplacementInIndices(VertexRoleMap.noseAlae),
      lessThan(0.5),
    );
    expect(
      field.maxDisplacementInIndices(VertexRoleMap.jawLeft),
      greaterThan(1.0),
    );
  });

  test('conflicting intents reduce opposing displacement on shared vertices', () {
    final context = ctx();
    final inward = faceSlimIntent(magnitude: 1.0);
    final outward = AnatomicalIntent(
      toolKey: 'cheekbone',
      primaryZone: AnatomicalZone.cheekLeft,
      mode: DeformationMode.radialOutward,
      magnitude: 1.0,
      affectedZones: {AnatomicalZone.cheekLeft, AnatomicalZone.cheekRight},
      priority: 2,
    );

    final singleIn = ace.compose(intents: [inward], context: context);
    final singleOut = ace.compose(intents: [outward], context: context);
    final combined = ace.compose(intents: [inward, outward], context: context);

    final cheekIndex = VertexRoleMap.cheekLeft.first;
    final inMag = singleIn.displacementAt(cheekIndex).distance;
    final outMag = singleOut.displacementAt(cheekIndex).distance;
    final combinedMag = combined.displacementAt(cheekIndex).distance;

    expect(inMag, greaterThan(1.0));
    expect(outMag, greaterThan(0.5));
    expect(combinedMag, lessThan(inMag + outMag));
  });

  test('anti-fold limits extreme radial inward displacement', () {
    const extremeAce = AnatomicalConstraintEngine(
      minTriangleAreaRatio: 0.35,
      antiFoldIterations: 3,
    );
    final field = extremeAce.compose(
      intents: [
        AnatomicalIntent(
          toolKey: 'face_slim',
          primaryZone: AnatomicalZone.cheekLeft,
          mode: DeformationMode.radialInward,
          magnitude: 3.0,
          affectedZones: {
            AnatomicalZone.cheekLeft,
            AnatomicalZone.cheekRight,
            AnatomicalZone.jawLeft,
            AnatomicalZone.jawRight,
          },
        ),
      ],
      context: ctx(),
    );

    expect(field.foldReducedTriangles, greaterThan(0));
    expect(field.maxDisplacementMagnitude(), greaterThan(0));
  });

  test('oralCavity always pinned', () {
    final field = ace.compose(
      intents: [
        AnatomicalIntent(
          toolKey: 'smile',
          primaryZone: AnatomicalZone.mouthCorner,
          mode: DeformationMode.translate,
          magnitude: 1.0,
          axis: const Offset(1, -0.3),
          affectedZones: {
            AnatomicalZone.mouthCorner,
            AnatomicalZone.upperLip,
            AnatomicalZone.lowerLip,
          },
          priority: 1,
        ),
      ],
      context: ctx(),
    );

    for (final index in VertexRoleMap.oralCavity) {
      expect(field.displacementAt(index), Offset.zero);
    }
  });

  test('empty intents produce zero field', () {
    final field = ace.compose(intents: const [], context: ctx());
    expect(field.maxDisplacementMagnitude(), 0);
  });
}
