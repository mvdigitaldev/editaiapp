import 'dart:typed_data';

import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass 4: composicao base + overlay com alpha.
class PassComposite implements RenderPass {
  const PassComposite();

  @override
  String get shaderName => RenderShaders.composite;

  @override
  Future<TextureHandle> execute(RenderPassContext context) async {
    final base = context.store.get(context.input.id);
    final overlayHandle = context.uniforms['overlay'] as TextureHandle?;
    final alpha = (context.uniforms['alpha'] as num?)?.toDouble() ?? 1;

    if (base == null || overlayHandle == null || alpha <= 0) {
      return context.input;
    }

    final overlay = context.store.get(overlayHandle.id);
    if (overlay == null ||
        overlay.width != base.width ||
        overlay.height != base.height) {
      return context.input;
    }

    final output = Uint8List.fromList(base.rgba);
    final a = alpha.clamp(0.0, 1.0);

    for (var i = 0; i < output.length; i += 4) {
      for (var ch = 0; ch < 3; ch++) {
        final b = output[i + ch];
        final o = overlay.rgba[i + ch];
        output[i + ch] = (b * (1 - a) + o * a).round().clamp(0, 255);
      }
    }

    final entry = context.store.create(
      rgba: output,
      width: base.width,
      height: base.height,
    );
    return context.store.toHandle(entry);
  }
}
