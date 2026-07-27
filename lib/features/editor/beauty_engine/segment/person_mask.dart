import 'dart:typed_data';

import '../models/image_source.dart';

/// Máscara de pessoa (uint8 0–255, 1 canal).
class PersonMask {
  final Uint8List bytes;
  final int width;
  final int height;

  const PersonMask({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// Amostra bilinear em coordenadas normalizadas [0,1].
  double sampleNormalized(double nx, double ny) {
    if (bytes.isEmpty || width <= 0 || height <= 0) {
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

    final v00 = bytes[y0 * width + x0] / 255.0;
    final v10 = bytes[y0 * width + x1] / 255.0;
    final v01 = bytes[y1 * width + x0] / 255.0;
    final v11 = bytes[y1 * width + x1] / 255.0;

    final top = v00 + (v10 - v00) * tx;
    final bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }
}

/// Detecção de silhueta — sem dependência de UI.
abstract class PersonMaskDetector {
  Future<PersonMask?> detect(ImageSource source);
}
