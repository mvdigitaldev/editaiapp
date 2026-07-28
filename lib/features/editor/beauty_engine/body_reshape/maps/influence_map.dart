import 'dart:typed_data';
import 'dart:ui';

import '../models/body_region.dart';

/// Mapa de influência por pixel (0–1) orientado à anatomia.
///
/// Fora do matte/domínio protegido o valor é zero — não expande ao fundo.
class InfluenceMap {
  final Float32List values;
  final int width;
  final int height;
  final Size imageSize;
  final Set<BodyRegion> regions;
  final double confidence;
  final double maxValue;

  const InfluenceMap({
    required this.values,
    required this.width,
    required this.height,
    required this.imageSize,
    required this.regions,
    required this.confidence,
    required this.maxValue,
  })  : assert(width >= 0 && height >= 0),
        assert(confidence >= 0 && confidence <= 1);

  bool get isEmpty => values.isEmpty || width <= 0 || height <= 0;

  bool get isIdentity => maxValue <= 1e-6;

  /// Amostra bilinear em coordenadas normalizadas [0,1].
  double sampleNormalized(double nx, double ny) {
    if (isEmpty) {
      return 0;
    }

    final fx = (nx.clamp(0.0, 1.0) * (width - 1));
    final fy = (ny.clamp(0.0, 1.0) * (height - 1));
    final x0 = fx.floor().clamp(0, width - 1);
    final y0 = fy.floor().clamp(0, height - 1);
    final x1 = (x0 + 1).clamp(0, width - 1);
    final y1 = (y0 + 1).clamp(0, height - 1);
    final tx = fx - x0;
    final ty = fy - y0;

    final v00 = values[y0 * width + x0];
    final v10 = values[y0 * width + x1];
    final v01 = values[y1 * width + x0];
    final v11 = values[y1 * width + x1];

    final top = v00 + (v10 - v00) * tx;
    final bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }

  double sampleAtPixel(int x, int y) {
    if (isEmpty) {
      return 0;
    }
    final sx = x.clamp(0, width - 1);
    final sy = y.clamp(0, height - 1);
    return values[sy * width + sx];
  }

  /// Média da influência dentro da região de interest (bbox normalizado).
  double meanInNormalizedRect(Rect rect) {
    if (isEmpty) {
      return 0;
    }
    final x0 = (rect.left.clamp(0.0, 1.0) * (width - 1)).floor();
    final y0 = (rect.top.clamp(0.0, 1.0) * (height - 1)).floor();
    final x1 = (rect.right.clamp(0.0, 1.0) * (width - 1)).ceil();
    final y1 = (rect.bottom.clamp(0.0, 1.0) * (height - 1)).ceil();
    var sum = 0.0;
    var count = 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        sum += values[y * width + x];
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }
}
