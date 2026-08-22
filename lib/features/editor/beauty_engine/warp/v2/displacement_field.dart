import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Campo de deslocamento por pixel da imagem lab (V2.0).
///
/// Um par `(dx, dy)` por pixel, índice `y * width + x`. Não interpola o
/// campo. Não armazena nem lê RGBA.
///
/// Layout: `dx`/`dy` separados (como o buffer denso 2D da V1), sem `roi`,
/// `domain` nem qualquer tipo V1.
///
/// `dart:ui` entra só por [Offset] em [displacementAt], o mesmo tipo 2D já
/// usado em `FaceLandmark.normalized`. Não importa widgets. Reavaliar se o
/// núcleo V2 precisar de um vetor próprio (ver relatório do marco 1).
class DisplacementField {
  DisplacementField({
    required this.width,
    required this.height,
    Float32List? dx,
    Float32List? dy,
  })  : dx = dx ?? Float32List(width * height),
        dy = dy ?? Float32List(width * height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('displacement_field_invalid_size: ${width}x$height');
    }
    final expected = width * height;
    if (this.dx.length != expected || this.dy.length != expected) {
      throw StateError(
        'displacement_field_size_mismatch: got dx=${this.dx.length} '
        'dy=${this.dy.length}, expected $expected',
      );
    }
  }

  factory DisplacementField.zeros({
    required int width,
    required int height,
  }) {
    return DisplacementField(width: width, height: height);
  }

  /// Campo uniforme de translação. **Apenas testes sintéticos / laboratório**
  /// (identity, translação inteira, OOB). Não faz parte do pipeline real de
  /// deformação facial — o campo de produto virá do construtor jaw (V2.1).
  factory DisplacementField.translation({
    required int width,
    required int height,
    required double dx,
    required double dy,
  }) {
    final field = DisplacementField(width: width, height: height);
    if (dx == 0 && dy == 0) {
      return field;
    }
    field.dx.fillRange(0, field.pixelCount, dx);
    field.dy.fillRange(0, field.pixelCount, dy);
    return field;
  }

  final int width;
  final int height;
  final Float32List dx;
  final Float32List dy;

  int get pixelCount => width * height;

  int indexOf(int x, int y) => y * width + x;

  Offset displacementAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      throw RangeError(
        'displacement_field_out_of_range: ($x,$y) size ${width}x$height',
      );
    }
    final i = indexOf(x, y);
    return Offset(dx[i], dy[i]);
  }

  bool get isZero {
    for (var i = 0; i < dx.length; i++) {
      if (dx[i] != 0 || dy[i] != 0) {
        return false;
      }
    }
    return true;
  }
}
