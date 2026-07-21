import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_mask_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/render_target.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(200, 300);
  late FaceMeshResult face;

  setUp(() {
    face = _fakeFaceMesh();
  });

  group('SkinFilterPipeline Sprint 17', () {
    const pipeline = SkinFilterPipeline();

    test('hasActiveSkin detects skin params', () {
      expect(pipeline.hasActiveSkin(const {}), isFalse);
      expect(
        pipeline.hasActiveSkin(const {'skin_smooth': 0.2}),
        isTrue,
      );
    });

    test('skin mask protects eye regions', () {
      final mask = SkinMaskUtils.build(face, imageSize);
      expect(mask.isEmpty, isFalse);
      expect(mask.protectedRegions, isNotEmpty);

      final eye = mask.protectedRegions.first;
      final center = eye.center;
      expect(SkinMaskUtils.isProtected(center.dx, center.dy, mask), isTrue);
    });

    test('buildPostStages returns skin engine stage', () {
      final stages = pipeline.buildPostStages(
        parameters: const {'skin_smooth': 0.3, 'blush': 0.2},
        face: face,
        imageSize: imageSize,
      );
      expect(stages, hasLength(1));
      expect(stages.first.shaderName, RenderShaders.skinEngine);
    });

    test('skin engine pass runs on CPU backend', () async {
      const width = 120;
      const height = 160;
      final mask = SkinMaskUtils.build(
        face,
        Size(width.toDouble(), height.toDouble()),
      );
      final renderer = GpuRendererImpl();
      final rgba = _solidRgba(width: width, height: height);
      final input = await renderer.upload(
        TextureUpload(bytes: rgba, width: width, height: height),
      );

      final output = await renderer.applyPass(
        input: input,
        shaderName: RenderShaders.skinEngine,
        uniforms: {
          'mask': mask,
          'skin_smooth': 0.4,
          'blush': 0.3,
        },
      );

      expect(output.id, isNot(equals(input.id)));
      renderer.release(input);
      renderer.release(output);
      renderer.dispose();
    });
  });
}

FaceMeshResult _fakeFaceMesh() {
  final landmarks = List.generate(
    FaceMeshResult.expectedLandmarkCount,
    (index) {
      final x = 0.35 + (index % 40) * 0.008;
      final y = 0.25 + (index ~/ 40) * 0.012;
      return FaceLandmark(
        index: index,
        normalized: Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)),
        z: index.isEven ? 0.01 : -0.01,
      );
    },
  );

  return FaceMeshResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTWH(60, 70, 80, 120),
    confidence: 0.95,
  );
}

Uint8List _solidRgba({required int width, required int height}) {
  final data = Uint8List(width * height * 4);
  for (var i = 0; i < data.length; i += 4) {
    data[i] = 180;
    data[i + 1] = 140;
    data[i + 2] = 120;
    data[i + 3] = 255;
  }
  return data;
}
