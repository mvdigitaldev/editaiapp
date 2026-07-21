import 'dart:typed_data';

import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass 2: ajuste de cor simples (brightness/contrast stub — Sprint 08+ LUT).
class PassColor implements RenderPass {
  const PassColor();

  @override
  String get shaderName => RenderShaders.colorAdjust;

  @override
  Future<TextureHandle> execute(RenderPassContext context) async {
    final source = context.store.get(context.input.id);
    if (source == null) {
      return context.input;
    }

    final brightness = (context.uniforms['brightness'] as num?)?.toDouble() ?? 0;
    final contrast = (context.uniforms['contrast'] as num?)?.toDouble() ?? 1;

    if (brightness == 0 && contrast == 1) {
      return context.pool.acquireCopy(context.input);
    }

    final output = Uint8List.fromList(source.rgba);
    final offset = (brightness * 255).round();
    final c = contrast.clamp(0.5, 2.0);

    for (var i = 0; i < output.length; i += 4) {
      for (var ch = 0; ch < 3; ch++) {
        final v = output[i + ch];
        final adjusted = ((v - 128) * c + 128 + offset).round();
        output[i + ch] = adjusted.clamp(0, 255);
      }
    }

    final entry = context.store.create(
      rgba: output,
      width: source.width,
      height: source.height,
    );
    return context.store.toHandle(entry);
  }
}
