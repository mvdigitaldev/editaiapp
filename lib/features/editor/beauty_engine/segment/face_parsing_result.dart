import 'dart:typed_data';

import 'face_parsing_class.dart';

/// Máscara categórica de face parsing na resolução de saída (R8 por pixel).
class FaceParsingResult {
  const FaceParsingResult({
    required this.classes,
    required this.width,
    required this.height,
    required this.source,
    this.confidence = 1,
  });

  final Uint8List classes;
  final int width;
  final int height;
  final FaceParsingSource source;
  final double confidence;

  bool get isEmpty => width <= 0 || height <= 0 || classes.isEmpty;

  FaceParsingClass classAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return FaceParsingClass.background;
    }
    return FaceParsingClass.fromIndex(classes[y * width + x]);
  }

  FaceParsingClass classAtNormalized(double nx, double ny) {
    final x = (nx * width).floor().clamp(0, width - 1);
    final y = (ny * height).floor().clamp(0, height - 1);
    return classAt(x, y);
  }

  double coverageOf(FaceParsingClass target) {
    if (isEmpty) return 0;
    final index = target.index;
    var hits = 0;
    for (final value in classes) {
      if (value == index) hits++;
    }
    return hits / classes.length;
  }

  bool isClassAt(double nx, double ny, FaceParsingClass target) {
    return classAtNormalized(nx, ny) == target;
  }
}

/// Origem da máscara — determina fallback quando confiança baixa.
enum FaceParsingSource {
  bisenet,
  mappedMulticlass,
  geometric,
}
