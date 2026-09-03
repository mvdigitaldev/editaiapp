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
    // Por linha, as arestas que o raio horizontal atravessa e a abscissa de
    // cada travessia são as mesmas para todos os pixels dela. Calculá-las uma
    // vez por linha, em vez de percorrer o anel em cada pixel, poupa o factor
    // do número de vértices: o oval da cara tem 36, e a sua caixa cobre meia
    // imagem. A regra é a mesma de [pointInPolygon] — um ponto está dentro
    // quando o número de travessias à sua direita é ímpar — logo o conjunto de
    // pixels marcados é idêntico, incluindo os casos degenerados.
    final crossings = <double>[];
    for (var y = y0; y <= y1; y++) {
      final yc = y + 0.5;
      crossings.clear();
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final yi = ring[i].dy;
        final yj = ring[j].dy;
        if ((yi > yc) == (yj > yc)) {
          continue;
        }
        final span = yj - yi;
        final denom = span.abs() < 1e-12 ? 1e-12 : span;
        crossings.add((ring[j].dx - ring[i].dx) * (yc - yi) / denom + ring[i].dx);
      }
      if (crossings.isEmpty) {
        continue;
      }
      crossings.sort();
      final total = crossings.length;
      var passed = 0;
      final row = y * width;
      for (var x = x0; x <= x1; x++) {
        final xc = x + 0.5;
        while (passed < total && crossings[passed] <= xc) {
          passed++;
        }
        if ((total - passed).isOdd) {
          mask[row + x] = 255;
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
    // A dilatação é local: nada a mais de `radius` de um pixel marcado pode
    // mudar. Medir a distância na imagem inteira para depois só olhar a caixa
    // do que está marcado custava 12,5 ms dos 34 ms das máscaras do `chin`.
    var left = width;
    var top = height;
    var right = -1;
    var bottom = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] == 0) {
          continue;
        }
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        bottom = y;
      }
    }
    if (right < 0) {
      return;
    }
    final pad = radius + 1;
    final winLeft = math.max(0, left - pad);
    final winTop = math.max(0, top - pad);
    final winRight = math.min(width - 1, right + pad);
    final winBottom = math.min(height - 1, bottom + pad);
    final winWidth = winRight - winLeft + 1;
    final winHeight = winBottom - winTop + 1;

    final sub = Uint8List(winWidth * winHeight);
    for (var y = 0; y < winHeight; y++) {
      final from = (winTop + y) * width + winLeft;
      sub.setRange(y * winWidth, (y + 1) * winWidth, mask, from);
    }
    final dist =
        EuclideanDistanceTransform.toNonZeroOf(sub, winWidth, winHeight);
    final r = radius.toDouble();
    for (var y = 0; y < winHeight; y++) {
      final subRow = y * winWidth;
      final row = (winTop + y) * width + winLeft;
      for (var x = 0; x < winWidth; x++) {
        if (dist[subRow + x] <= r) {
          mask[row + x] = 255;
        }
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

  /// Regra de pertença do anel, ponto a ponto. É a definição que
  /// [fillPolygon] rasteriza por linha, e é pública para os testes poderem
  /// comparar contra ela.
  static bool pointInPolygon(double x, double y, List<Offset> ring) {
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
