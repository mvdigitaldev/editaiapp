import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'distance_transform.dart';

/// Máscaras 0/255 no grid do campo (não são RGBA de foto).
class RegionMasks {
  RegionMasks({
    required this.width,
    required this.height,
    required this.jaw,
    required this.jawActive,
    required this.eyes,
    required this.brows,
    required this.nose,
    required this.mouth,
    required this.faceCenter,
    required this.beard,
    required this.ears,
    required this.protected,
    required this.oval,
  });

  final int width;
  final int height;
  final Uint8List jaw;
  final Uint8List jawActive;
  final Uint8List eyes;
  final Uint8List brows;
  final Uint8List nose;
  final Uint8List mouth;
  final Uint8List faceCenter;
  final Uint8List beard;
  final Uint8List ears;
  final Uint8List protected;
  final Uint8List oval;

  int get pixelCount => width * height;

  int count(Uint8List mask) {
    var n = 0;
    for (final v in mask) {
      if (v != 0) n++;
    }
    return n;
  }
}

/// Raster de polígonos / discos no grid do campo. Sem imagem.
abstract final class RegionMaskRaster {
  RegionMaskRaster._();

  static Uint8List zeros(int width, int height) =>
      Uint8List(width * height);

  static void fillPolygon(Uint8List mask, int width, int height, List<Offset> ring) {
    if (ring.length < 3) {
      return;
    }
    var minX = width.toDouble();
    var minY = height.toDouble();
    var maxX = 0.0;
    var maxY = 0.0;
    for (final p in ring) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    final x0 = minX.floor().clamp(0, width - 1);
    final y0 = minY.floor().clamp(0, height - 1);
    final x1 = maxX.ceil().clamp(0, width - 1);
    final y1 = maxY.ceil().clamp(0, height - 1);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (_pointInPolygon(x + 0.5, y + 0.5, ring)) {
          mask[y * width + x] = 255;
        }
      }
    }
  }

  static void fillConvexHull(Uint8List mask, int width, int height, List<Offset> points) {
    fillPolygon(mask, width, height, convexHull(points));
  }

  static void fillDisk(
    Uint8List mask,
    int width,
    int height,
    Offset center,
    double radius,
  ) {
    if (radius <= 0) {
      return;
    }
    final r2 = radius * radius;
    final x0 = (center.dx - radius).floor().clamp(0, width - 1);
    final y0 = (center.dy - radius).floor().clamp(0, height - 1);
    final x1 = (center.dx + radius).ceil().clamp(0, width - 1);
    final y1 = (center.dy + radius).ceil().clamp(0, height - 1);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final ddx = x + 0.5 - center.dx;
        final ddy = y + 0.5 - center.dy;
        if (ddx * ddx + ddy * ddy <= r2) {
          mask[y * width + x] = 255;
        }
      }
    }
  }

  /// Expande a máscara em [radius] pixéis. Disco euclidiano: o chamfer L1 que
  /// isto substitui dilatava só `radius / √2` na diagonal e deixava o domínio
  /// em losango, com quinas a 45° que a rampa do campo depois imprimia.
  static void dilate(Uint8List mask, int width, int height, int radius) {
    if (radius <= 0) {
      return;
    }
    final dist = EuclideanDistanceTransform.toNonZeroOf(mask, width, height);
    final r = radius.toDouble();
    for (var i = 0; i < mask.length; i++) {
      if (dist[i] <= r) {
        mask[i] = 255;
      }
    }
  }

  static void orInto(Uint8List dest, Uint8List src) {
    for (var i = 0; i < dest.length; i++) {
      if (src[i] != 0) {
        dest[i] = 255;
      }
    }
  }

  static List<Offset> convexHull(List<Offset> points) {
    if (points.length <= 2) {
      return List<Offset>.from(points);
    }
    final sorted = [...points]..sort((a, b) {
        final dx = a.dx.compareTo(b.dx);
        return dx != 0 ? dx : a.dy.compareTo(b.dy);
      });
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    if (lower.isNotEmpty) {
      lower.removeLast();
    }
    if (upper.isNotEmpty) {
      upper.removeLast();
    }
    return [...lower, ...upper];
  }

  static bool _pointInPolygon(double x, double y, List<Offset> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final yi = ring[i].dy;
      final yj = ring[j].dy;
      final xi = ring[i].dx;
      final xj = ring[j].dx;
      final intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / ((yj - yi).abs() < 1e-12 ? 1e-12 : (yj - yi)) +
              xi);
      if (intersect) {
        inside = !inside;
      }
    }
    return inside;
  }
}
