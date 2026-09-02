import 'dart:math' as math;
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/warp/v2/boundary_feather.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faixa vertical activa de [stripe] px de largura, centrada em [width] / 2.
/// Reproduz o domínio estreito onde a medial axis cai a meio da zona activa.
Uint8List _stripe(int width, int height, int stripe) {
  final mask = Uint8List(width * height);
  final from = (width - stripe) ~/ 2;
  final to = from + stripe;
  for (var y = 0; y < height; y++) {
    for (var x = from; x < to; x++) {
      mask[y * width + x] = 255;
    }
  }
  return mask;
}

double _worstSecondDifference(
  Float32List v,
  int width,
  int y, {
  required int from,
  required int to,
}) {
  var worst = 0.0;
  for (var x = from + 1; x < to - 1; x++) {
    final i = y * width + x;
    worst = math.max(worst, (v[i + 1] - 2 * v[i] + v[i - 1]).abs());
  }
  return worst;
}

void main() {
  group('BoundaryFeather', () {
    const width = 160;
    const height = 40;

    test('vale zero fora do domínio e na fronteira', () {
      const stripe = 60;
      final mask = _stripe(width, height, stripe);
      final ramp = BoundaryFeather.insideActive(
        mask: mask,
        width: width,
        height: height,
        falloffPx: 20,
        sigmaPx: 5,
      );
      final from = (width - stripe) ~/ 2;
      final row = height ~/ 2;
      expect(ramp[row * width + from - 1], 0);
      expect(ramp[row * width + 5], 0);
      // O primeiro pixel activo está a meio pixel da fronteira, logo a rampa
      // ainda tem de ser desprezável face ao seu alcance.
      expect(ramp[row * width + from], lessThan(0.1));
    });

    test('satura em um a partir do falloff', () {
      final mask = _stripe(width, height, 100);
      final ramp = BoundaryFeather.insideActive(
        mask: mask,
        width: width,
        height: height,
        falloffPx: 12,
        sigmaPx: 3,
      );
      expect(ramp[(height ~/ 2) * width + width ~/ 2], closeTo(1, 1e-3));
    });

    test('fica sempre em [0, 1]', () {
      final mask = _stripe(width, height, 44);
      final ramp = BoundaryFeather.insideActive(
        mask: mask,
        width: width,
        height: height,
        falloffPx: 30,
        sigmaPx: 6,
      );
      for (final v in ramp) {
        expect(v, inInclusiveRange(0, 1));
      }
    });

    test('mata o vinco da medial axis que a rampa crua deixa', () {
      // Faixa de 60 px com falloff de 40: a rampa nunca satura e o máximo da
      // distância cai a 30 px da fronteira, a meio da zona activa.
      const stripe = 60;
      final mask = _stripe(width, height, stripe);
      final from = (width - stripe) ~/ 2;
      final row = height ~/ 2;

      final raw = BoundaryFeather.insideActive(
        mask: mask,
        width: width,
        height: height,
        falloffPx: 40,
        sigmaPx: 0,
      );
      final smooth = BoundaryFeather.insideActive(
        mask: mask,
        width: width,
        height: height,
        falloffPx: 40,
        sigmaPx: 8,
      );

      final rawWorst = _worstSecondDifference(
        raw,
        width,
        row,
        from: from,
        to: from + stripe,
      );
      final smoothWorst = _worstSecondDifference(
        smooth,
        width,
        row,
        from: from,
        to: from + stripe,
      );
      // Com a largura par o vértice cai entre dois pixels e o salto reparte-se,
      // pelo que a rampa crua marca `1 / falloff` e não `2 / falloff`.
      expect(rawWorst, greaterThan(0.02));
      expect(smoothWorst, lessThan(rawWorst / 4));
    });

    test('preserva o perfil da rampa', () {
      const stripe = 120;
      final mask = _stripe(width, height, stripe);
      final from = (width - stripe) ~/ 2;
      final row = height ~/ 2;
      final raw = BoundaryFeather.insideActive(
        mask: mask,
        width: width,
        height: height,
        falloffPx: 30,
        sigmaPx: 0,
      );
      final smooth = BoundaryFeather.insideActive(
        mask: mask,
        width: width,
        height: height,
        falloffPx: 30,
        sigmaPx: 6,
      );
      var worst = 0.0;
      for (var x = from; x < from + stripe; x++) {
        final i = row * width + x;
        worst = math.max(worst, (smooth[i] - raw[i]).abs());
      }
      // O desvio concentra-se no joelho da saturação, que o borrão arredonda, e
      // vale por isso da ordem de `σ / falloff`.
      expect(worst, lessThan(0.6 * 6 / 30));
    });

    test('o gradiente não passa o da rampa crua', () {
      // O borrão não pode apertar a rampa: foi uma porta multiplicativa a
      // fazê-lo que punha o `chin` a inverter.
      const stripe = 120;
      final mask = _stripe(width, height, stripe);
      final from = (width - stripe) ~/ 2;
      final row = height ~/ 2;
      const falloff = 30.0;
      final smooth = BoundaryFeather.insideActive(
        mask: mask,
        width: width,
        height: height,
        falloffPx: falloff,
        sigmaPx: 6,
      );
      var worst = 0.0;
      for (var x = from; x < from + stripe - 1; x++) {
        final i = row * width + x;
        worst = math.max(worst, (smooth[i + 1] - smooth[i]).abs());
      }
      // Arredondar o joelho obriga a rampa a subir um pouco mais depressa
      // antes de saturar; o excesso mede-se em poucos por cento e é o que
      // separa esta mistura de uma porta multiplicativa, que apertava a rampa
      // pelo factor 1,5 do smoothstep.
      expect(worst, lessThanOrEqualTo(1.06 / falloff));
    });

    test('limita o borrão ao falloff', () {
      // Com o suporte do borrão acima do falloff a mistura ficava aberta onde a
      // rampa já saturou e devolvia o cru em toda a transição.
      const stripe = 120;
      final mask = _stripe(width, height, stripe);
      final row = height ~/ 2;
      final capped = BoundaryFeather.insideActive(
        mask: mask,
        width: width,
        height: height,
        falloffPx: 9,
        sigmaPx: 40,
      );
      // Continua a saturar: um borrão sem tecto arrastaria o perfil todo.
      expect(capped[row * width + width ~/ 2], closeTo(1, 1e-3));
    });

    test('awayFromInactive mede a partir da zona protegida', () {
      // Complemento de [insideActive]: a semente é o que está marcado.
      final protected = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < 20; x++) {
          protected[y * width + x] = 255;
        }
      }
      final ramp = BoundaryFeather.awayFromInactive(
        mask: protected,
        width: width,
        height: height,
        falloffPx: 20,
        sigmaPx: 4,
      );
      final row = height ~/ 2;
      expect(ramp[row * width + 10], 0);
      expect(ramp[row * width + width - 1], closeTo(1, 1e-3));
    });

    test('boxRadiusFor cresce com o desvio', () {
      expect(BoundaryFeather.boxRadiusFor(0.2), 0);
      expect(BoundaryFeather.boxRadiusFor(8), greaterThan(5));
      expect(
        BoundaryFeather.boxRadiusFor(16),
        greaterThan(BoundaryFeather.boxRadiusFor(8)),
      );
    });

    test('rejeita máscara com tamanho errado', () {
      expect(
        () => BoundaryFeather.insideActive(
          mask: Uint8List(10),
          width: width,
          height: height,
          falloffPx: 10,
          sigmaPx: 3,
        ),
        throwsArgumentError,
      );
    });
  });
}
