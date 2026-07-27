import 'dart:math' as math;

/// Curva de fusão estilo Meitu: overlap fixo, slider controla suavidade.
class SeamlessBlendCurve {
  SeamlessBlendCurve._();

  /// Zona de sobreposição (~12% do eixo transversal da colagem).
  static const double overlapRatio = 0.12;

  /// Máximo da soma das duas emendas numa foto do meio (topo + base).
  static const double middlePhotoOverlapBudget = 0.42;

  /// Peso da imagem inferior/direita em [t] (0 = só a de cima/esquerda, 1 = só a de baixo/direita).
  static double blendWeight(double t, double fusionStrength) {
    final normalized = t.clamp(0.0, 1.0);
    final fusion = fusionStrength.clamp(0.0, 1.0);

    if (fusion < 0.02) {
      return normalized >= 0.5 ? 1.0 : 0.0;
    }

    final spread = 0.04 + fusion * 0.96;
    final remapped = ((normalized - 0.5) / spread + 0.5).clamp(0.0, 1.0);

    if (fusion >= 0.55) {
      return _cosineEase(remapped);
    }
    return _smoothstep(remapped);
  }

  static double _smoothstep(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static double _cosineEase(double t) {
    final x = t.clamp(0.0, 1.0);
    return (1 - math.cos(x * math.pi)) / 2;
  }
}

/// Interpolação gamma-correta (evita emendas escuras).
class SeamlessColorBlend {
  SeamlessColorBlend._();

  static int lerpChannel(int a, int b, double t) {
    final linearA = _srgbToLinear(a);
    final linearB = _srgbToLinear(b);
    final mixed = linearA + (linearB - linearA) * t;
    return _linearToSrgb(mixed).round().clamp(0, 255);
  }

  static double _srgbToLinear(int channel) {
    final c = channel / 255.0;
    if (c <= 0.04045) return c / 12.92;
    return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _linearToSrgb(double channel) {
    final c = channel.clamp(0.0, 1.0);
    if (c <= 0.0031308) return c * 12.92 * 255.0;
    return (1.055 * math.pow(c, 1.0 / 2.4) - 0.055) * 255.0;
  }
}
