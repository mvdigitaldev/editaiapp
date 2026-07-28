import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Confiança de textura (0–1): alta onde há estrutura/gradiente (estampas).
///
/// Usado pelo [TextureStabilizationPass] para limitar estiramento sem anular
/// o efeito corporal em regiões planas.
class TextureConfidenceMap {
  final Float32List values;
  final int width;
  final int height;
  final Size imageSize;
  final double maxValue;
  final double meanValue;

  const TextureConfidenceMap({
    required this.values,
    required this.width,
    required this.height,
    required this.imageSize,
    required this.maxValue,
    required this.meanValue,
  }) : assert(width >= 0 && height >= 0);

  bool get isEmpty => values.isEmpty || width <= 0 || height <= 0;

  double sampleNormalized(double nx, double ny) {
    if (isEmpty) {
      return 0;
    }
    final fx = (nx.clamp(0.0, 1.0) * (width - 1));
    final fy = (ny.clamp(0.0, 1.0) * (height - 1));
    final x0 = fx.floor().clamp(0, width - 1);
    final y0 = fy.floor().clamp(0, height - 1);
    final x1 = (x0 + 1).clamp(0, width - 1);
    final y1 = (y0 + 1).clamp(0, height - 1);
    final tx = fx - x0;
    final ty = fy - y0;
    final v00 = values[y0 * width + x0];
    final v10 = values[y0 * width + x1];
    final v01 = values[y1 * width + x0];
    final v11 = values[y1 * width + x1];
    final top = v00 + (v10 - v00) * tx;
    final bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }

  /// Constrói a partir de RGBA: magnitude do gradiente de luminância normalizada.
  factory TextureConfidenceMap.fromRgba({
    required Uint8List rgba,
    required int width,
    required int height,
    Size? imageSize,
    int downsample = 2,
  }) {
    assert(width > 0 && height > 0);
    assert(rgba.length >= width * height * 4);
    final step = downsample.clamp(1, 8);
    final mw = math.max(1, width ~/ step);
    final mh = math.max(1, height ~/ step);
    final luma = Float32List(mw * mh);

    for (var y = 0; y < mh; y++) {
      for (var x = 0; x < mw; x++) {
        final sx = (x * step).clamp(0, width - 1);
        final sy = (y * step).clamp(0, height - 1);
        final o = (sy * width + sx) * 4;
        luma[y * mw + x] =
            (0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2]) /
                255.0;
      }
    }

    return TextureConfidenceMap.fromLuminance(
      luminance: luma,
      width: mw,
      height: mh,
      imageSize: imageSize ?? Size(width.toDouble(), height.toDouble()),
    );
  }

  factory TextureConfidenceMap.fromLuminance({
    required Float32List luminance,
    required int width,
    required int height,
    required Size imageSize,
  }) {
    if (width <= 0 || height <= 0 || luminance.isEmpty) {
      return TextureConfidenceMap(
        values: Float32List(0),
        width: 0,
        height: 0,
        imageSize: imageSize,
        maxValue: 0,
        meanValue: 0,
      );
    }

    final values = Float32List(width * height);
    var maxG = 1e-6;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final xm = x > 0 ? x - 1 : x;
        final xp = x < width - 1 ? x + 1 : x;
        final ym = y > 0 ? y - 1 : y;
        final yp = y < height - 1 ? y + 1 : y;
        final gx = luminance[y * width + xp] - luminance[y * width + xm];
        final gy = luminance[yp * width + x] - luminance[ym * width + x];
        final g = math.sqrt(gx * gx + gy * gy);
        values[i] = g;
        if (g > maxG) {
          maxG = g;
        }
      }
    }

    var sum = 0.0;
    var maxV = 0.0;
    for (var i = 0; i < values.length; i++) {
      final v = (values[i] / maxG).clamp(0.0, 1.0);
      // Curva suave: textura média já conta; picos de borda → 1.
      final curved = math.sqrt(v);
      values[i] = curved;
      sum += curved;
      if (curved > maxV) {
        maxV = curved;
      }
    }

    return TextureConfidenceMap(
      values: values,
      width: width,
      height: height,
      imageSize: imageSize,
      maxValue: maxV,
      meanValue: values.isEmpty ? 0.0 : sum / values.length,
    );
  }

  /// Mapa constante (testes / fallback).
  factory TextureConfidenceMap.filled({
    required int width,
    required int height,
    required Size imageSize,
    double value = 0.5,
  }) {
    final v = value.clamp(0.0, 1.0);
    final values = Float32List(width * height);
    for (var i = 0; i < values.length; i++) {
      values[i] = v;
    }
    return TextureConfidenceMap(
      values: values,
      width: width,
      height: height,
      imageSize: imageSize,
      maxValue: v,
      meanValue: v,
    );
  }
}
