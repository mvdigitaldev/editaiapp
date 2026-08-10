import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../body_reshape/maps/influence_map.dart';
import '../body_reshape/maps/matte_preprocessor.dart';
import '../body_reshape/maps/person_mask_bridge.dart';
import '../body_reshape/maps/protection_maps.dart';
import '../models/mesh_region.dart';
import '../models/warp_field.dart';
import '../segment/person_mask.dart';
import 'mls_solver.dart';
import 'models/control_point.dart';

/// Qualidade da grade MLS: interativo prioriza latência; export prioriza suavidade.
enum WarpFieldQuality {
  interactive,
  preview,
  export,
}

/// Constroi grade de displacement + mascara a partir de control points MLS.
class WarpFieldBuilder {
  const WarpFieldBuilder({
    this.gridWidth = 64,
    this.gridHeight = 64,
    this.maskFeatherPx = 24,
    this.mlsIterations = 6,
    this.outerRingPx = 12,
    this.maxDisplacementFraction = 0.40,
    this.missingMatteIntensityScale = 0.65,
    this.mattePreprocessor = const MattePreprocessor(),
  });

  final int gridWidth;
  final int gridHeight;
  final double maskFeatherPx;
  final int mlsIterations;

  /// Mantido por compatibilidade de API; o domínio fora do matte agora é zero.
  final double outerRingPx;

  /// Clamp de |disp| como fração da meia-largura da ROI (anti-fold).
  final double maxDisplacementFraction;

  /// Escala conservadora quando não há PersonMask/matte.
  final double missingMatteIntensityScale;

  final MattePreprocessor mattePreprocessor;

  /// Grade e feather proporcionais à imagem — menos pixelização nas bordas.
  factory WarpFieldBuilder.forImageSize(
    Size imageSize, {
    bool highQuality = false,
    WarpFieldQuality quality = WarpFieldQuality.preview,
  }) {
    final resolved = highQuality ? WarpFieldQuality.export : quality;
    final minDim = math.min(imageSize.width, imageSize.height);

    late final double cellPx;
    late final int minGrid;
    late final int maxGrid;
    late final int mlsIterations;
    late final double outerRingPx;

    switch (resolved) {
      case WarpFieldQuality.interactive:
        cellPx = 14.0;
        minGrid = 48;
        maxGrid = 80;
        mlsIterations = 5;
        outerRingPx = 10;
      case WarpFieldQuality.preview:
        cellPx = 10.0;
        minGrid = 64;
        maxGrid = 112;
        mlsIterations = 6;
        outerRingPx = 12;
      case WarpFieldQuality.export:
        cellPx = 8.0;
        minGrid = 80;
        maxGrid = 160;
        mlsIterations = 8;
        outerRingPx = 14;
    }

    final grid = (minDim / cellPx).round().clamp(minGrid, maxGrid);
    final feather = math.max(28.0, minDim * 0.045);

    return WarpFieldBuilder(
      gridWidth: grid,
      gridHeight: grid,
      maskFeatherPx: feather,
      mlsIterations: mlsIterations,
      outerRingPx: outerRingPx,
    );
  }

  /// face_slim preview — grade densa (~4 px/célula) p/ fallback backward.
  factory WarpFieldBuilder.forFaceSlimInteractive(Size imageSize) {
    final minDim = math.min(imageSize.width, imageSize.height);
    const cellPx = 4.0;
    final grid = (minDim / cellPx).round().clamp(160, 192);
    return WarpFieldBuilder(
      gridWidth: grid,
      gridHeight: grid,
      maskFeatherPx: math.max(24.0, minDim * 0.04),
      mlsIterations: 5,
      outerRingPx: 10,
    );
  }

  /// Preview interativo V3 — grade mais densa (~6 px/célula) para warps locais
  /// (olhos/boca); MLS continua em [forFaceWarpInteractive].
  factory WarpFieldBuilder.forFaceMeshV3Interactive(Size imageSize) {
    final minDim = math.min(imageSize.width, imageSize.height);
    const cellPx = 6.0;
    final grid = (minDim / cellPx).round().clamp(80, 112);
    return WarpFieldBuilder(
      gridWidth: grid,
      gridHeight: grid,
      maskFeatherPx: math.max(28.0, minDim * 0.045),
      mlsIterations: 5,
      outerRingPx: 12,
    );
  }

  /// Sprint 36 — render direto na malha: grade fina (~2.5 px/célula), até 256.
  factory WarpFieldBuilder.forFaceMeshV3Direct(
    Size imageSize, {
    bool exporting = false,
  }) {
    final minDim = math.min(imageSize.width, imageSize.height);
    final cellPx = exporting ? 2.0 : 2.5;
    final grid = (minDim / cellPx).round().clamp(120, 256);
    return WarpFieldBuilder(
      gridWidth: grid,
      gridHeight: grid,
      maskFeatherPx: math.max(24.0, minDim * 0.04),
      mlsIterations: 5,
      outerRingPx: 10,
    );
  }

  /// Preview interativo — grade pequena (~11 px/célula), latência mínima.
  factory WarpFieldBuilder.forFaceWarpInteractive(Size imageSize) {
    final minDim = math.min(imageSize.width, imageSize.height);
    const cellPx = 11.0;
    final grid = (minDim / cellPx).round().clamp(48, 72);
    return WarpFieldBuilder(
      gridWidth: grid,
      gridHeight: grid,
      maskFeatherPx: math.max(28.0, minDim * 0.045),
      mlsIterations: 5,
      outerRingPx: 12,
    );
  }

  /// Preview: grade moderada. Export: grade densa.
  factory WarpFieldBuilder.forFaceWarp(
    Size imageSize, {
    bool exporting = false,
  }) {
    final minDim = math.min(imageSize.width, imageSize.height);
    final cellPx = exporting ? 4.5 : 6.0;
    final maxGrid = exporting ? 280 : 128;
    final minGrid = exporting ? 120 : 72;
    final grid = (minDim / cellPx).round().clamp(minGrid, maxGrid);
    final feather = math.max(32.0, minDim * 0.05);
    return WarpFieldBuilder(
      gridWidth: grid,
      gridHeight: grid,
      maskFeatherPx: feather,
      mlsIterations: exporting ? 7 : 6,
      outerRingPx: 14,
    );
  }

  WarpField build({
    required List<ControlPoint> controlPoints,
    required Size imageSize,
    required MeshRegion region,
    required double intensity,
    PersonMask? personMask,
    ProtectionMaps? protectionMaps,
    InfluenceMap? influenceMap,
  }) {
    if (intensity <= 0 || controlPoints.isEmpty) {
      return WarpField.identity(imageSize: imageSize, region: region);
    }

    final protection = protectionMaps ??
        (personMask == null
            ? null
            : mattePreprocessor.buildProtectionMaps(
                personMask.toPersonMatte(),
                imageSize: imageSize,
              ));

    final cellCount = gridWidth * gridHeight;
    final displacement = Float32List(cellCount * 2);
    final mask = Float32List(cellCount);

    final bounds = _controlBounds(controlPoints, imageSize);
    final featherPx = maskFeatherPx;
    final invW = imageSize.width > 0 ? 1.0 / imageSize.width : 0.0;
    final invH = imageSize.height > 0 ? 1.0 / imageSize.height : 0.0;
    final halfW = bounds.width * 0.5;
    final missingScale =
        protection == null ? missingMatteIntensityScale.clamp(0.0, 1.0) : 1.0;
    final maxDisp = math.max(
          imageSize.width * 0.035,
          halfW * maxDisplacementFraction,
        ) *
        missingScale;
    // Fallback legado quando não há InfluenceMap V2.
    final capsule = influenceMap == null
        ? _capsuleFromPoints(controlPoints, imageSize)
        : null;

    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        final idx = gy * gridWidth + gx;
        final px = (gx / (gridWidth - 1)) * imageSize.width;
        final py = (gy / (gridHeight - 1)) * imageSize.height;
        final point = Offset(px, py);
        final nx = px * invW;
        final ny = py * invH;

        var m = 1.0;
        if (influenceMap != null && !influenceMap.isEmpty) {
          m = influenceMap.sampleNormalized(nx, ny);
        } else {
          m = _computeMask(point, bounds, featherPx);
          if (m > 0.001 && capsule != null) {
            m *= _capsuleFalloff(point, capsule);
          }
        }

        if (m <= 0.001) {
          mask[idx] = 0;
          continue;
        }

        if (influenceMap == null && protection != null) {
          // Domínio controlado pelo matte: fora → peso 0 (sem anel de fundo).
          m *= protection.sampleWarpWeight(nx, ny);
        } else if (influenceMap == null) {
          // Sem matte: continua utilizável, porém mais conservador.
          m *= missingScale;
        }

        mask[idx] = m;
        if (m <= 0.001) {
          continue;
        }

        final source = MlsSolver.inverse(
          controlPoints,
          point,
          iterations: mlsIterations,
        );
        var dx = source.dx - px;
        var dy = source.dy - py;
        final mag = math.sqrt(dx * dx + dy * dy);
        if (mag > maxDisp && mag > 1e-6) {
          final s = maxDisp / mag;
          dx *= s;
          dy *= s;
        }
        displacement[idx * 2] = dx;
        displacement[idx * 2 + 1] = dy;
      }
    }

    return WarpField(
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      displacement: displacement,
      mask: mask,
      imageSize: imageSize,
      region: region,
      controlPoints: controlPoints,
      intensity: intensity,
    );
  }

  Rect _controlBounds(List<ControlPoint> points, Size imageSize) {
    var minX = imageSize.width;
    var minY = imageSize.height;
    var maxX = 0.0;
    var maxY = 0.0;
    var maxShift = 0.0;

    for (final point in points) {
      if (point.isAnchor) {
        continue;
      }
      minX = math.min(minX, point.source.dx);
      minY = math.min(minY, point.source.dy);
      maxX = math.max(maxX, point.source.dx);
      maxY = math.max(maxY, point.source.dy);
      minX = math.min(minX, point.target.dx);
      minY = math.min(minY, point.target.dy);
      maxX = math.max(maxX, point.target.dx);
      maxY = math.max(maxY, point.target.dy);
      maxShift = math.max(maxShift, point.delta.distance);
    }

    if (maxX <= minX || maxY <= minY) {
      return Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
    }

    final minDim = math.min(imageSize.width, imageSize.height);
    final cpSpread = math.max(maxX - minX, maxY - minY);
    // Warps locais (olhos/nariz/boca): evita retângulo gigante que puxa a boca
    // quando só os olhos rotacionam.
    final padding = math.max(
      cpSpread * 0.42,
      maxShift * 2.2 + maskFeatherPx + outerRingPx,
    ).clamp(20.0, minDim * 0.14);
    return Rect.fromLTRB(
      math.max(0, minX - padding),
      math.max(0, minY - padding),
      math.min(imageSize.width, maxX + padding),
      math.min(imageSize.height, maxY + padding),
    );
  }

  double _computeMask(
    Offset point,
    Rect bounds,
    double featherPx,
  ) {
    if (!bounds.contains(point)) {
      return 0;
    }

    final distLeft = point.dx - bounds.left;
    final distTop = point.dy - bounds.top;
    final distRight = bounds.right - point.dx;
    final distBottom = bounds.bottom - point.dy;
    final edgeDistPx = math.min(
      math.min(distLeft, distRight),
      math.min(distTop, distBottom),
    );

    if (edgeDistPx >= featherPx) {
      return 1;
    }

    final t = (edgeDistPx / featherPx).clamp(0.0, 1.0);
    return _smoothstep(t);
  }

  /// Cápsula vertical aproximada a partir dos CPs móveis (eixo do torso).
  ({Offset top, Offset bottom, double radius})? _capsuleFromPoints(
    List<ControlPoint> points,
    Size imageSize,
  ) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    var count = 0;
    for (final p in points) {
      if (p.isAnchor) continue;
      minX = math.min(minX, p.source.dx);
      maxX = math.max(maxX, p.source.dx);
      minY = math.min(minY, p.source.dy);
      maxY = math.max(maxY, p.source.dy);
      count++;
    }
    if (count < 2 || !minX.isFinite) {
      return null;
    }
    final cx = (minX + maxX) * 0.5;
    final radius = math.max((maxX - minX) * 0.55, imageSize.width * 0.04);
    return (
      top: Offset(cx, minY),
      bottom: Offset(cx, maxY),
      radius: radius,
    );
  }

  double _capsuleFalloff(
    Offset point,
    ({Offset top, Offset bottom, double radius}) capsule,
  ) {
    final axis = capsule.bottom - capsule.top;
    final len2 = axis.dx * axis.dx + axis.dy * axis.dy;
    if (len2 < 1) {
      return 1;
    }
    final t = (((point.dx - capsule.top.dx) * axis.dx +
                (point.dy - capsule.top.dy) * axis.dy) /
            len2)
        .clamp(0.0, 1.0);
    final closest = Offset(
      capsule.top.dx + axis.dx * t,
      capsule.top.dy + axis.dy * t,
    );
    final dist = (point - closest).distance;
    final r = capsule.radius;
    if (dist <= r * 0.55) {
      return 1;
    }
    if (dist >= r) {
      return 0;
    }
    final u = 1.0 - ((dist - r * 0.55) / (r * 0.45));
    return _smoothstep(u.clamp(0.0, 1.0));
  }

  static double _smoothstep(double t) {
    return t * t * (3 - 2 * t);
  }
}
