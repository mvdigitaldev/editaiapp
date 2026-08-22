import 'dart:typed_data';

/// Classes do modelo MediaPipe `selfie_multiclass_256x256`.
///
/// É a máscara semântica de fase 1 do SDK facial (cap. 1.2 do plano):
/// resolve pele/cabelo/fundo com custo quase zero de engenharia. O parsing
/// 19 classes (Sprint 4) vem do [FaceParsingMapper] + BiSeNet quando disponível.
/// A ordem de declaração é a ordem das classes do modelo — `index` do enum é
/// o próprio id da categoria devolvida pelo segmenter.
enum FacePartClass {
  background,
  hair,
  bodySkin,
  faceSkin,
  clothes,
  others;

  static FacePartClass fromIndex(int value) {
    if (value < 0 || value >= values.length) return FacePartClass.others;
    return values[value];
  }
}

/// Máscara de categorias por pixel devolvida pelo Image Segmenter nativo.
///
/// A resolução é a do modelo (256×256), não a da foto — a amostragem é
/// sempre normalizada.
class FacePartsSegmentation {
  const FacePartsSegmentation({
    required this.classes,
    required this.width,
    required this.height,
  });

  /// Um byte por pixel com o índice de [FacePartClass].
  final Uint8List classes;
  final int width;
  final int height;

  bool get isEmpty => width <= 0 || height <= 0 || classes.isEmpty;

  int classIndexAt(double nx, double ny) {
    if (isEmpty) return FacePartClass.others.index;
    final x = (nx * width).floor().clamp(0, width - 1);
    final y = (ny * height).floor().clamp(0, height - 1);
    return classes[y * width + x];
  }

  bool isClassAt(double nx, double ny, FacePartClass target) {
    return classIndexAt(nx, ny) == target.index;
  }

  /// Fração da imagem ocupada por [target] — usado para decidir se a
  /// segmentação é confiável antes de trocar a máscara geométrica por ela.
  double coverageOf(FacePartClass target) {
    if (isEmpty) return 0;
    var hits = 0;
    for (final value in classes) {
      if (value == target.index) hits++;
    }
    return hits / classes.length;
  }

  /// Contagem absoluta por classe MediaPipe. O modelo de 6 classes não tem ear.
  Map<String, int> pixelCounts() {
    final counts = {for (final c in FacePartClass.values) c.name: 0};
    if (isEmpty) {
      return counts;
    }
    for (final value in classes) {
      final name = FacePartClass.fromIndex(value).name;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }
}
