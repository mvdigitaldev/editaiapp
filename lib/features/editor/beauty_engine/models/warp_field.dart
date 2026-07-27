import 'dart:typed_data';
import 'dart:ui';

import 'mesh_region.dart';
import 'tri_mesh.dart';
import '../warp/models/control_point.dart';

/// Campo de deformacao calculado pelo warp engine.
class WarpField {
  final int gridWidth;
  final int gridHeight;
  final Float32List displacement;
  final Float32List mask;
  final Size imageSize;
  final MeshRegion region;
  final List<ControlPoint> controlPoints;
  final double intensity;

  const WarpField({
    required this.gridWidth,
    required this.gridHeight,
    required this.displacement,
    required this.mask,
    required this.imageSize,
    required this.region,
    this.controlPoints = const [],
    this.intensity = 0,
  });

  bool get isIdentity => intensity <= 0 || controlPoints.isEmpty;

  WarpField reset() => WarpField.identity(imageSize: imageSize, region: region);

  static WarpField identity({
    required Size imageSize,
    required MeshRegion region,
    int gridWidth = 8,
    int gridHeight = 8,
  }) {
    final cellCount = gridWidth * gridHeight;
    return WarpField(
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      displacement: Float32List(cellCount * 2),
      mask: Float32List(cellCount),
      imageSize: imageSize,
      region: region,
      controlPoints: const [],
      intensity: 0,
    );
  }

  Offset sampleDisplacement(Offset normalized) {
    if (isIdentity) {
      return Offset.zero;
    }

    final gx = (normalized.dx * (gridWidth - 1)).clamp(0.0, gridWidth - 1.0);
    final gy = (normalized.dy * (gridHeight - 1)).clamp(0.0, gridHeight - 1.0);

    final x0 = gx.floor();
    final y0 = gy.floor();
    final x1 = (x0 + 1).clamp(0, gridWidth - 1);
    final y1 = (y0 + 1).clamp(0, gridHeight - 1);
    final tx = gx - x0;
    final ty = gy - y0;

    final d00 = _cellDisplacement(x0, y0);
    final d10 = _cellDisplacement(x1, y0);
    final d01 = _cellDisplacement(x0, y1);
    final d11 = _cellDisplacement(x1, y1);

    final dx = _lerp(_lerp(d00.dx, d10.dx, tx), _lerp(d01.dx, d11.dx, tx), ty);
    final dy = _lerp(_lerp(d00.dy, d10.dy, tx), _lerp(d01.dy, d11.dy, tx), ty);
    return Offset(dx, dy);
  }

  double sampleMask(Offset normalized) {
    if (isIdentity) {
      return 0;
    }

    final gx = (normalized.dx * (gridWidth - 1)).clamp(0.0, gridWidth - 1.0);
    final gy = (normalized.dy * (gridHeight - 1)).clamp(0.0, gridHeight - 1.0);
    final x0 = gx.floor();
    final y0 = gy.floor();
    final x1 = (x0 + 1).clamp(0, gridWidth - 1);
    final y1 = (y0 + 1).clamp(0, gridHeight - 1);
    final tx = gx - x0;
    final ty = gy - y0;

    final m00 = _cellMask(x0, y0);
    final m10 = _cellMask(x1, y0);
    final m01 = _cellMask(x0, y1);
    final m11 = _cellMask(x1, y1);

    return _lerp(_lerp(m00, m10, tx), _lerp(m01, m11, tx), ty);
  }

  Offset _cellDisplacement(int x, int y) {
    final idx = (y * gridWidth + x) * 2;
    return Offset(displacement[idx], displacement[idx + 1]);
  }

  double _cellMask(int x, int y) => mask[y * gridWidth + x];

  /// Retângulo em pixels onde a máscara é não-zero (com margem de 1 célula).
  Rect? activePixelBounds() {
    if (isIdentity) {
      return null;
    }

    var minGx = gridWidth;
    var minGy = gridHeight;
    var maxGx = -1;
    var maxGy = -1;

    for (var gy = 0; gy < gridHeight; gy++) {
      for (var gx = 0; gx < gridWidth; gx++) {
        if (mask[gy * gridWidth + gx] <= 0.001) {
          continue;
        }
        if (gx < minGx) minGx = gx;
        if (gy < minGy) minGy = gy;
        if (gx > maxGx) maxGx = gx;
        if (gy > maxGy) maxGy = gy;
      }
    }

    if (maxGx < 0) {
      return null;
    }

    minGx = (minGx - 1).clamp(0, gridWidth - 1);
    minGy = (minGy - 1).clamp(0, gridHeight - 1);
    maxGx = (maxGx + 1).clamp(0, gridWidth - 1);
    maxGy = (maxGy + 1).clamp(0, gridHeight - 1);

    final left = (minGx / (gridWidth - 1)) * imageSize.width;
    final top = (minGy / (gridHeight - 1)) * imageSize.height;
    final right = (maxGx / (gridWidth - 1)) * imageSize.width;
    final bottom = (maxGy / (gridHeight - 1)) * imageSize.height;

    return Rect.fromLTRB(left, top, right, bottom);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// Parametros para calculo de warp.
class WarpRequest {
  final TriMesh mesh;
  final MeshRegion region;
  final Map<String, double> parameters;
  final Size imageSize;

  const WarpRequest({
    required this.mesh,
    required this.region,
    required this.parameters,
    required this.imageSize,
  });

  double parameter(String snakeCase, {String? camelCase, double defaultValue = 0}) {
    if (parameters.containsKey(snakeCase)) {
      return parameters[snakeCase]!.clamp(0.0, 1.0);
    }
    if (camelCase != null && parameters.containsKey(camelCase)) {
      return parameters[camelCase]!.clamp(0.0, 1.0);
    }
    return defaultValue;
  }
}
