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

  /// Desvio do alisamento da distância, em pixels de imagem.
  ///
  /// Fixo, e não em fracção da cara, porque o que corrige são os dentes da
  /// rasterização das máscaras, que medem um pixel qualquer que seja o tamanho
  /// da cara.
  static const rasterSigmaPx = 1.2;

  /// Valor médio da rampa `max(0, d)` alisada, medido na fronteira: para uma
  /// fronteira recta vale `σ/√(2π)`. Subtrair isto devolve o zero à fronteira.
  static const _rasterBias = rasterSigmaPx * 0.3989;

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
      _windowed(
        mask: mask,
        width: width,
        height: height,
        falloffPx: falloffPx,
        sigmaPx: sigmaPx,
        seedOnZero: true,
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
      _windowed(
        mask: mask,
        width: width,
        height: height,
        falloffPx: falloffPx,
        sigmaPx: sigmaPx,
        seedOnZero: false,
      );

  /// Constrói a rampa só na janela que a pode ter diferente de zero.
  ///
  /// Fora da região de interesse — os pixels que não são semente — a distância
  /// vale zero e a rampa com ela, portanto calcular a imagem inteira é
  /// trabalho perdido: no `chin` a região activa ocupa 6% dos pixels e a
  /// distância mais o borrão custavam 26 ms dos 90 ms do campo.
  ///
  /// O resultado é o mesmo, não uma aproximação. Todo o pixel fora da caixa da
  /// região de interesse é semente, logo qualquer pixel de interesse tem a sua
  /// semente mais próxima dentro dessa caixa dilatada de um: ou é uma semente
  /// interior, ou é a moldura imediata. A janela leva ainda o suporte dos dois
  /// borrões, para que a replicação de borda replique zeros — que é o que a
  /// imagem inteira teria lá.
  static Float32List _windowed({
    required Uint8List mask,
    required int width,
    required int height,
    required double falloffPx,
    required double sigmaPx,
    required bool seedOnZero,
  }) {
    final capped = math.min(sigmaPx, falloffPx * _sigmaOfFalloff);
    final margin = 1 +
        boxPasses * (boxRadiusFor(rasterSigmaPx) + boxRadiusFor(capped)) +
        1;
    final win = _interestWindow(mask, width, height, seedOnZero, margin);
    if (win == null) {
      return Float32List(width * height);
    }
    if (win.width == width && win.height == height) {
      return _build(
        dist: seedOnZero
            ? EuclideanDistanceTransform.toZeroOf(mask, width, height)
            : EuclideanDistanceTransform.toNonZeroOf(mask, width, height),
        width: width,
        height: height,
        falloffPx: falloffPx,
        sigmaPx: sigmaPx,
      );
    }

    final sub = Uint8List(win.width * win.height);
    for (var y = 0; y < win.height; y++) {
      final from = (win.top + y) * width + win.left;
      sub.setRange(y * win.width, (y + 1) * win.width, mask, from);
    }
    final subRamp = _build(
      dist: seedOnZero
          ? EuclideanDistanceTransform.toZeroOf(sub, win.width, win.height)
          : EuclideanDistanceTransform.toNonZeroOf(sub, win.width, win.height),
      width: win.width,
      height: win.height,
      falloffPx: falloffPx,
      sigmaPx: sigmaPx,
    );
    final out = Float32List(width * height);
    for (var y = 0; y < win.height; y++) {
      final to = (win.top + y) * width + win.left;
      out.setRange(to, to + win.width, subRamp, y * win.width);
    }
    return out;
  }

  /// Caixa dos pixels que não são semente, dilatada de [margin] e recortada à
  /// imagem. `null` se toda a máscara for semente.
  static ({int left, int top, int width, int height})? _interestWindow(
    Uint8List mask,
    int width,
    int height,
    bool seedOnZero,
    int margin,
  ) {
    var left = width;
    var top = height;
    var right = -1;
    var bottom = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final isSeed = seedOnZero ? mask[row + x] == 0 : mask[row + x] != 0;
        if (isSeed) {
          continue;
        }
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        bottom = y;
      }
    }
    if (right < 0) {
      return null;
    }
    final l = math.max(0, left - margin);
    final t = math.max(0, top - margin);
    final r = math.min(width - 1, right + margin);
    final b = math.min(height - 1, bottom + margin);
    return (left: l, top: t, width: r - l + 1, height: b - t + 1);
  }

  static Float32List _build({
    required Float32List dist,
    required int width,
    required int height,
    required double falloffPx,
    required double sigmaPx,
  }) {
    final pixelCount = width * height;
    _smoothRaster(dist, width, height);
    // A rampa é um smoothstep e não `d / falloff`: a rampa linear arranca com
    // derivada `1 / falloff`, portanto o primeiro pixel dentro do domínio já
    // vale um passo inteiro. Como a fronteira é a rasterização de uma máscara
    // binária, esse passo corre em degraus de um pixel ao longo dela — no
    // `v_shape` o campo entrava a 0,23 px de golpe, e na borda pele/cabelo, com
    // contraste máximo, lia-se como serrilhado. O smoothstep tem derivada nula
    // nas duas pontas, logo o campo arranca do zero sem passo e fecha na
    // saturação sem joelho, ao preço de 1,5× no gradiente ao meio da rampa —
    // que continua muito abaixo de 1 e por isso não ameaça `detJ`.
    final ramp = Float32List(pixelCount);
    final inverse = falloffPx > 1e-6 ? 1.0 / falloffPx : 0.0;
    for (var i = 0; i < pixelCount; i++) {
      final r = dist[i] * inverse;
      ramp[i] = r >= 1.0 ? 1.0 : r * r * (3 - 2 * r);
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

  /// Alisa [dist] no lugar para apagar os dentes da rasterização das máscaras.
  ///
  /// As máscaras são binárias e desenhadas a pixel cheio, portanto a fronteira
  /// do domínio serrilha, e a distância exacta a uma fronteira serrilhada
  /// oscila meio pixel de linha para linha. Junto à fronteira a mistura deste
  /// ficheiro devolve a rampa crua, que herda essa oscilação: no `v_shape`
  /// media 0,23 px de vaivém entre pixels vizinhos, e na borda pele/cabelo,
  /// onde o contraste é máximo, isso lê-se como serrilhado.
  ///
  /// O borrão apaga a oscilação, que corre ao longo da fronteira, mas também
  /// levanta a rampa acima do zero na travessia. Por isso desconta-se
  /// [_rasterBias] e corta-se em zero: a fronteira efectiva passa a ser a
  /// curva de nível de uma função já alisada, lisa ao longo dela, e o campo
  /// volta a casar com o exterior parado.
  static void _smoothRaster(Float32List dist, int width, int height) {
    final radius = boxRadiusFor(rasterSigmaPx);
    if (radius < 1) {
      return;
    }
    // Quem está fora do domínio tem de lá ficar: o borrão espalha distância
    // para fora e sem esta guarda a rampa deixava de valer zero no exterior,
    // que é o que faz o campo casar com a parte parada da imagem.
    final outside = Uint8List(dist.length);
    for (var i = 0; i < dist.length; i++) {
      if (dist[i] <= 0) {
        outside[i] = 1;
      }
    }
    final scratch = Float32List(dist.length);
    for (var pass = 0; pass < boxPasses; pass++) {
      _boxHorizontal(dist, scratch, width, height, radius);
      _boxVertical(scratch, dist, width, height, radius);
    }
    for (var i = 0; i < dist.length; i++) {
      final d = outside[i] != 0 ? 0.0 : dist[i] - _rasterBias;
      dist[i] = d > 0 ? d : 0;
    }
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
