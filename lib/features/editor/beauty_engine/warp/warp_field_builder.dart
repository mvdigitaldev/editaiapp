import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/mesh_region.dart';
import '../models/warp_field.dart';
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
  });

  final int gridWidth;
  final int gridHeight;
  final double maskFeatherPx;
  final int mlsIterations;

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

    switch (resolved) {
      case WarpFieldQuality.interactive:
        cellPx = 18.0;
        minGrid = 40;
        maxGrid = 64;
        mlsIterations = 3;
      case WarpFieldQuality.preview:
        cellPx = 14.0;
        minGrid = 56;
        maxGrid = 80;
        mlsIterations = 4;
      case WarpFieldQuality.export:
        cellPx = 10.0;
        minGrid = 80;
        maxGrid = 144;
        mlsIterations = 6;
    }

    final grid = (minDim / cellPx).round().clamp(minGrid, maxGrid);
    final feather = math.max(32.0, minDim * 0.05);

    return WarpFieldBuilder(
      gridWidth: grid,
      gridHeight: grid,
      maskFeatherPx: feather,
      mlsIterations: mlsIterations,
    );
  }

  WarpField build({
    required List<ControlPoint> controlPoints,
    required Size imageSize,
    required MeshRegion region,
    required double intensity,
  }) {
    if (intensity <= 0 || controlPoints.isEmpty) {
      return WarpField.identity(imageSize: imageSize, region: region);
    }

    final cellCount = gridWidth * gridHeight;
    final displacement = Float32List(cellCount * 2);
    final mask = Float32List(cellCount);

    final bounds = _controlBounds(controlPoints, imageSize);
    final featherPx = maskFeatherPx;

    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        final idx = gy * gridWidth + gx;
        final px = (gx / (gridWidth - 1)) * imageSize.width;
        final py = (gy / (gridHeight - 1)) * imageSize.height;
        final point = Offset(px, py);

        final m = _computeMask(point, bounds, featherPx);
        mask[idx] = m;
        if (m <= 0.001) {
          continue;
        }

        final source = MlsSolver.inverse(
          controlPoints,
          point,
          iterations: mlsIterations,
        );
        displacement[idx * 2] = source.dx - px;
        displacement[idx * 2 + 1] = source.dy - py;
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
      // Inclui target — zona vacante após slim precisa de mask>0.
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
    // Padding cobre a silhueta antiga + zona liberada + feather.
    final padding = math.max(
      64.0,
      math.max(minDim * 0.08, maxShift * 2.2 + maskFeatherPx),
    );
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

  static double _smoothstep(double t) {
    return t * t * (3 - 2 * t);
  }
}
