import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/face_filter_pipeline.dart';
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
    return d.distance * field.sampleMask(Offset(nx, ny));
  }

  test('nose_slim B2 invariant — jaw untouched at max', () {
    final field = FaceFilterPipeline(
      fieldBuilder: WarpFieldBuilder.forFaceWarp(imageSize),
    ).compose(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      parameters: const {'nose_slim': 1.0},
    );
    final noseDisp = dispAt(field, 0.5, 0.46);
    final jawDisp = dispAt(field, 0.12, 0.85);
    expect(noseDisp, greaterThan(jawDisp));
    expect(noseDisp, greaterThan(0.2));
  });
}
