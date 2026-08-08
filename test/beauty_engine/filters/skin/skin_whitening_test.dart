import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/pass_skin_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/render_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_pool.dart';
import 'package:flutter_test/flutter_test.dart';

import 'skin_face_fixture.dart';

void main() {
  test('skin_whitening only does not throw', () async {
    const w = 128, h = 128;
    final rgba = Uint8List(w * h * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = 180;
      rgba[i + 1] = 130;
      rgba[i + 2] = 110;
      rgba[i + 3] = 255;
    }
    final pool = TexturePool();
    final input = pool.acquireFromUpload(
      TextureUpload(bytes: rgba, width: w, height: h),
    );
    final face = syntheticFace();
    final stages = const SkinFilterPipeline().buildPostStages(
      parameters: {'skin_whitening': 0.8},
      face: face,
      imageSize: Size(w.toDouble(), h.toDouble()),
    );
    expect(stages, isNotEmpty);
    const pass = PassSkinEngine();
    final ctx = RenderPassContext(
      input: input,
      pool: pool,
      uniforms: stages.first.uniforms,
    );
    final out = await pass.execute(ctx);
    expect(out.id, isNotNull);
    final entry = pool.store.get(out.id);
    expect(entry, isNotNull);
    var changed = false;
    for (var i = 0; i < rgba.length; i += 4) {
      if (entry!.rgba[i] != rgba[i]) {
        changed = true;
        break;
      }
    }
    expect(changed, isTrue);
  });
}
