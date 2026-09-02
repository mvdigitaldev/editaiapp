import 'dart:math' as math;
import 'dart:typed_data';

import 'distance_transform.dart';

/// Rampa que leva o campo a zero na fronteira do domínio activo, sem o vinco da
/// medial axis. Só grid: sem RGBA, sem landmarks.
///
/// A rampa crua `min(1, dist / falloff)` herda a crista da transformada de
/// distância: na medial axis do domínio a distância tem um máximo interior e
/// `|grad dist|` vale 1 de cada lado com sinais opostos, logo o gradiente da
/// rampa salta `2 / falloff`. Quando `falloff` passa a distância da medial axis
/// a rampa nunca satura e o salto cai no meio da zona activa com peso alto: no
/// `v_shape` isso dava 0,69 px/px de salto em `dx` e imprimia na bochecha a
/// linha diagonal paralela à silhueta.
///
/// O borrão arredonda a medial axis e também o joelho da saturação, e por ser
/// uma média preserva o perfil e a amplitude da rampa.
abstract final class BoundaryFeather {
  BoundaryFeather._();

  /// Passagens de caixa que aproximam a gaussiana. Três chegam: o erro face à
  /// gaussiana fica abaixo de 3%, e o que importa aqui é só matar a segunda
  /// derivada.
  static const boxPasses = 3;

  /// Tecto do desvio do borrão em fracção de `falloffPx`. Um terço deixa o
  /// suporte (`3σ`) fechar dentro da rampa.
  static const _sigmaOfFalloff = 1 / 3;

  /// Rampa medida a partir da fronteira do domínio activo, onde [mask] é não
  /// nula.
  ///
  /// Devolve valores em `[0, 1]`: zero na fronteira e fora do domínio, um a
  /// [falloffPx] de distância para dentro.
  static Float32List insideActive({
    required Uint8List mask,
    required int width,
    required int height,
    required double falloffPx,
    required double sigmaPx,
  }) =>
      _build(
        dist: EuclideanDistanceTransform.toZeroOf(mask, width, height),
        width: width,
        height: height,
        falloffPx: falloffPx,
        sigmaPx: sigmaPx,
      );

  /// Rampa medida a partir da zona protegida, onde [mask] é não nula. Mesma
  /// rampa de [insideActive], para os campos que guardam o complemento.
  static Float32List awayFromInactive({
    required Uint8List mask,
    required int width,
    required int height,
    required double falloffPx,
    required double sigmaPx,
  }) =>
      _build(
        dist: EuclideanDistanceTransform.toNonZeroOf(mask, width, height),
        width: width,
        height: height,
        falloffPx: falloffPx,
        sigmaPx: sigmaPx,
      );

  static Float32List _build({
    required Float32List dist,
    required int width,
    required int height,
    required double falloffPx,
    required double sigmaPx,
  }) {
    final pixelCount = width * height;
    final ramp = Float32List(pixelCount);
    final inverse = falloffPx > 1e-6 ? 1.0 / falloffPx : 0.0;
    for (var i = 0; i < pixelCount; i++) {
      final r = dist[i] * inverse;
      ramp[i] = r >= 1.0 ? 1.0 : r;
    }
    // O borrão tem de caber na rampa. Quando o suporte passa `falloffPx` a
    // mistura ainda está aberta onde a rampa já saturou, devolve o cru em toda
    // a transição e não sobra ganho: era o que acontecia na rampa da orelha do
    // `cheekbone`, com `earFalloff` de 13 px contra 24 px de suporte.
    final capped = math.min(sigmaPx, falloffPx * _sigmaOfFalloff);
    if (capped < 0.5) {
      return ramp;
    }
    final radius = boxRadiusFor(capped);
    if (radius < 1) {
      return ramp;
    }
    final blurred = Float32List.fromList(ramp);
    final scratch = Float32List(pixelCount);
    for (var pass = 0; pass < boxPasses; pass++) {
      _boxHorizontal(blurred, scratch, width, height, radius);
      _boxVertical(scratch, blurred, width, height, radius);
    }

    // O borrão espalha peso para cima da fronteira e desfaz o zero que fazia o
    // campo casar com o exterior: usado sozinho, punha o `v_shape` a saltar
    // 1,3 px na borda do domínio e a inverter (`minDetJ` −0,20). Perto da
    // fronteira volta-se por isso à rampa crua, que lá vale exactamente zero.
    //
    // A troca é uma mistura e não uma porta multiplicativa: uma porta impõe a
    // sua própria escala, e como o suporte do borrão é bem menor que
    // `falloffPx` ela sai mais abrupta que a rampa — o `chin`, que já vivia no
    // limite, invertia (`minDetJ` −0,007 a t=−1). Na mistura o termo que a
    // transição acrescenta ao gradiente é apenas `g' × (borrado − cru)`, e a
    // diferença entre os dois é da ordem do borrão, logo fica desprezável.
    //
    // A mistura fecha dentro do suporte do borrão, muito antes da medial axis,
    // que assim continua a ser servida pelo borrado e não recupera o vinco.
    final edge = boxPasses * radius;
    final edgeInverse = 1.0 / edge;
    for (var i = 0; i < pixelCount; i++) {
      final s = dist[i] * edgeInverse;
      if (s >= 1.0) {
        ramp[i] = blurred[i];
        continue;
      }
      final g = s * s * (3 - 2 * s);
      ramp[i] += (blurred[i] - ramp[i]) * g;
    }
    return ramp;
  }

  /// Raio de caixa que, repetido [boxPasses] vezes, aproxima `sigmaPx`.
  static int boxRadiusFor(double sigmaPx) {
    final w = math.sqrt(12 * sigmaPx * sigmaPx / boxPasses + 1);
    return ((w - 1) * 0.5).round();
  }

  static void _boxHorizontal(
    Float32List src,
    Float32List dst,
    int width,
    int height,
    int radius,
  ) {
    final window = 2 * radius + 1;
    final norm = 1.0 / window;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      // Bordas replicadas: a rampa já vale zero fora do domínio, portanto
      // replicar não injecta peso onde o campo tem de ser nulo.
      var sum = src[row] * (radius + 1);
      for (var x = 1; x <= radius; x++) {
        sum += src[row + math.min(x, width - 1)];
      }
      for (var x = 0; x < width; x++) {
        dst[row + x] = sum * norm;
        final add = src[row + math.min(x + radius + 1, width - 1)];
        final drop = src[row + math.max(x - radius, 0)];
        sum += add - drop;
      }
    }
  }

  static void _boxVertical(
    Float32List src,
    Float32List dst,
    int width,
    int height,
    int radius,
  ) {
    final window = 2 * radius + 1;
    final norm = 1.0 / window;
    for (var x = 0; x < width; x++) {
      var sum = src[x] * (radius + 1);
      for (var y = 1; y <= radius; y++) {
        sum += src[math.min(y, height - 1) * width + x];
      }
      for (var y = 0; y < height; y++) {
        dst[y * width + x] = sum * norm;
        final add = src[math.min(y + radius + 1, height - 1) * width + x];
        final drop = src[math.max(y - radius, 0) * width + x];
        sum += add - drop;
      }
    }
  }
}
