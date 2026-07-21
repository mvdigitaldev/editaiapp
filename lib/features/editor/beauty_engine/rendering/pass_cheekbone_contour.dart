import 'dart:typed_data';
import 'dart:ui';

import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass pós-warp: highlight + shadow para contour de maçã do rosto (Sprint 14).
class PassCheekboneContour implements RenderPass {
  const PassCheekboneContour();

  @override
  String get shaderName => RenderShaders.cheekboneContour;

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

    final highlights =
        context.uniforms['highlights'] as List<Rect>? ?? const [];
    final shadows = context.uniforms['shadows'] as List<Rect>? ?? const [];
    if (highlights.isEmpty && shadows.isEmpty) {
      return context.pool.acquireCopy(context.input);
    }

    final output = Uint8List.fromList(source.rgba);
    final width = source.width;
    final height = source.height;
    final highlightStrength = (intensity * 0.18).clamp(0.0, 0.18);
    final shadowStrength = (intensity * 0.14).clamp(0.0, 0.14);

    for (final region in highlights) {
      _applyBand(
        output: output,
        width: width,
        height: height,
        region: region,
        startT: 0,
        endT: 0.45,
        brighten: highlightStrength,
      );
    }

    for (final region in shadows) {
      _applyBand(
        output: output,
        width: width,
        height: height,
        region: region,
        startT: 0.5,
        endT: 1,
        brighten: -shadowStrength,
      );
    }

    final entry = context.store.create(
      rgba: output,
      width: width,
      height: height,
    );
    return context.store.toHandle(entry);
  }

  void _applyBand({
    required Uint8List output,
    required int width,
    required int height,
    required Rect region,
    required double startT,
    required double endT,
    required double brighten,
  }) {
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
      if (rowT < startT || rowT > endT) {
        continue;
      }
      final bandT = (rowT - startT) / (endT - startT);
      final factor = (1 - (bandT - 0.5).abs() * 2).clamp(0.0, 1.0) * brighten;

      for (var x = left; x < right; x++) {
        final i = (y * width + x) * 4;
        for (var ch = 0; ch < 3; ch++) {
          final v = output[i + ch];
          output[i + ch] = (v + 255 * factor).round().clamp(0, 255);
        }
      }
    }
  }
}
