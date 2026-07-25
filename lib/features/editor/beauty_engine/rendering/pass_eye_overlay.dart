import 'dart:typed_data';

import '../filters/face/skin_soft_region.dart';
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

    final ellipses =
        context.uniforms['ellipses'] as List<NormalizedEllipse>? ?? const [];
    if (ellipses.isEmpty) {
      return context.pool.acquireCopy(context.input);
    }

    final output = Uint8List.fromList(source.rgba);
    final width = source.width;
    final height = source.height;
    final strength = (intensity * 0.35).clamp(0.0, 0.35);

    for (final ellipse in ellipses) {
      if (!ellipse.isValid) {
        continue;
      }

      final bounds = ellipse.boundingRect.inflate(0.02);
      final left = (bounds.left * width).round().clamp(0, width - 1);
      final top = (bounds.top * height).round().clamp(0, height - 1);
      final right = (bounds.right * width).round().clamp(left + 1, width);
      final bottom = (bounds.bottom * height).round().clamp(top + 1, height);

      for (var y = top; y < bottom; y++) {
        final ny = y / height;
        for (var x = left; x < right; x++) {
          final nx = x / width;
          final maskWeight = ellipse.weight(nx, ny, edgeFeather: 0.045);
          if (maskWeight <= 0) {
            continue;
          }

          final verticalT =
              ((ny - bounds.top) / bounds.height).clamp(0.0, 1.0);
          if (verticalT > 0.62) {
            continue;
          }
          final rowFactor =
              (1 - verticalT / 0.62) * strength * maskWeight;

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
