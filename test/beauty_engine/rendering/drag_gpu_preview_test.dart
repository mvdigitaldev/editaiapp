import 'dart:io';
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/rendering/fragment_program_warp_backend.dart';
import 'package:editaiapp/features/editor/beauty_engine/controllers/beauty_engine_controller.dart';
import 'package:editaiapp/features/editor/beauty_engine/face_mesh/face_mesh_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/mesh_engine_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/processing_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/pose/pose_detector_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/dense_displacement_pack.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/drag_gpu_preview.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_stub.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/v2/displacement_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_engine_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('amplitude única quando os lados andam juntos', () {
    expect(
      dragUniformScale(
        const {'jaw': 0.2, 'jaw_left': 0.2, 'jaw_right': 0.2},
        const {'jaw': 0.5, 'jaw_left': 0.5, 'jaw_right': 0.5},
        const ['jaw', 'jaw_left', 'jaw_right'],
      ),
      closeTo(2.5, 1e-9),
    );
    expect(
      dragUniformScale(
        const {'jaw': 0.4, 'jaw_left': 0.4, 'jaw_right': 0.2},
        const {'jaw': 0.4, 'jaw_left': 0.1, 'jaw_right': 0.2},
        const ['jaw', 'jaw_left', 'jaw_right'],
      ),
      isNull,
    );
  });

  test('o pacote denso volta ao deslocamento com amplitude 1', () {
    final field = DisplacementField(width: 2, height: 1);
    field.dx[0] = 4.5;
    field.dy[0] = -2.25;
    final packed = DenseDisplacementPack.pack(field);
    final back = DenseDisplacementPack.decode(
      encodedX: packed.rgba[0],
      encodedY: packed.rgba[1],
      scale: packed.scale,
    );
    expect(back.dx, closeTo(4.5, 0.05));
    expect(back.dy, closeTo(-2.25, 0.05));
    final half = DenseDisplacementPack.decode(
      encodedX: packed.rgba[0],
      encodedY: packed.rgba[1],
      scale: packed.scale,
      amplitude: 0.5,
    );
    expect(half.dx, closeTo(2.25, 0.05));
  });

  test('o passe de arrasto não chama toByteData', () {
    final source = File(
      'lib/features/editor/beauty_engine/body_reshape/rendering/fragment_program_warp_backend.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<ui.Image?> paintDisplacement');
    final end = source.indexOf('Future<Uint8List?> apply');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(source.substring(start, end).contains('toByteData'), isFalse);
  });

  test('export e o preview assente não usam o passe de arrasto', () {
    final source = File(
      'lib/features/editor/beauty_engine/controllers/beauty_engine_controller.dart',
    ).readAsStringSync();
    final exportStart = source.indexOf('Future<Uint8List> exportJpeg');
    final next = source.indexOf('Uint8List applyBodyWarpChain', exportStart);
    final export = source.substring(exportStart, next);
    expect(export.contains('renderDragPreview'), isFalse);
    expect(export.contains('_dragGpu'), isFalse);

    final previewStart = source.indexOf('Future<ProcessedFrame> renderPreview');
    final previewEnd = source.indexOf('Future<Image?> renderDragPreview');
    final preview = source.substring(previewStart, previewEnd);
    expect(preview.contains('renderDragPreview'), isFalse);
  });

  test('sem gesto a cadeia coincide consigo mesma', () {
    final controller = BeautyEngineController(
      faceDetector: const FaceMeshDetectorStub(),
      poseDetector: const PoseDetectorStub(),
      meshEngine: const MeshEngineStub(),
      warpEngine: const WarpEngineStub(),
      gpuRenderer: GPURendererStub(),
    );
    final source = Uint8List(8 * 8 * 4);
    for (var i = 0; i < source.length; i++) {
      source[i] = (i * 17) & 255;
    }
    Uint8List run() => controller.applyFaceWarpChain(
          sourceRgba: source,
          width: 8,
          height: 8,
          face: null,
          parameters: const {'jaw': 1, 'v_shape': -1},
        );
    final first = run();
    final second = run();
    expect(first, equals(source));
    expect(second, equals(first));
  });

  test('pele ou slider que não é warp não entram no atalho', () async {
    final controller = BeautyEngineController(
      faceDetector: const FaceMeshDetectorStub(),
      poseDetector: const PoseDetectorStub(),
      meshEngine: const MeshEngineStub(),
      warpEngine: const WarpEngineStub(),
      gpuRenderer: GPURendererStub(),
    );
    final source =
        ImageSource(bytes: Uint8List(8 * 8 * 4), width: 8, height: 8);
    final skin = await controller.renderDragPreview(
      source: source,
      pipeline: const ProcessingPipeline(
        overrides: {'jaw': 1, 'skin_smooth': 0.4},
      ),
      dragKey: 'jaw',
    );
    final color = await controller.renderDragPreview(
      source: source,
      pipeline: const ProcessingPipeline(overrides: {'exposure': 0.2}),
      dragKey: 'exposure',
    );
    expect(skin, isNull);
    expect(color, isNull);
    FragmentProgramWarpBackend.resetShared();
  });
}
