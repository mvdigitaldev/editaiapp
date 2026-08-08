import 'dart:typed_data';

/// Guided filter (He, Sun, Tang 2010) — filtro edge-preserving de custo O(1)
/// por pixel independente do raio, via imagens integrais.
///
/// É o filtro de suavização de pele usado em produção (cap. 1.4 do plano do
/// SDK facial): ao contrário do bilateral, o custo não cresce com o raio e
/// não produz halo/banding em gradientes suaves de pele.
///
/// Todas as funções operam em luz LINEAR (ver [ColorScience]); aplicar em
/// sRGB gama escurece as transições.
abstract final class GuidedFilter {
  /// Filtro auto-guiado (guide == src), o caso da suavização de pele.
  ///
  /// [radius] em pixels; [eps] é a variância de corte — quanto MENOR, mais
  /// bordas são preservadas (e menos suavização acontece). Para pele em luz
  /// linear, 1e-4..1e-3 é a faixa útil.
  static Float32List filterSelf(
    Float32List src, {
    required int width,
    required int height,
    required int radius,
    required double eps,
  }) {
    assert(src.length == width * height);
    if (radius <= 0) {
      return Float32List.fromList(src);
    }

    final meanI = boxMean(src, width: width, height: height, radius: radius);
    final squared = Float32List(src.length);
    for (var i = 0; i < src.length; i++) {
      squared[i] = src[i] * src[i];
    }
    final meanII = boxMean(squared, width: width, height: height, radius: radius);

    // a = var / (var + eps); b = mean * (1 - a)
    final a = Float32List(src.length);
    final b = Float32List(src.length);
    for (var i = 0; i < src.length; i++) {
      final mean = meanI[i];
      final variance = meanII[i] - mean * mean;
      final ai = variance <= 0 ? 0.0 : variance / (variance + eps);
      a[i] = ai;
      b[i] = mean * (1 - ai);
    }

    final meanA = boxMean(a, width: width, height: height, radius: radius);
    final meanB = boxMean(b, width: width, height: height, radius: radius);

    final out = Float32List(src.length);
    for (var i = 0; i < src.length; i++) {
      out[i] = meanA[i] * src[i] + meanB[i];
    }
    return out;
  }

  /// Média em janela quadrada (2r+1)² via imagem integral — O(1) por pixel.
  ///
  /// A integral usa [Float64List]: em 1080p a soma acumulada passa de 2e6
  /// termos e float32 perderia precisão suficiente para gerar faixas
  /// horizontais visíveis no resultado.
  static Float32List boxMean(
    Float32List src, {
    required int width,
    required int height,
    required int radius,
  }) {
    assert(src.length == width * height);
    final integralWidth = width + 1;
    final integral = Float64List(integralWidth * (height + 1));

    for (var y = 0; y < height; y++) {
      var rowSum = 0.0;
      final srcRow = y * width;
      final curRow = (y + 1) * integralWidth;
      final prevRow = y * integralWidth;
      for (var x = 0; x < width; x++) {
        rowSum += src[srcRow + x];
        integral[curRow + x + 1] = integral[prevRow + x + 1] + rowSum;
      }
    }

    final out = Float32List(src.length);
    for (var y = 0; y < height; y++) {
      final y0 = y - radius < 0 ? 0 : y - radius;
      final y1 = y + radius >= height ? height - 1 : y + radius;
      final top = y0 * integralWidth;
      final bottom = (y1 + 1) * integralWidth;
      final rowHeight = y1 - y0 + 1;
      final outRow = y * width;
      for (var x = 0; x < width; x++) {
        final x0 = x - radius < 0 ? 0 : x - radius;
        final x1 = x + radius >= width ? width - 1 : x + radius;
        final sum = integral[bottom + x1 + 1] -
            integral[bottom + x0] -
            integral[top + x1 + 1] +
            integral[top + x0];
        out[outRow + x] = sum / (rowHeight * (x1 - x0 + 1));
      }
    }
    return out;
  }

  /// Média em janela para máscaras uint8 (0..255) → Float32 0..1. Usada para
  /// feather de máscara sem converter o buffer inteiro antes.
  static Float32List boxMeanU8(
    Uint8List src, {
    required int width,
    required int height,
    required int radius,
  }) {
    final normalized = Float32List(src.length);
    for (var i = 0; i < src.length; i++) {
      normalized[i] = src[i] / 255.0;
    }
    if (radius <= 0) {
      return normalized;
    }
    return boxMean(normalized, width: width, height: height, radius: radius);
  }
}
