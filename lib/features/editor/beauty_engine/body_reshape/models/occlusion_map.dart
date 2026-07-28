import 'dart:typed_data';

/// Mapa de oclusão: 0 = livre, 255 = oclusor rígido a preservar.
class OcclusionMap {
  final Uint8List weights;
  final int width;
  final int height;
  final String providerId;
  final double confidence;

  const OcclusionMap({
    required this.weights,
    required this.width,
    required this.height,
    required this.providerId,
    this.confidence = 1,
  }) : assert(confidence >= 0 && confidence <= 1);

  bool get isEmpty => weights.isEmpty || width <= 0 || height <= 0;
}
