import 'dart:math' as math;

/// Família de proporção da colagem.
enum CollageAspectFamily {
  ratio16x9,
  ratio4x3,
  square,
}

/// Orientação (ignorada para quadrado).
enum CollageOrientation {
  landscape,
  portrait,
}

/// Preset completo: proporção + orientação → ratio e eixo de empilhamento.
class CollageAspectPreset {
  const CollageAspectPreset({
    required this.family,
    this.orientation = CollageOrientation.portrait,
  });

  final CollageAspectFamily family;
  final CollageOrientation orientation;

  static const square = CollageAspectPreset(family: CollageAspectFamily.square);

  static const ratio16x9Portrait = CollageAspectPreset(
    family: CollageAspectFamily.ratio16x9,
    orientation: CollageOrientation.portrait,
  );

  static const ratio16x9Landscape = CollageAspectPreset(
    family: CollageAspectFamily.ratio16x9,
    orientation: CollageOrientation.landscape,
  );

  static const ratio4x3Portrait = CollageAspectPreset(
    family: CollageAspectFamily.ratio4x3,
    orientation: CollageOrientation.portrait,
  );

  static const ratio4x3Landscape = CollageAspectPreset(
    family: CollageAspectFamily.ratio4x3,
    orientation: CollageOrientation.landscape,
  );

  /// Largura / altura do canvas.
  double get widthOverHeight {
    switch (family) {
      case CollageAspectFamily.square:
        return 1;
      case CollageAspectFamily.ratio16x9:
        return orientation == CollageOrientation.landscape ? 16 / 9 : 9 / 16;
      case CollageAspectFamily.ratio4x3:
        return orientation == CollageOrientation.landscape ? 4 / 3 : 3 / 4;
    }
  }

  /// Landscape → empilha na horizontal; portrait/square → vertical.
  bool get isHorizontalStack =>
      family != CollageAspectFamily.square &&
      orientation == CollageOrientation.landscape;

  /// Dimensões do canvas com maior lado = [maxEdge].
  ({int width, int height}) canvasSize(int maxEdge) {
    final edge = maxEdge.clamp(64, 8192);
    final ratio = widthOverHeight;
    if (ratio >= 1) {
      final width = edge;
      final height = math.max(1, (edge / ratio).round());
      return (width: width, height: height);
    }
    final height = edge;
    final width = math.max(1, (edge * ratio).round());
    return (width: width, height: height);
  }
}

/// Curva de fusão + overlap variável com [fusionStrength].
class SeamlessBlendCurve {
  SeamlessBlendCurve._();

  /// Overlap mínimo (~6% do eixo longo).
  static const double minOverlapRatio = 0.06;

  /// Máximo da soma das duas emendas numa foto do meio (topo + base),
  /// escala com a fusão.
  static double middlePhotoOverlapBudget(double fusionStrength) {
    final f = fusionStrength.clamp(0.0, 1.0);
    return 0.42 + f * 0.55;
  }

  /// Fração máxima de overlap no eixo (em fusion=1).
  /// 2 fotos → 1.0 (cada uma cobre o canvas, ~50/50).
  /// N fotos → (N-1)/N (contribuição ~1/N).
  static double maxOverlapRatio(int photoCount) {
    final n = photoCount.clamp(2, 6);
    if (n <= 2) return 1.0;
    return (n - 1) / n;
  }

  /// Overlap em pixels ao longo do eixo de empilhamento.
  static int overlapPixels({
    required int axisLength,
    required int photoCount,
    required double fusionStrength,
  }) {
    if (axisLength <= 0 || photoCount < 2) return 0;

    final f = fusionStrength.clamp(0.0, 1.0);
    final maxRatio = maxOverlapRatio(photoCount);
    final ratio = minOverlapRatio + (maxRatio - minOverlapRatio) * f;
    final raw = (axisLength * ratio).round();
    return raw.clamp(4, axisLength);
  }

  /// Altura/largura de cada slot cover: `(L + (N-1)*o) / N`.
  static int slotSpan({
    required int axisLength,
    required int photoCount,
    required int overlap,
  }) {
    final n = photoCount.clamp(2, 6);
    final o = overlap.clamp(0, axisLength);
    return math.max(1, (axisLength + (n - 1) * o) ~/ n);
  }

  /// Peso da imagem inferior/direita em [t] (0 = só a de cima/esquerda).
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
