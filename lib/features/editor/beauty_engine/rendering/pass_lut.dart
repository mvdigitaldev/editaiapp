import 'dart:typed_data';

import '../presets/lut_engine.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass 3: LUT square 512 (paridade flutter_image_filters lookup.frag).
class PassLut implements RenderPass {
  PassLut({LutEngine? engine}) : _engine = engine ?? LutEngine();

  final LutEngine _engine;

  @override
  String get shaderName => RenderShaders.lutApply;

  @override
  Future<TextureHandle> execute(RenderPassContext context) async {
    final source = context.store.get(context.input.id);
    if (source == null) {
      return context.input;
    }

    final assetPath = context.uniforms['lutAssetPath'] as String?;
    final intensity = (context.uniforms['intensity'] as num?)?.toDouble() ?? 1;

    if (assetPath == null || assetPath.isEmpty || intensity <= 0) {
      return context.pool.acquireCopy(context.input);
    }

    final filtered = await _engine.applyToRgba(
      sourceRgba: Uint8List.fromList(source.rgba),
      width: source.width,
      height: source.height,
      lutAssetPath: assetPath,
      intensity: intensity,
    );

    final entry = context.store.create(
      rgba: filtered,
      width: source.width,
      height: source.height,
    );
    return context.store.toHandle(entry);
  }
}
