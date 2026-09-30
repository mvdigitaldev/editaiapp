import 'dart:math' as math;
import 'dart:typed_data';

import '../../../color/color_science.dart';
import 'guided_filter.dart';

/// Intensidades 0..1 das ferramentas do Grupo A (pele).
class SkinRetouchParams {
  const SkinRetouchParams({
    this.smooth = 0,
    this.acne = 0,
    this.wrinkles = 0,
    this.darkCircles = 0,
    this.shine = 0,
  });

  final double smooth;
  final double acne;
  final double wrinkles;
  final double darkCircles;
  final double shine;

  bool get isNoop =>
      smooth <= 0 && acne <= 0 && wrinkles <= 0 && darkCircles <= 0 && shine <= 0;
}

/// Payload plano (typed data + números) para permitir execução em isolate.
class SkinRetouchRequest {
  const SkinRetouchRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.skinWeights,
    required this.underEyeWeights,
    required this.params,
    required this.faceEdgePx,
    this.shineWeights,
    this.shineKnee,
    this.cheekWeights,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final Uint8List skinWeights;
  final Uint8List underEyeWeights;
  final SkinRetouchParams params;
  final double faceEdgePx;

  /// Máscara de brilho/oleosidade (Sprint 5) — opcional.
  final Uint8List? shineWeights;

  /// Joelho de brilho calibrado por tom; fallback interno se null.
  final double? shineKnee;

  /// Bochecha, para a referência de cor das olheiras. Sem isto, a referência
  /// volta à pele fora da olheira.
  final Uint8List? cheekWeights;
}

/// Pipeline de pele do Grupo A: separação de frequências em 3 bandas sobre
/// guided filter, correção de manchas, olheiras em OKLab e compressão de
/// brilho — tudo em luz linear.
///
/// Substitui o box blur 3×3 anterior, que borrava sem preservar poro e não
/// tinha noção de banda de frequência. Referências: cap. 1.4 e Grupo A do
/// plano do SDK facial; invariantes no catálogo de Visual Quality Targets
/// (`docs/beauty/13-visual-quality-targets.md`).
abstract final class SkinRetouchEngine {
  /// Fração da alta frequência (poros) preservada no slider máximo.
  /// Target A1: ≥70%.
  static const highFrequencyKeepAtMax = 0.70;

  /// Fração da banda média (manchas/blotches) preservada no slider máximo.
  static const midFrequencyKeepAtMax = 0.30;

  /// eps do guided filter da banda fina (poro/ruído) e da banda larga.
  static const fineEps = 2.5e-4;
  static const coarseEps = 1.2e-3;

  /// Raio da banda fina em pixels — proporcional ao rosto, não à resolução,
  /// para que a suavização tenha a mesma aparência em qualquer tamanho.
  static int fineRadiusFor(double faceEdgePx) {
    return (faceEdgePx * 0.012).round().clamp(1, 18);
  }

  /// Raio da banda larga: 3× a fina separa mancha (média) de forma do rosto.
  static int coarseRadiusFor(double faceEdgePx) {
    return (fineRadiusFor(faceEdgePx) * 3).clamp(3, 48);
  }

  /// Ponto de entrada — puro, determinístico, sem I/O: seguro para `compute`.
  static Uint8List run(SkinRetouchRequest request) {
    final width = request.width;
    final height = request.height;
    final pixels = width * height;
    final params = request.params;
    final output = Uint8List.fromList(request.rgba);

    if (params.isNoop || pixels <= 0 || request.skinWeights.length != pixels) {
      return output;
    }

    // Só olheiras: o sulco não precisa das bandas de frequência.
    if (params.darkCircles > 0 &&
        params.smooth <= 0 &&
        params.acne <= 0 &&
        params.wrinkles <= 0 &&
        params.shine <= 0) {
      if (request.underEyeWeights.length == pixels) {
        _applyDarkCircles(
          output: output,
          width: width,
          height: height,
          skinWeights: request.skinWeights,
          underEyeWeights: request.underEyeWeights,
          cheekWeights: request.cheekWeights,
          pixels: pixels,
          intensity: params.darkCircles,
        );
      }
      return output;
    }

    final table = ColorScience.srgbToLinearTable;
    final luma = ColorScience.lumaFromRgba(request.rgba, width, height);

    // Raios proporcionais ao rosto: fine ~ poro/ruído, coarse ~ blotch.
    final fineRadius = fineRadiusFor(request.faceEdgePx);
    final coarseRadius = coarseRadiusFor(request.faceEdgePx);

    // eps baixo preserva bordas reais (nariz, lábio) e ainda remove ruído.
    final fineBase = GuidedFilter.filterSelf(
      luma,
      width: width,
      height: height,
      radius: fineRadius,
      eps: fineEps,
    );
    final coarseBase = GuidedFilter.filterSelf(
      luma,
      width: width,
      height: height,
      radius: coarseRadius,
      eps: coarseEps,
    );

    final smoothStrength = math.min(
      1.0,
      params.smooth + params.wrinkles * 0.5,
    );
    final midKeep = 1 - (1 - midFrequencyKeepAtMax) * smoothStrength;
    final highKeep = 1 - (1 - highFrequencyKeepAtMax) * smoothStrength;

    // Referência local para detectar manchas: nível de pele da vizinhança
    // ampla, largo o bastante para que a própria mancha quase não conte.
    final blemishReference = params.acne > 0
        ? GuidedFilter.boxMean(
            luma,
            width: width,
            height: height,
            radius: (coarseRadius * 2).clamp(6, 96),
          )
        : null;

    final skinReferenceLuma = _weightedMean(
      coarseBase,
      request.skinWeights,
      minWeight: 150,
    );
    final shineKnee = request.shineKnee ?? skinReferenceLuma * 1.18;
    final shineMask = request.shineWeights;

    // --- Passe 1: bandas de frequência, manchas e brilho (domínio luma) ---
    for (var p = 0; p < pixels; p++) {
      final weight = request.skinWeights[p] / 255.0;
      if (weight <= 0) continue;

      final original = luma[p];
      final low = coarseBase[p];
      final fine = fineBase[p];
      // Decomposição em 3 bandas: low + mid + high == original.
      final mid = fine - low;
      final high = original - fine;

      // Bandas baixa+média: onde vivem mancha, olheira e brilho. A alta
      // (poro) é preservada e recomposta no final.
      var lowMid = low + mid * midKeep;

      if (blemishReference != null) {
        // Mancha = região mais escura que a vizinhança ampla. O limiar é uma
        // FRAÇÃO do tom local: em luz linear, a mesma mancha de 14 níveis
        // sRGB vale ~0.04 em pele clara e ~0.004 em pele escura, então um
        // piso absoluto nunca dispararia em pele escura (cap. 16). O piso
        // mínimo existe só para não caçar ruído em regiões quase pretas.
        final reference = blemishReference[p];
        final deficit = reference - fine;
        final threshold = math.max(reference * 0.05, 0.0015);
        if (deficit > threshold) {
          final spot =
              ((deficit - threshold) / threshold).clamp(0.0, 1.0).toDouble();
          lowMid += deficit * params.acne * spot;
        }
      }

      if (params.shine > 0 && shineKnee > 0 && lowMid > shineKnee) {
        var shineFactor = 1.0;
        if (shineMask != null && shineMask.length == pixels) {
          shineFactor = shineMask[p] / 255.0;
        }
        if (shineFactor > 0) {
          final excess = lowMid - shineKnee;
          lowMid = shineKnee +
              excess * (1 - 0.7 * params.shine * shineFactor);
        }
      }

      final target = lowMid + high * highKeep;
      final blended = original + (target - original) * weight;

      if (blended == original) continue;

      // Aplica a mudança de luminância preservando a razão entre canais
      // (mantém matiz e saturação da pele).
      final i = p * 4;
      final rLin = table[request.rgba[i]];
      final gLin = table[request.rgba[i + 1]];
      final bLin = table[request.rgba[i + 2]];
      if (original <= 1e-5) {
        final value = ColorScience.linearToSrgb8(blended.clamp(0.0, 1.0));
        output[i] = value;
        output[i + 1] = value;
        output[i + 2] = value;
        continue;
      }
      final factor = (blended / original).clamp(0.0, 4.0);
      output[i] = ColorScience.linearToSrgb8((rLin * factor).clamp(0.0, 1.0));
      output[i + 1] = ColorScience.linearToSrgb8((gLin * factor).clamp(0.0, 1.0));
      output[i + 2] = ColorScience.linearToSrgb8((bLin * factor).clamp(0.0, 1.0));
    }

    // --- Passe 2: olheiras em OKLab ---
    if (params.darkCircles > 0 &&
        request.underEyeWeights.length == pixels) {
      _applyDarkCircles(
        output: output,
        width: width,
        height: height,
        skinWeights: request.skinWeights,
        underEyeWeights: request.underEyeWeights,
        cheekWeights: request.cheekWeights,
        pixels: pixels,
        intensity: params.darkCircles,
      );
    }

    return output;
  }

  /// No slider máximo, a sombra de baixa frequência sobe até este fracção
  /// do vão à pele vizinha. Fechar 100% achata o volume da órbita.
  static const _darkCircleLift = 0.90;

  /// Corrige a olheira por separação de frequências: a sombra (baixa
  /// frequência) vai ao tom da pele logo ao lado; o poro (alta) fica.
  /// A referência é a média local da pele FORA da máscara — a bochecha
  /// distante falha com barba ou luz lateral.
  static void _applyDarkCircles({
    required Uint8List output,
    required int width,
    required int height,
    required Uint8List skinWeights,
    required Uint8List underEyeWeights,
    required int pixels,
    required double intensity,
    Uint8List? cheekWeights,
  }) {
    final table = ColorScience.srgbToLinearTable;
    final lab = Float64List(3);
    final rgb = Float64List(3);

    final L = Float32List(pixels);
    final A = Float32List(pixels);
    final Bch = Float32List(pixels);
    var minY = height;
    var maxY = 0;
    var maskHits = 0;
    for (var p = 0; p < pixels; p++) {
      final i = p * 4;
      ColorScience.linearRgbToOklab(
        table[output[i]],
        table[output[i + 1]],
        table[output[i + 2]],
        lab,
      );
      L[p] = lab[0];
      A[p] = lab[1];
      Bch[p] = lab[2];
      if (underEyeWeights[p] <= 16) continue;
      final y = p ~/ width;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      maskHits++;
    }
    if (maskHits < 8) return;

    final allowed = Float32List(pixels);
    var allowedHits = 0;
    for (var p = 0; p < pixels; p++) {
      if (underEyeWeights[p] >= 40) continue;
      final onCheek =
          cheekWeights != null && cheekWeights.length == pixels && cheekWeights[p] >= 120;
      if (skinWeights[p] < 120 && !onCheek) continue;
      allowed[p] = 1;
      allowedHits++;
    }
    if (allowedHits < 40) {
      for (var p = 0; p < pixels; p++) {
        if (skinWeights[p] < 180 || underEyeWeights[p] > 0) continue;
        allowed[p] = 1;
        allowedHits++;
      }
    }
    if (allowedHits < 20) return;

    final band = math.max(6, maxY - minY);
    final refRadius = (band * 2.2).round().clamp(16, 72);
    final poreRadius = (band * 0.10).round().clamp(2, 6);

    var sumL = 0.0;
    var sumA = 0.0;
    var sumB = 0.0;
    var nAllow = 0;
    for (var p = 0; p < pixels; p++) {
      if (allowed[p] <= 0) continue;
      sumL += L[p];
      sumA += A[p];
      sumB += Bch[p];
      nAllow++;
    }
    final fallbackL = nAllow == 0 ? 0.7 : sumL / nAllow;
    final fallbackA = nAllow == 0 ? 0.0 : sumA / nAllow;
    final fallbackB = nAllow == 0 ? 0.0 : sumB / nAllow;

    final refL = _maskedMean(
      values: L,
      allowed: allowed,
      width: width,
      height: height,
      radius: refRadius,
      fallback: fallbackL,
    );
    final refA = _maskedMean(
      values: A,
      allowed: allowed,
      width: width,
      height: height,
      radius: refRadius,
      fallback: fallbackA,
    );
    final refB = _maskedMean(
      values: Bch,
      allowed: allowed,
      width: width,
      height: height,
      radius: refRadius,
      fallback: fallbackB,
    );
    final lowL = GuidedFilter.boxMean(
      L,
      width: width,
      height: height,
      radius: poreRadius,
    );
    final region = GuidedFilter.boxMeanU8(
      underEyeWeights,
      width: width,
      height: height,
      radius: (band * 0.12).round().clamp(2, 8),
    );

    for (var p = 0; p < pixels; p++) {
      final w = region[p];
      if (w <= 0.02) continue;

      final gap = refL[p] - lowL[p];
      if (gap <= 0.004) continue;

      final t = (intensity * w * _darkCircleLift).clamp(0.0, _darkCircleLift);
      final newL = L[p] + gap * t;
      final shade = (gap / 0.07).clamp(0.0, 1.0);
      final chroma = t * (0.22 + 0.50 * shade);
      final newA = A[p] + (refA[p] - A[p]) * chroma;
      final newB = Bch[p] + (refB[p] - Bch[p]) * chroma;

      ColorScience.oklabToLinearRgb(newL, newA, newB, rgb);
      final i = p * 4;
      output[i] = ColorScience.linearToSrgb8(rgb[0].clamp(0.0, 1.0));
      output[i + 1] = ColorScience.linearToSrgb8(rgb[1].clamp(0.0, 1.0));
      output[i + 2] = ColorScience.linearToSrgb8(rgb[2].clamp(0.0, 1.0));
    }
  }

  static Float32List _maskedMean({
    required Float32List values,
    required Float32List allowed,
    required int width,
    required int height,
    required int radius,
    required double fallback,
  }) {
    final weighted = Float32List(values.length);
    for (var i = 0; i < values.length; i++) {
      weighted[i] = values[i] * allowed[i];
    }
    final num = GuidedFilter.boxMean(
      weighted,
      width: width,
      height: height,
      radius: radius,
    );
    final den = GuidedFilter.boxMean(
      allowed,
      width: width,
      height: height,
      radius: radius,
    );
    final out = Float32List(values.length);
    for (var i = 0; i < values.length; i++) {
      final d = den[i];
      out[i] = d > 0.05 ? num[i] / d : fallback;
    }
    return out;
  }

  static double _weightedMean(
    Float32List values,
    Uint8List weights, {
    required int minWeight,
  }) {
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < values.length; i++) {
      if (weights[i] < minWeight) continue;
      sum += values[i];
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }
}
