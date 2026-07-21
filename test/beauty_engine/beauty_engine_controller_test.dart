import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/controllers/beauty_engine_controller.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/processing_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/pose/pose_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_engine_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BeautyEngineController stub returns original bytes', () async {
    final controller = BeautyEngineController(
      faceDetector: const FaceMeshDetectorStub(),
      poseDetector: const PoseDetectorStub(),
      meshEngine: const MeshEngineStub(),
      warpEngine: const WarpEngineStub(),
      gpuRenderer: GPURendererStub(),
    );

    final bytes = Uint8List.fromList([1, 2, 3]);
    final source = ImageSource(bytes: bytes, width: 1, height: 1);

    final frame = await controller.process(
      source: source,
      pipeline: const ProcessingPipeline(),
    );

    expect(frame.width, 1);
    expect(frame.height, 1);
    expect(frame.bytes, bytes);
    expect(frame.face, isNull);
    expect(frame.pose, isNull);
  });
}
