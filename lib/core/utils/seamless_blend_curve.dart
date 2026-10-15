import 'dart:math' as math;

/// Família de proporção da colagem.
enum CollageAspectFamily {
  ratio16x9,
  ratio4x3,
  square,
}

/// Orientação do canvas (ignorada para quadrado). Independente da montagem.
enum CollageOrientation {
  landscape,
  portrait,
}

/// Direção da montagem (empilhamento das fotos), independente da proporção.
enum CollageStackDirection {
  /// Fotos uma em cima da outra (cima → baixo).
  vertical,

  /// Fotos lado a lado (esquerda → direita).
  horizontal,
}

/// Preset: proporção do canvas + orientação + direção da montagem.
class CollageAspectPreset {
  const CollageAspectPreset({
    required this.family,
    this.orientation = CollageOrientation.portrait,
    this.stackDirection = CollageStackDirection.vertical,
  });

  final CollageAspectFamily family;
  final CollageOrientation orientation;
  final CollageStackDirection stackDirection;

  static const square = CollageAspectPreset(family: CollageAspectFamily.square);

  static const ratio16x9Portrait = CollageAspectPreset(
    family: CollageAspectFamily.ratio16x9,
    orientation: CollageOrientation.portrait,
    stackDirection: CollageStackDirection.vertical,
  );

  static const ratio16x9Landscape = CollageAspectPreset(
    family: CollageAspectFamily.ratio16x9,
    orientation: CollageOrientation.landscape,
    stackDirection: CollageStackDirection.horizontal,
  );

  static const ratio4x3Portrait = CollageAspectPreset(
    family: CollageAspectFamily.ratio4x3,
    orientation: CollageOrientation.portrait,
    stackDirection: CollageStackDirection.vertical,
  );

  static const ratio4x3Landscape = CollageAspectPreset(
    family: CollageAspectFamily.ratio4x3,
    orientation: CollageOrientation.landscape,
    stackDirection: CollageStackDirection.horizontal,
  );

  CollageAspectPreset copyWith({
    CollageAspectFamily? family,
    CollageOrientation? orientation,
    CollageStackDirection? stackDirection,
  }) {
    return CollageAspectPreset(
      family: family ?? this.family,
      orientation: orientation ?? this.orientation,
      stackDirection: stackDirection ?? this.stackDirection,
    );
  }

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

  /// Empilha na horizontal (lado a lado).
  bool get isHorizontalStack =>
      stackDirection == CollageStackDirection.horizontal;

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

  /// Overlap já com o tecto da foto do meio.
  static int resolvedOverlap({
    required int axisLength,
    required int photoCount,
    required double fusionStrength,
  }) {
    final overlap = overlapPixels(
      axisLength: axisLength,
      photoCount: photoCount,
      fusionStrength: fusionStrength,
    );
    if (photoCount <= 2) return overlap;
    final slotHint = slotSpan(
      axisLength: axisLength,
      photoCount: photoCount,
      overlap: overlap,
    );
    final budget =
        (slotHint * middlePhotoOverlapBudget(fusionStrength)).round();
    final maxEach = math.max(4, budget ~/ 2);
    return math.min(overlap, maxEach);
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

/// Geometria dos slots. A pré-visualização e o export usam a mesma conta.
class SeamlessSlotLayout {
  const SeamlessSlotLayout({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.horizontal,
    required this.overlap,
    required this.slotMain,
    required this.step,
    required this.photoCount,
  });

  final int canvasWidth;
  final int canvasHeight;
  final bool horizontal;
  final int overlap;
  final int slotMain;
  final int step;
  final int photoCount;

  int get axisLength => horizontal ? canvasWidth : canvasHeight;

  static SeamlessSlotLayout compute({
    required CollageAspectPreset aspect,
    required int photoCount,
    required double fusionStrength,
    int maxEdge = 1000,
  }) {
    final size = aspect.canvasSize(maxEdge);
    final horizontal = aspect.isHorizontalStack;
    final axis = horizontal ? size.width : size.height;
    final overlap = SeamlessBlendCurve.resolvedOverlap(
      axisLength: axis,
      photoCount: photoCount,
      fusionStrength: fusionStrength,
    );
    final slotMain = SeamlessBlendCurve.slotSpan(
      axisLength: axis,
      photoCount: photoCount,
      overlap: overlap,
    );
    return SeamlessSlotLayout(
      canvasWidth: size.width,
      canvasHeight: size.height,
      horizontal: horizontal,
      overlap: overlap,
      slotMain: slotMain,
      step: math.max(1, slotMain - overlap),
      photoCount: photoCount,
    );
  }
}

/// Enquadramento cover de uma foto no slot, com folga para arrastar.
class SeamlessCoverFrame {
  const SeamlessCoverFrame({
    required this.scale,
    required this.scaledWidth,
    required this.scaledHeight,
    required this.overflowX,
    required this.overflowY,
  });

  /// Folga mínima numa das direcções, para a foto sempre poder mexer um pouco.
  static const double minPanSlack = 0.12;

  final double scale;
  final double scaledWidth;
  final double scaledHeight;
  final double overflowX;
  final double overflowY;

  static SeamlessCoverFrame measure({
    required double sourceWidth,
    required double sourceHeight,
    required double slotWidth,
    required double slotHeight,
  }) {
    if (sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        slotWidth <= 0 ||
        slotHeight <= 0) {
      return const SeamlessCoverFrame(
        scale: 1,
        scaledWidth: 1,
        scaledHeight: 1,
        overflowX: 0,
        overflowY: 0,
      );
    }

    var scale = math.max(slotWidth / sourceWidth, slotHeight / sourceHeight);
    var scaledW = sourceWidth * scale;
    var scaledH = sourceHeight * scale;
    var overflowX = math.max(0.0, scaledW - slotWidth);
    var overflowY = math.max(0.0, scaledH - slotHeight);
    final tightX = overflowX < slotWidth * minPanSlack;
    final tightY = overflowY < slotHeight * minPanSlack;
    if (tightX && tightY) {
      final kx = (slotWidth * (1 + minPanSlack)) / scaledW;
      final ky = (slotHeight * (1 + minPanSlack)) / scaledH;
      scale *= math.max(1.0, math.min(kx, ky));
      scaledW = sourceWidth * scale;
      scaledH = sourceHeight * scale;
      overflowX = math.max(0.0, scaledW - slotWidth);
      overflowY = math.max(0.0, scaledH - slotHeight);
    }

    return SeamlessCoverFrame(
      scale: scale,
      scaledWidth: scaledW,
      scaledHeight: scaledH,
      overflowX: overflowX,
      overflowY: overflowY,
    );
  }
}
