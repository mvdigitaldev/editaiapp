import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/mesh/face_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/anatomical_intent.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_matte_roi.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/anatomy/face_mesh_deformation_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_mesh_forward_warp.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/face_warp_remap_debug.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  const engine = FaceMeshDeformationEngine();

  Future<void> runCase({
    required String tag,
    required Size imageSize,
  }) async {
    final face = syntheticFace();
    final mesh = const FaceMeshBuilder().build(face, imageSize);
    final vertexField = engine.composeVertexField(
      parameters: const {'face_slim': 0.9},
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
    final payload = FaceMeshForwardPayload(
      mesh: mesh,
      vertexField: vertexField,
      influenceMap: influence,
    );

    final w = imageSize.width.round();
    final h = imageSize.height.round();
    final rgba = _gradientRgba(w, h);

    final paths = FaceWarpRemapDebug.dumpFromPayloadHarness(
      rgba: rgba,
      width: w,
      height: h,
      payload: payload,
      tag: tag,
      runId: 'remap-debug-$tag',
    );

    expect(paths, isNotNull);
  }

  test('fixture 640x960 @90% generates remap debug maps', () async {
    await runCase(tag: 'fixture-640x960-90', imageSize: const Size(640, 960));
  });

  test('lab-res 733x1080 @90% generates remap debug maps', () async {
    await runCase(tag: 'lab-733x1080-90', imageSize: const Size(733, 1080));
  });
}

Uint8List _gradientRgba(int w, int h) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      rgba[o] = x % 256;
      rgba[o + 1] = y % 256;
      rgba[o + 2] = (x + y) % 256;
      rgba[o + 3] = 255;
    }
  }
  return rgba;
}
