import 'dart:math' as math;
import 'dart:typed_data';

/// Campo de distância assinada em pixels da resolução do matte.
///
/// Convenção: negativo = interior da pessoa; positivo = exterior; 0 = contorno.
class SignedDistanceField {
  final Float32List distances;
  final int width;
  final int height;

  const SignedDistanceField({
    required this.distances,
    required this.width,
    required this.height,
  }) : assert(width >= 0 && height >= 0);

  bool get isEmpty => distances.isEmpty || width <= 0 || height <= 0;

  double sampleAtPixel(int x, int y) {
    if (isEmpty) {
      return 0;
    }
    final sx = x.clamp(0, width - 1);
    final sy = y.clamp(0, height - 1);
    return distances[sy * width + sx];
  }

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

    final v00 = distances[y0 * width + x0];
    final v10 = distances[y0 * width + x1];
    final v01 = distances[y1 * width + x0];
    final v11 = distances[y1 * width + x1];

    final top = v00 + (v10 - v00) * tx;
    final bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }

  double get maxAbsDistance {
    var maximum = 0.0;
    for (final value in distances) {
      maximum = math.max(maximum, value.abs());
    }
    return maximum;
  }
}
