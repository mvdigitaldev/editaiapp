import 'dart:typed_data';
import 'dart:ui';

import '../filters/face/skin_mask_utils.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Pass consolidado: smooth, whitening, retouch, makeup, teeth (Sprint 17).
class PassSkinEngine implements RenderPass {
  const PassSkinEngine();

  @override
  String get shaderName => RenderShaders.skinEngine;

  @override
  Future<TextureHandle> execute(RenderPassContext context) async {
    final source = context.store.get(context.input.id);
    if (source == null) {
      return context.input;
    }

    final mask = context.uniforms['mask'] as SkinProcessingMask?;
    if (mask == null || mask.isEmpty) {
      return context.pool.acquireCopy(context.input);
    }

    final smooth = _f(context, 'skin_smooth');
    final whitening = _f(context, 'skin_whitening');
    final acne = _f(context, 'remove_acne');
    final wrinkles = _f(context, 'remove_wrinkles');
    final darkCircles = _f(context, 'remove_dark_circles');
    final teeth = _f(context, 'teeth_whitening');
    final blush = _f(context, 'blush');
    final contour = _f(context, 'contour');
    final eyebrows = _f(context, 'eyebrows');
    final eyelashes = _f(context, 'eyelashes');

    if (smooth == 0 &&
        whitening == 0 &&
        acne == 0 &&
        wrinkles == 0 &&
        darkCircles == 0 &&
        teeth == 0 &&
        blush == 0 &&
        contour == 0 &&
        eyebrows == 0 &&
        eyelashes == 0) {
      return context.pool.acquireCopy(context.input);
    }

    final output = Uint8List.fromList(source.rgba);
    final width = source.width;
    final height = source.height;
    final original = Uint8List.fromList(source.rgba);

    final x0 = (mask.faceBounds.left * width).round().clamp(0, width - 1);
    final y0 = (mask.faceBounds.top * height).round().clamp(0, height - 1);
    final x1 = ((mask.faceBounds.left + mask.faceBounds.width) * width)
        .round()
        .clamp(x0 + 1, width);
    final y1 = ((mask.faceBounds.top + mask.faceBounds.height) * height)
        .round()
        .clamp(y0 + 1, height);

    if (smooth > 0 || acne > 0 || wrinkles > 0) {
      _applySkinBlur(
        output: output,
        original: original,
        width: width,
        height: height,
        x0: x0,
        y0: y0,
        x1: x1,
        y1: y1,
        mask: mask,
        strength: (smooth * 0.45 + acne * 0.25 + wrinkles * 0.2).clamp(0, 0.55),
      );
    }

    for (var y = y0; y < y1; y++) {
      final ny = y / height;
      for (var x = x0; x < x1; x++) {
        final nx = x / width;
        if (!mask.faceBounds.contains(Offset(nx, ny))) {
          continue;
        }

        final i = (y * width + x) * 4;
        var r = output[i];
        var g = output[i + 1];
        var b = output[i + 2];

        if (whitening > 0 && !SkinMaskUtils.isProtected(nx, ny, mask)) {
          final w = whitening * 0.12;
          r = (r + (255 - r) * w).round();
          g = (g + (255 - g) * w).round();
          b = (b + (255 - b) * w).round();
        }

        if (darkCircles > 0) {
          final weight = SkinMaskUtils.underEyeWeight(nx, ny, mask);
          if (weight > 0) {
            final lift = darkCircles * 0.15 * weight;
            r = (r + (255 - r) * lift).round();
            g = (g + (255 - g) * lift).round();
            b = (b + (255 - b) * lift).round();
          }
        }

        if (teeth > 0) {
          final weight = SkinMaskUtils.teethWhiteningWeight(
            nx,
            ny,
            mask,
            r,
            g,
            b,
          );
          if (weight > 0) {
            final t = teeth * 0.28 * weight;
            r = (r + (255 - r) * t).round();
            g = (g + (255 - g) * t).round();
            b = (b + (255 - b) * t).round();
          }
        }

        if (blush > 0) {
          final weight = SkinMaskUtils.softRegionsWeight(nx, ny, mask.cheekRegions);
          if (weight > 0) {
            r = (r + 28 * blush * weight).round().clamp(0, 255);
            g = (g + 8 * blush * weight).round().clamp(0, 255);
            b = (b + 4 * blush * weight).round().clamp(0, 255);
          }
        }

        if (contour > 0) {
          final weight = SkinMaskUtils.softRegionsWeight(
            nx,
            ny,
            mask.contourRegions,
            edgeFeather: 0.03,
          );
          if (weight > 0) {
            final c = contour * 0.12 * weight;
            r = (r * (1 - c)).round();
            g = (g * (1 - c)).round();
            b = (b * (1 - c)).round();
          }
        }

        if (eyebrows > 0) {
          final weight = SkinMaskUtils.softRegionsWeight(
            nx,
            ny,
            mask.eyebrowRegions,
            edgeFeather: 0.02,
          );
          if (weight > 0) {
            final e = eyebrows * 0.18 * weight;
            r = (r * (1 - e)).round();
            g = (g * (1 - e)).round();
            b = (b * (1 - e)).round();
          }
        }

        if (eyelashes > 0) {
          final weight = SkinMaskUtils.softRegionsWeight(
            nx,
            ny,
            mask.eyelashRegions,
            edgeFeather: 0.02,
          );
          if (weight > 0) {
            final e = eyelashes * 0.15 * weight;
            r = (r * (1 - e)).round();
            g = (g * (1 - e)).round();
            b = (b * (1 - e)).round();
          }
        }

        output[i] = r.clamp(0, 255);
        output[i + 1] = g.clamp(0, 255);
        output[i + 2] = b.clamp(0, 255);
      }
    }

    final entry = context.store.create(
      rgba: output,
      width: width,
      height: height,
    );
    return context.store.toHandle(entry);
  }

  static double _f(RenderPassContext context, String key) {
    return ((context.uniforms[key] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
  }

  static void _applySkinBlur({
    required Uint8List output,
    required Uint8List original,
    required int width,
    required int height,
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    required SkinProcessingMask mask,
    required double strength,
  }) {
    if (strength <= 0) {
      return;
    }

    final temp = Uint8List.fromList(output);
    for (var y = y0; y < y1; y++) {
      final ny = y / height;
      for (var x = x0; x < x1; x++) {
        final nx = x / width;
        if (SkinMaskUtils.isProtected(nx, ny, mask, feather: 0.03)) {
          continue;
        }

        var r = 0;
        var g = 0;
        var b = 0;
        var count = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final sx = (x + dx).clamp(0, width - 1);
            final sy = (y + dy).clamp(0, height - 1);
            final si = (sy * width + sx) * 4;
            r += original[si];
            g += original[si + 1];
            b += original[si + 2];
            count++;
          }
        }

        final i = (y * width + x) * 4;
        output[i] = (temp[i] * (1 - strength) + (r / count) * strength).round();
        output[i + 1] =
            (temp[i + 1] * (1 - strength) + (g / count) * strength).round();
        output[i + 2] =
            (temp[i + 2] * (1 - strength) + (b / count) * strength).round();
      }
    }
  }
}
