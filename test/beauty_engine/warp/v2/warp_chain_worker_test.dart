import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/controllers/beauty_engine_controller.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/pose/pose_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/warp_chain_worker.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_engine_stub.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../filters/skin/mvp_benchmark_faces.dart';

BeautyEngineController _controller() => BeautyEngineController(
      faceDetector: const FaceMeshDetectorStub(),
      poseDetector: const PoseDetectorStub(),
      meshEngine: const MeshEngineStub(),
      warpEngine: const WarpEngineStub(),
      gpuRenderer: GPURendererStub(),
    );

Uint8List _pattern(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    bytes[i * 4] = (i * 7) & 0xFF;
    bytes[i * 4 + 1] = (i * 13) & 0xFF;
    bytes[i * 4 + 2] = (i * 29) & 0xFF;
    bytes[i * 4 + 3] = 0xFF;
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isolate da cadeia coincide com a cadeia da UI ao mudar só o último',
      () async {
    final sample = loadAvailableRealBenchmarkFaces().first;
    const width = 160;
    const height = 220;
    final source = _pattern(width, height);
    final params = {'head': -0.6, 'jaw': 0.8, 'cheekbone': 0.3};

    Uint8List clean(Map<String, double> values) {
      final controller = _controller();
      final faceRgba = controller.applyFaceWarpChain(
        sourceRgba: source,
        width: width,
        height: height,
        face: sample.face,
        parameters: values,
      );
      return controller.applyBodyWarpChain(
        sourceRgba: faceRgba,
        width: width,
        height: height,
        pose: null,
        personMask: null,
        parameters: values,
      );
    }

    final worker = WarpChainWorker.instance;
    Future<Uint8List> remote(Map<String, double> values) => worker.apply(
          sourceRgba: source,
          width: width,
          height: height,
          face: sample.face,
          pose: null,
          personMask: null,
          parameters: values,
        );

    final first = await remote(params);
    final expected = clean(params);
    expect(first, orderedEquals(expected));
    expect(first, isNot(orderedEquals(source)));

    final moved = await remote({'head': -0.6, 'jaw': 0.8, 'cheekbone': 0.9});
    expect(
      moved,
      orderedEquals(clean({'head': -0.6, 'jaw': 0.8, 'cheekbone': 0.9})),
    );
    expect(moved, isNot(orderedEquals(first)));
  });
}
