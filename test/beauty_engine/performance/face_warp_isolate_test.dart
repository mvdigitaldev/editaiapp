import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/controllers/beauty_engine_controller.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/face_warp_isolate.dart';
import 'package:editaiapp/features/editor/beauty_engine/pose/pose_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_engine_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_field_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../filters/skin/skin_face_fixture.dart';

void main() {
  test('isolate MLS matches sync compose for face_slim', () async {
    final face = syntheticFace();
    const imageSize = Size(720, 960);
    const params = {'face_slim': 0.6};

    final controller = BeautyEngineController(
      faceDetector: FaceMeshDetectorStub(),
      poseDetector: PoseDetectorStub(),
      meshEngine: MeshEngineImpl(),
      warpEngine: WarpEngineStub(),
      gpuRenderer: GPURendererStub(),
    );

    final sync = controller.composeFaceField(
      face: face,
      imageSize: imageSize,
      parameters: params,
    );

    final input = FaceWarpIsolateInput.fromCompose(
      face: face,
      imageSize: imageSize,
      parameters: params,
      quality: WarpFieldQuality.preview,
    );
    final isolated = await FaceWarpIsolateRunner.run(input);

    expect(isolated, isNotNull);
    expect(sync, isNotNull);
    expect(isolated!.gridWidth, sync!.gridWidth);
    expect(isolated.gridHeight, sync.gridHeight);
    expect(isolated.displacement.length, sync.displacement.length);

    var maxDelta = 0.0;
    for (var i = 0; i < sync.displacement.length; i++) {
      final delta = (isolated.displacement[i] - sync.displacement[i]).abs();
      if (delta > maxDelta) {
        maxDelta = delta;
      }
    }
    expect(maxDelta, lessThan(1e-4));
  });
}
