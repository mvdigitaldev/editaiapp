import 'dart:typed_data';

/// Análise estrutural do fundo (linhas/rigidez). Sprint 2 entrega o contrato.
class BackgroundAnalysis {
  final Uint8List rigidity;
  final int width;
  final int height;
  final String providerId;
  final double confidence;

  const BackgroundAnalysis({
    required this.rigidity,
    required this.width,
    required this.height,
    required this.providerId,
    this.confidence = 1,
  }) : assert(confidence >= 0 && confidence <= 1);

  bool get isEmpty => rigidity.isEmpty || width <= 0 || height <= 0;
}
