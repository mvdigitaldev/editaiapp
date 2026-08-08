import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_mask_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:flutter_test/flutter_test.dart';

import '../beauty_engine/filters/skin/skin_face_fixture.dart';
import 'golden_test_utils.dart';
import 'synthetic_portrait.dart';

/// Grupo C — blush/whitening com máscaras elípticas (Sprint 8).
void main() {
  const width = 256;
  const height = 320;
  const imageSize = Size(width * 1.0, height * 1.0);

  Future<Uint8List> renderMakeup(Map<String, double> parameters) async {
    final source = syntheticPortrait(width, height);
    final renderer = GpuRendererImpl();
    final input = await renderer.upload(
      TextureUpload(bytes: source, width: width, height: height),
    );
    final stages = const SkinFilterPipeline().buildPostStages(
      parameters: parameters,
      face: syntheticFace(),
      imageSize: imageSize,
    );
    final output = await renderer.runPipeline(input: input, stages: stages);
    final rgba = await renderer.readPixels(output);
    renderer.dispose();
    return rgba;
  }

  int index(double nx, double ny) =>
      (((ny * height).round().clamp(0, height - 1)) * width +
              ((nx * width).round().clamp(0, width - 1))) *
          4;

  test('blush max não tinta testa (C1)', () async {
    final source = syntheticPortrait(width, height);
    final output = await renderMakeup(const {'blush': 1.0});
    final mask = SkinMaskUtils.build(syntheticFace(), imageSize);
    final forehead = mask.foreheadRegions.first;
    final fx = (forehead.center.dx * width).round().clamp(0, width - 1);
    final fy = (forehead.center.dy * height).round().clamp(0, height - 1);
    final i = (fy * width + fx) * 4;
    expect((output[i] - source[i]).abs(), lessThan(8));
    expect((output[i + 1] - source[i + 1]).abs(), lessThan(8));
  });

  test('blush golden combo', () async {
    final output = await renderMakeup(const {'blush': 0.85, 'skin_whitening': 0.4});
    expectMatchesGolden(
      name: 'makeup_blush_whitening_combo',
      rgba: output,
      width: width,
      height: height,
    );
  });

  test('whitening respeita olhos', () async {
    final source = syntheticPortrait(width, height);
    final output = await renderMakeup(const {'skin_whitening': 1.0});
    final eyeI = index(0.38, 0.42);
    expect(output[eyeI], source[eyeI]);
  });
}
