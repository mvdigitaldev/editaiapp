import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/mesh_region.dart';
import '../models/warp_field.dart';
import 'mls_solver.dart';
import 'models/control_point.dart';

/// Constroi grade de displacement + mascara a partir de control points MLS.
class WarpFieldBuilder {
  const WarpFieldBuilder({
    this.gridWidth = 64,
    this.gridHeight = 64,
    this.maskFeatherPx = 24,
  });

  final int gridWidth;
  final int gridHeight;
  final double maskFeatherPx;

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
    final featherNorm = maskFeatherPx / math.max(imageSize.width, imageSize.height);

    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        final idx = gy * gridWidth + gx;
        final px = (gx / (gridWidth - 1)) * imageSize.width;
        final py = (gy / (gridHeight - 1)) * imageSize.height;
        final point = Offset(px, py);

        final source = MlsSolver.inverse(controlPoints, point);
        displacement[idx * 2] = source.dx - px;
        displacement[idx * 2 + 1] = source.dy - py;

        mask[idx] = _computeMask(point, bounds, featherNorm, imageSize);
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

    for (final point in points) {
      if (point.isAnchor) {
        continue;
      }
      minX = math.min(minX, point.source.dx);
      minY = math.min(minY, point.source.dy);
      maxX = math.max(maxX, point.source.dx);
      maxY = math.max(maxY, point.source.dy);
    }

    if (maxX <= minX || maxY <= minY) {
      return Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
    }

    const padding = 32.0;
    return Rect.fromLTRB(
      math.max(0, minX - padding),
      math.max(0, minY - padding),
      math.min(imageSize.width, maxX + padding),
      math.min(imageSize.height, maxY + padding),
    );
  }

  double _computeMask(Offset point, Rect bounds, double featherNorm, Size imageSize) {
    if (!bounds.contains(point)) {
      return 0;
    }

    final nx = point.dx / imageSize.width;
    final ny = point.dy / imageSize.height;
    final left = bounds.left / imageSize.width;
    final top = bounds.top / imageSize.height;
    final right = bounds.right / imageSize.width;
    final bottom = bounds.bottom / imageSize.height;

    final distLeft = (nx - left).abs();
    final distTop = (ny - top).abs();
    final distRight = (right - nx).abs();
    final distBottom = (bottom - ny).abs();
    final edgeDist = math.min(
      math.min(distLeft, distRight),
      math.min(distTop, distBottom),
    );

    if (edgeDist >= featherNorm) {
      return 1;
    }
    return (edgeDist / featherNorm).clamp(0.0, 1.0);
  }
}
