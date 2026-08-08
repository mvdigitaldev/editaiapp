import 'dart:math' as math;
import 'dart:typed_data';

/// Retrato sintético determinístico: fundo em gradiente com listras, elipse
/// em tom de pele (rosto), faixa escura (cabelo) e detalhes de alta
/// frequência na "pele" para denunciar borrões/deslocamentos.
///
/// A geometria coincide com o rosto de `skin_face_fixture.dart`, então os
/// testes de pele podem afirmar o que deve e o que não deve ser tocado.
Uint8List syntheticPortrait(int width, int height) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final nx = x / (width - 1);
      final ny = y / (height - 1);
      final i = (y * width + x) * 4;

      // Fundo: gradiente + listras verticais.
      var r = 40 + (nx * 60).round();
      var g = 60 + (ny * 80).round();
      var b = 110;
      if ((x ~/ 12).isEven) {
        r += 25;
        g += 25;
        b += 25;
      }

      // Rosto: elipse central em tom de pele com textura de "poros".
      final faceDist =
          math.pow((nx - 0.5) / 0.24, 2) + math.pow((ny - 0.42) / 0.30, 2);
      if (faceDist <= 1) {
        final texture = ((x * 7 + y * 13) % 17 == 0) ? -18 : 0;
        r = 224 + texture;
        g = 172 + texture;
        b = 148 + texture;
        // Olhos: dois pontos escuros.
        final leftEye =
            math.pow((nx - 0.42) / 0.03, 2) + math.pow((ny - 0.36) / 0.02, 2);
        final rightEye =
            math.pow((nx - 0.58) / 0.03, 2) + math.pow((ny - 0.36) / 0.02, 2);
        if (leftEye <= 1 || rightEye <= 1) {
          r = 50;
          g = 40;
          b = 35;
        }
        // Boca: faixa avermelhada.
        final mouth =
            math.pow((nx - 0.5) / 0.08, 2) + math.pow((ny - 0.56) / 0.015, 2);
        if (mouth <= 1) {
          r = 190;
          g = 90;
          b = 90;
        }
      }

      // Cabelo: calota acima do rosto.
      final hairDist =
          math.pow((nx - 0.5) / 0.28, 2) + math.pow((ny - 0.30) / 0.26, 2);
      if (hairDist <= 1 && ny < 0.26) {
        r = 55;
        g = 40;
        b = 30;
      }

      rgba[i] = r.clamp(0, 255);
      rgba[i + 1] = g.clamp(0, 255);
      rgba[i + 2] = b.clamp(0, 255);
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}
