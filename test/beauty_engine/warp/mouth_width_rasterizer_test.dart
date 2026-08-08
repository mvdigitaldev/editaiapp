import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  test('mouth_width vertex field vs rasterized field', () {
    const imageSize = Size(640, 960);
    const engine = FaceMeshDeformationEngine();
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);
    const params = {'mouth_width': 1.0};

    final vertex = engine.composeVertexField(
      parameters: params,
      context: FaceAnatomyContext(
        face: face,
        imageSize: imageSize,
        mesh: mesh,
      ),
    );
    expect(vertex.displacementAt(61).dx, lessThan(-1.0));

    final field = engine.composeWarpField(
      face: face,
      mesh: mesh,
      imageSize: imageSize,
      parameters: params,
    );
    expect(field!.maxDisplacementMagnitude, greaterThan(0.5),
        reason: 'rasterizer lost mouth_width displacement');
  });
}
