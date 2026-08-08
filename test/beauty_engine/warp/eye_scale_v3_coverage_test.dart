import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  test('eye_scale V3 preview has enough grid coverage and displacement', () {
    // ~720p preview edge — cenário parecido com device lab.
    const imageSize = Size(720, 1280);
    const engine = FaceMeshDeformationEngine();
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);

    final field = engine.composeWarpField(
      face: face,
      mesh: mesh,
      imageSize: imageSize,
      parameters: const {'eye_scale': 1.0},
      interactivePreview: true,
    );

    expect(field, isNotNull);
    expect(field!.gridWidth, greaterThanOrEqualTo(80));
    expect(field.maxDisplacementMagnitude, greaterThan(3.0));
    expect(field.activeCellCount ?? 0, greaterThan(24));
  });
}
