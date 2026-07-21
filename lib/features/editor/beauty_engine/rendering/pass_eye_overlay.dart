import 'dart:typed_data';
import 'dart:ui';

import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass pós-warp: sombra sutil na pálpebra superior (double eyelid).
class PassEyeOverlay implements RenderPass {
  const PassEyeOverlay();

  @override
  String get shaderName => RenderShaders.eyeOverlay;

  @override
  Future<TextureHandle> execute(RenderPassContext context) async {
    final source = context.store.get(context.input.id);
    if (source == null) {
      return context.input;
    }

    final intensity =
        (context.uniforms['intensity'] as num?)?.toDouble() ?? 0;
    if (intensity <= 0) {
      return context.pool.acquireCopy(context.input);
    }

    final regions = context.uniforms['regions'] as List<Rect>? ?? const [];
    if (regions.isEmpty) {
      return context.pool.acquireCopy(context.input);
    }

    final output = Uint8List.fromList(source.rgba);
    final width = source.width;
    final height = source.height;
    final strength = (intensity * 0.35).clamp(0.0, 0.35);

    for (final region in regions) {
      final left = (region.left * width).round().clamp(0, width - 1);
      final top = (region.top * height).round().clamp(0, height - 1);
      final right = ((region.left + region.width) * width).round().clamp(
        left + 1,
        width,
      );
      final bottom = ((region.top + region.height) * height).round().clamp(
        top + 1,
        height,
      );

      for (var y = top; y < bottom; y++) {
        final rowT = (y - top) / (bottom - top);
        if (rowT > 0.55) {
          continue;
        }
        final rowFactor = (1 - rowT / 0.55) * strength;

        for (var x = left; x < right; x++) {
          final i = (y * width + x) * 4;
          for (var ch = 0; ch < 3; ch++) {
            final v = output[i + ch];
            output[i + ch] = (v * (1 - rowFactor)).round().clamp(0, 255);
          }
        }
      }
    }

    final entry = context.store.create(
      rgba: output,
      width: width,
      height: height,
    );
    return context.store.toHandle(entry);
  }
}
