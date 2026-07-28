import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Matte de pessoa no domínio Body Reshape (independente do detector legado).
class PersonMatte {
  final Uint8List alpha;
  final int width;
  final int height;
  final double confidence;
  final String providerId;

  /// Bounding box normalizado [0,1] da silhueta, se conhecido.
  final Rect? boundingRegion;

  const PersonMatte({
    required this.alpha,
    required this.width,
    required this.height,
    required this.providerId,
    this.confidence = 1,
    this.boundingRegion,
  })  : assert(confidence >= 0 && confidence <= 1),
        assert(width >= 0 && height >= 0);

  bool get isEmpty => alpha.isEmpty || width <= 0 || height <= 0;

  /// Amostra bilinear do alfa em coordenadas normalizadas [0,1].
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

    final v00 = alpha[y0 * width + x0] / 255.0;
    final v10 = alpha[y0 * width + x1] / 255.0;
    final v01 = alpha[y1 * width + x0] / 255.0;
    final v11 = alpha[y1 * width + x1] / 255.0;

    final top = v00 + (v10 - v00) * tx;
    final bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }

  PersonMatte copyWith({
    Uint8List? alpha,
    int? width,
    int? height,
    double? confidence,
    String? providerId,
    Rect? boundingRegion,
  }) {
    return PersonMatte(
      alpha: alpha ?? this.alpha,
      width: width ?? this.width,
      height: height ?? this.height,
      confidence: confidence ?? this.confidence,
      providerId: providerId ?? this.providerId,
      boundingRegion: boundingRegion ?? this.boundingRegion,
    );
  }
}
