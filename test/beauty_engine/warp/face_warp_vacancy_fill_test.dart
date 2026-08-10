import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_constraint_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent_factory.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_warp_vacancy_fill.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_warp_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  test('vacancy fill adds backward displacement near moved eye vertices', () {
    const imageSize = Size(512, 512);
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);

    const parameters = {'eye_distance': 1.0};
    final context = FaceAnatomyContext(
      face: face,
      imageSize: imageSize,
      mesh: mesh,
    );
    final intents = AnatomicalIntentFactory.build(
      parameters: parameters,
      context: context,
    );
    final vertexField = const AnatomicalConstraintEngine().compose(
      intents: intents,
      context: context,
    );

    expect(vertexField.maxDisplacementMagnitude(), greaterThan(2.0));

    const grid = 80;
    final fieldWithout = FaceMeshWarpRasterizer.rasterizeFromVertexField(
      sourceMesh: mesh,
      vertexField: vertexField,
      imageSize: imageSize,
      region: MeshRegion.faceOval,
      gridWidth: grid,
      gridHeight: grid,
      intensity: 1,
      parameters: const {},
      fse: 120,
    );

    final fieldWith = FaceMeshWarpRasterizer.rasterizeFromVertexField(
      sourceMesh: mesh,
      vertexField: vertexField,
      imageSize: imageSize,
      region: MeshRegion.faceOval,
      gridWidth: grid,
      gridHeight: grid,
      intensity: 1,
      parameters: parameters,
      fse: 120,
    );

    int activeCells(WarpField field) {
      var count = 0;
      for (var i = 0; i < field.mask.length; i++) {
        if (field.mask[i] <= 0.001) continue;
        final dx = field.displacement[i * 2];
        final dy = field.displacement[i * 2 + 1];
        if (dx * dx + dy * dy > 0.25) count++;
      }
      return count;
    }

    expect(activeCells(fieldWith), greaterThan(activeCells(fieldWithout)));
    expect(FaceWarpVacancyFill.hasActiveLateralTool(parameters), isTrue);
  });

  test('face_slim skips grid vacancy fill (mesh path handles disocclusion)', () {
    const imageSize = Size(512, 512);
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);
    const parameters = {'face_slim': 0.9};

    final context = FaceAnatomyContext(
      face: face,
      imageSize: imageSize,
      mesh: mesh,
    );
    final intents = AnatomicalIntentFactory.build(
      parameters: parameters,
      context: context,
    );
    final vertexField = const AnatomicalConstraintEngine().compose(
      intents: intents,
      context: context,
    );

    const grid = 80;
    final fieldNoVacancy = FaceMeshWarpRasterizer.rasterizeFromVertexField(
      sourceMesh: mesh,
      vertexField: vertexField,
      imageSize: imageSize,
      region: MeshRegion.faceOval,
      gridWidth: grid,
      gridHeight: grid,
      intensity: 0.9,
      parameters: parameters,
      fse: 140,
      applyVacancyFill: false,
      directMesh: true,
    );

    final fieldWithVacancy = FaceMeshWarpRasterizer.rasterizeFromVertexField(
      sourceMesh: mesh,
      vertexField: vertexField,
      imageSize: imageSize,
      region: MeshRegion.faceOval,
      gridWidth: grid,
      gridHeight: grid,
      intensity: 0.9,
      parameters: parameters,
      fse: 140,
      applyVacancyFill: true,
      directMesh: true,
    );

    expect(
      FaceWarpVacancyFill.vacancySourceIndices(parameters),
      isEmpty,
    );
    expect(
      fieldWithVacancy.maxDisplacementMagnitude,
      equals(fieldNoVacancy.maxDisplacementMagnitude),
    );
  });
}
