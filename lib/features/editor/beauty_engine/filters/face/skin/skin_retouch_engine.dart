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
        skinWeights: request.skinWeights,
        underEyeWeights: request.underEyeWeights,
        pixels: pixels,
        intensity: params.darkCircles,
      );
    }

    return output;
  }

  /// Corrige a região sob os olhos em direção ao tom de pele de referência
  /// amostrado do próprio rosto — nunca clareia além dele (invariante A3).
  static void _applyDarkCircles({
    required Uint8List output,
    required Uint8List skinWeights,
    required Uint8List underEyeWeights,
    required int pixels,
    required double intensity,
  }) {
    final table = ColorScience.srgbToLinearTable;
    final lab = Float64List(3);
    final rgb = Float64List(3);

    // Referência: pele com peso alto e FORA da região de olheira.
    var sumL = 0.0;
    var sumA = 0.0;
    var sumB = 0.0;
    var count = 0;
    for (var p = 0; p < pixels; p++) {
      if (skinWeights[p] < 180 || underEyeWeights[p] > 0) continue;
      final i = p * 4;
      ColorScience.linearRgbToOklab(
        table[output[i]],
        table[output[i + 1]],
        table[output[i + 2]],
        lab,
      );
      sumL += lab[0];
      sumA += lab[1];
      sumB += lab[2];
      count++;
    }
    if (count == 0) return;

    final refL = sumL / count;
    final refA = sumA / count;
    final refB = sumB / count;

    for (var p = 0; p < pixels; p++) {
      final region = underEyeWeights[p] / 255.0;
      if (region <= 0) continue;
      final skin = skinWeights[p] / 255.0;
      if (skin <= 0) continue;

      final i = p * 4;
      ColorScience.linearRgbToOklab(
        table[output[i]],
        table[output[i + 1]],
        table[output[i + 2]],
        lab,
      );
      // Só clareia: sombra mais clara que a bochecha fica intocada.
      if (lab[0] >= refL) continue;

      final t = (intensity * region * skin).clamp(0.0, 1.0);
      final newL = lab[0] + (refL - lab[0]) * t;
      final newA = lab[1] + (refA - lab[1]) * t * 0.6;
      final newB = lab[2] + (refB - lab[2]) * t * 0.6;

      ColorScience.oklabToLinearRgb(newL, newA, newB, rgb);
      output[i] = ColorScience.linearToSrgb8(rgb[0].clamp(0.0, 1.0));
      output[i + 1] = ColorScience.linearToSrgb8(rgb[1].clamp(0.0, 1.0));
      output[i + 2] = ColorScience.linearToSrgb8(rgb[2].clamp(0.0, 1.0));
    }
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
