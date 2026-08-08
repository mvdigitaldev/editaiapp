import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_influence_map_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_warp_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_field_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../beauty_engine/filters/skin/skin_face_fixture.dart';

void main() {
  const imageSize = Size(640, 960);
  final face = syntheticFace();
  final mesh = const FaceMeshBuilder().build(face, imageSize);

  double dispAt(WarpField field, double nx, double ny) {
    final d = field.sampleDisplacement(Offset(nx, ny));
    final m = field.sampleMask(Offset(nx, ny));
    return d.distance * m;
  }

  test('jaw warp has zero displacement on forehead', () {
    final pipeline = FaceFilterPipeline(
      fieldBuilder: WarpFieldBuilder.forFaceWarp(imageSize),
    );
    final field = pipeline.compose(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      parameters: const {'jaw': 1.0},
    );
    expect(field.isIdentity, isFalse);
    expect(dispAt(field, 0.5, 0.12), lessThan(0.5));
  });

  test('nose_slim displacement concentrated on mid face', () {
    final pipeline = FaceFilterPipeline(
      fieldBuilder: WarpFieldBuilder.forFaceWarp(imageSize),
    );
    final field = pipeline.compose(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      parameters: const {'nose_slim': 1.0},
    );
    final noseDisp = dispAt(field, 0.5, 0.48);
    final jawDisp = dispAt(field, 0.15, 0.82);
    expect(noseDisp, greaterThan(0.5));
    expect(noseDisp, greaterThan(jawDisp));
  });

  test('FaceInfluenceMapBuilder lowerFace is zero above mouth', () {
    final map = FaceInfluenceMapBuilder.build(
      region: FaceWarpRegion.lowerFace,
      face: face,
      imageSize: imageSize,
    );
    expect(map.sampleNormalized(0.5, 0.2), lessThan(0.05));
    expect(map.sampleNormalized(0.5, 0.64), greaterThan(0.05));
  });
}
