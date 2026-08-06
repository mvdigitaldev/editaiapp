import 'dart:math' as math;
import 'dart:typed_data';

/// Métricas de qualidade/regressão visual sobre buffers RGBA (Sprint 0 do
/// SDK facial — cap. 11 do plano). Usadas pelo golden image testing e,
/// futuramente, pelo Face Quality Assessment.
///
/// Todas as funções assumem buffers RGBA8 (4 bytes por pixel) do MESMO
/// tamanho; violações são erros de programação (asserts).
abstract final class ImageQualityMetrics {
  /// SSIM médio por janelas 8×8 sobre a luminância (Rec. 709).
  ///
  /// 1.0 = idênticas; ≥0.98 é o threshold padrão de regressão do plano.
  static double ssim(
    Uint8List a,
    Uint8List b, {
    required int width,
    required int height,
    int windowSize = 8,
  }) {
    assert(a.length == b.length);
    assert(a.length == width * height * 4);

    final lumaA = _luminance(a, width, height);
    final lumaB = _luminance(b, width, height);

    const c1 = 6.5025; // (0.01 * 255)^2
    const c2 = 58.5225; // (0.03 * 255)^2

    var sum = 0.0;
    var windows = 0;
    for (var wy = 0; wy < height; wy += windowSize) {
      for (var wx = 0; wx < width; wx += windowSize) {
        final x1 = math.min(wx + windowSize, width);
        final y1 = math.min(wy + windowSize, height);
        final n = (x1 - wx) * (y1 - wy);
        if (n < 4) continue;

        var meanA = 0.0;
        var meanB = 0.0;
        for (var y = wy; y < y1; y++) {
          final row = y * width;
          for (var x = wx; x < x1; x++) {
            meanA += lumaA[row + x];
            meanB += lumaB[row + x];
          }
        }
        meanA /= n;
        meanB /= n;

        var varA = 0.0;
        var varB = 0.0;
        var cov = 0.0;
        for (var y = wy; y < y1; y++) {
          final row = y * width;
          for (var x = wx; x < x1; x++) {
            final da = lumaA[row + x] - meanA;
            final db = lumaB[row + x] - meanB;
            varA += da * da;
            varB += db * db;
            cov += da * db;
          }
        }
        varA /= n;
        varB /= n;
        cov /= n;

        sum += ((2 * meanA * meanB + c1) * (2 * cov + c2)) /
            ((meanA * meanA + meanB * meanB + c1) * (varA + varB + c2));
        windows++;
      }
    }
    return windows == 0 ? 1.0 : (sum / windows).clamp(0.0, 1.0);
  }

  /// PSNR em dB sobre os canais RGB. [double.infinity] para imagens idênticas.
  static double psnr(Uint8List a, Uint8List b) {
    assert(a.length == b.length);
    var mse = 0.0;
    var n = 0;
    for (var i = 0; i < a.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        final d = (a[i + c] - b[i + c]).toDouble();
        mse += d * d;
        n++;
      }
    }
    mse /= n;
    if (mse == 0) return double.infinity;
    return 10 * math.log(255 * 255 / mse) / math.ln10;
  }

  /// ΔE2000 (CIEDE2000) médio entre as duas imagens, opcionalmente restrito
  /// a uma máscara single-channel (peso 0–255 por pixel).
  ///
  /// ΔE ≈ 1 é o limiar de diferença perceptível; o plano usa média ≤1.5 na
  /// máscara de pele como tolerância de regressão.
  static double deltaE2000Mean(
    Uint8List a,
    Uint8List b, {
    Uint8List? mask,
  }) {
    assert(a.length == b.length);
    assert(mask == null || mask.length == a.length ~/ 4);

    var sum = 0.0;
    var weightTotal = 0.0;
    for (var i = 0, p = 0; i < a.length; i += 4, p++) {
      final w = mask == null ? 1.0 : mask[p] / 255.0;
      if (w <= 0) continue;
      final labA = _srgbToLab(a[i], a[i + 1], a[i + 2]);
      final labB = _srgbToLab(b[i], b[i + 1], b[i + 2]);
      sum += _ciede2000(labA, labB) * w;
      weightTotal += w;
    }
    return weightTotal == 0 ? 0.0 : sum / weightTotal;
  }

  // --- internos ---

  static Float32List _luminance(Uint8List rgba, int width, int height) {
    final out = Float32List(width * height);
    for (var i = 0, p = 0; p < out.length; i += 4, p++) {
      out[p] =
          0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
    }
    return out;
  }

  /// sRGB 8-bit → CIELAB (D65).
  static List<double> _srgbToLab(int r8, int g8, int b8) {
    double linear(int c8) {
      final c = c8 / 255.0;
      return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = linear(r8);
    final g = linear(g8);
    final b = linear(b8);

    // sRGB D65 → XYZ, normalizado pelo branco de referência.
    final x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
    final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
    final z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;

    double f(double t) => t > 0.008856
        ? math.pow(t, 1 / 3).toDouble()
        : (7.787 * t + 16.0 / 116.0);

    final fx = f(x);
    final fy = f(y);
    final fz = f(z);
    return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
  }

  /// CIEDE2000 (implementação padrão de Sharma et al. 2005).
  static double _ciede2000(List<double> lab1, List<double> lab2) {
    final l1 = lab1[0], a1 = lab1[1], b1 = lab1[2];
    final l2 = lab2[0], a2 = lab2[1], b2 = lab2[2];

    final c1 = math.sqrt(a1 * a1 + b1 * b1);
    final c2 = math.sqrt(a2 * a2 + b2 * b2);
    final cMean = (c1 + c2) / 2;
    final c7 = math.pow(cMean, 7).toDouble();
    final g = 0.5 * (1 - math.sqrt(c7 / (c7 + 6103515625.0))); // 25^7

    final a1p = a1 * (1 + g);
    final a2p = a2 * (1 + g);
    final c1p = math.sqrt(a1p * a1p + b1 * b1);
    final c2p = math.sqrt(a2p * a2p + b2 * b2);

    double hp(double ap, double b) {
      if (ap == 0 && b == 0) return 0;
      var h = math.atan2(b, ap) * 180 / math.pi;
      if (h < 0) h += 360;
      return h;
    }

    final h1p = hp(a1p, b1);
    final h2p = hp(a2p, b2);

    final dLp = l2 - l1;
    final dCp = c2p - c1p;

    double dhp;
    if (c1p * c2p == 0) {
      dhp = 0;
    } else {
      dhp = h2p - h1p;
      if (dhp > 180) dhp -= 360;
      if (dhp < -180) dhp += 360;
    }
    final dHp = 2 * math.sqrt(c1p * c2p) * math.sin(dhp * math.pi / 360);

    final lMean = (l1 + l2) / 2;
    final cpMean = (c1p + c2p) / 2;

    double hpMean;
    if (c1p * c2p == 0) {
      hpMean = h1p + h2p;
    } else {
      hpMean = (h1p + h2p) / 2;
      if ((h1p - h2p).abs() > 180) {
        hpMean += h1p + h2p < 360 ? 180 : -180;
      }
    }

    final t = 1 -
        0.17 * math.cos((hpMean - 30) * math.pi / 180) +
        0.24 * math.cos(2 * hpMean * math.pi / 180) +
        0.32 * math.cos((3 * hpMean + 6) * math.pi / 180) -
        0.20 * math.cos((4 * hpMean - 63) * math.pi / 180);

    final lm50 = (lMean - 50) * (lMean - 50);
    final sl = 1 + 0.015 * lm50 / math.sqrt(20 + lm50);
    final sc = 1 + 0.045 * cpMean;
    final sh = 1 + 0.015 * cpMean * t;

    final cp7 = math.pow(cpMean, 7).toDouble();
    final rc = 2 * math.sqrt(cp7 / (cp7 + 6103515625.0));
    final dTheta = 30 * math.exp(-((hpMean - 275) / 25) * ((hpMean - 275) / 25));
    final rt = -rc * math.sin(2 * dTheta * math.pi / 180);

    final termL = dLp / sl;
    final termC = dCp / sc;
    final termH = dHp / sh;
    return math.sqrt(
      termL * termL + termC * termC + termH * termH + rt * termC * termH,
    );
  }
}
