import 'dart:math' as math;

import 'package:editaiapp/features/editor/beauty_engine/warp/v2/ridge_weight.dart';
import 'package:flutter_test/flutter_test.dart';

/// Implementação anterior, que tomava o peso só do segmento mais próximo. Serve
/// de linha de base: é o degrau que se quer eliminar.
double _nearestSegmentOnly(
  List<RidgeNode> nodes,
  double x,
  double y,
  double sigma,
) {
  var bestD2 = double.infinity;
  var bestW = 0.0;
  for (var i = 0; i < nodes.length - 1; i++) {
    final a = nodes[i];
    final b = nodes[i + 1];
    final abx = b.p.dx - a.p.dx;
    final aby = b.p.dy - a.p.dy;
    final len2 = abx * abx + aby * aby;
    var t = 0.0;
    if (len2 > 1e-12) {
      t = (((x - a.p.dx) * abx + (y - a.p.dy) * aby) / len2).clamp(0.0, 1.0);
    }
    final qx = a.p.dx + abx * t;
    final qy = a.p.dy + aby * t;
    final d2 = (x - qx) * (x - qx) + (y - qy) * (y - qy);
    if (d2 < bestD2) {
      bestD2 = d2;
      bestW = a.weight + (b.weight - a.weight) * t;
    }
  }
  final g = bestW * math.exp(-bestD2 / (2 * sigma * sigma));
  return g > 1 ? 1 : g;
}

/// Centro do arco da fixture: é por aqui que passa a medial axis.
const _arcCenter = Offset(200, 300);

/// Crista curva com pesos decrescentes, como as da mandíbula.
///
/// O raio tem de ser da ordem do sopro (`sigmaAcross`), senão a medial axis cai
/// onde o peso já é desprezável e o degrau não se manifesta — foi o que
/// acontece na crista da testa, e é porque só o queixo invertia.
List<RidgeNode> _curvedRidge({double radius = 45}) {
  final anchors = <RidgeNode>[];
  for (var i = 0; i < 7; i++) {
    final angle = -math.pi / 2 + i * 0.22;
    anchors.add((
      p: Offset(
        _arcCenter.dx + radius * math.cos(angle),
        _arcCenter.dy + radius * math.sin(angle),
      ),
      weight: 1.0 - i * 0.14,
    ));
  }
  return RidgeWeight.densify(anchors);
}

void main() {
  group('RidgeWeight.densify', () {
    test('insere o ponto médio entre âncoras, em posição e peso', () {
      final out = RidgeWeight.densify([
        (p: const Offset(0, 0), weight: 1.0),
        (p: const Offset(10, 20), weight: 0.5),
      ]);
      expect(out.length, 3);
      expect(out[1].p, const Offset(5, 10));
      expect(out[1].weight, closeTo(0.75, 1e-9));
    });

    test('devolve a lista intacta com menos de duas âncoras', () {
      final single = [(p: const Offset(1, 2), weight: 0.5)];
      expect(RidgeWeight.densify(single), same(single));
      expect(RidgeWeight.densify(const []), isEmpty);
    });
  });

  group('RidgeWeight.at', () {
    test('vale o peso da âncora sobre a crista', () {
      final nodes = RidgeWeight.densify([
        (p: const Offset(0, 0), weight: 1.0),
        (p: const Offset(100, 0), weight: 0.5),
      ]);
      final onAnchor = RidgeWeight.at(
        ridge: Ridge.of(nodes),
        x: 0,
        y: 0,
        sigmaAcross: 30,
        blendPx: 4,
      );
      expect(onAnchor, closeTo(1.0, 0.02));
    });

    test('decai com a distância perpendicular', () {
      final nodes = RidgeWeight.densify([
        (p: const Offset(0, 0), weight: 1.0),
        (p: const Offset(100, 0), weight: 1.0),
      ]);
      double at(double y) => RidgeWeight.at(
            ridge: Ridge.of(nodes),
            x: 50,
            y: y,
            sigmaAcross: 30,
            blendPx: 4,
          );
      expect(at(0), closeTo(1.0, 1e-6));
      expect(at(30), closeTo(math.exp(-0.5), 0.01));
      expect(at(90), lessThan(0.02));
    });

    test('crista vazia ou sigma nulo dá zero', () {
      expect(
        RidgeWeight.at(
          ridge: Ridge.of(const []),
          x: 0,
          y: 0,
          sigmaAcross: 10,
          blendPx: 4,
        ),
        0,
      );
      expect(
        RidgeWeight.at(
          ridge: Ridge.of([(p: const Offset(0, 0), weight: 1.0)]),
          x: 0,
          y: 0,
          sigmaAcross: 0,
          blendPx: 4,
        ),
        0,
      );
    });

    test('não passa de 1 mesmo com pesos saturados', () {
      final nodes = RidgeWeight.densify([
        (p: const Offset(0, 0), weight: 2.0),
        (p: const Offset(50, 0), weight: 2.0),
      ]);
      expect(
        RidgeWeight.at(
          ridge: Ridge.of(nodes),
          x: 25,
          y: 0,
          sigmaAcross: 30,
          blendPx: 4,
        ),
        1.0,
      );
    });

    test('elimina o degrau da medial axis que o argmin deixava', () {
      final nodes = _curvedRidge();
      const sigma = 40.0;
      const blend = 4.0;

      var worstLegacy = 0.0;
      var worstNew = 0.0;
      // Varre o lado concavo, onde as perpendiculares dos segmentos se cruzam.
      for (var y = 260; y <= 340; y++) {
        double? prevLegacy;
        double? prevNew;
        for (var x = 160; x <= 240; x++) {
          final legacy = _nearestSegmentOnly(nodes, x + 0.5, y + 0.5, sigma);
          final now = RidgeWeight.at(
            ridge: Ridge.of(nodes),
            x: x + 0.5,
            y: y + 0.5,
            sigmaAcross: sigma,
            blendPx: blend,
          );
          if (prevLegacy != null) {
            worstLegacy = math.max(worstLegacy, (legacy - prevLegacy).abs());
            worstNew = math.max(worstNew, (now - prevNew!).abs());
          }
          prevLegacy = legacy;
          prevNew = now;
        }
      }

      expect(
        worstLegacy,
        greaterThan(0.02),
        reason: 'a fixture deixou de exercer o degrau que se quer eliminar',
      );
      expect(
        worstNew,
        lessThan(worstLegacy * 0.5),
        reason: 'a troca de segmento continua a dar degrau no peso',
      );
    });

    test('preserva o pico e desvia pouco da versão anterior', () {
      // Raio bem acima do sopro, como nas cristas reais: a medial axis fica
      // onde o peso já é residual, e portanto a comparação mede o corpo da
      // crista, não a zona degenerada que o teste anterior cobre.
      final nodes = _curvedRidge(radius: 100);
      const sigma = 40.0;
      const blend = 4.0;

      var peakLegacy = 0.0;
      var peakNew = 0.0;
      var worstDiff = 0.0;
      for (var y = 200; y <= 400; y++) {
        for (var x = 120; x <= 320; x++) {
          final legacy = _nearestSegmentOnly(nodes, x + 0.5, y + 0.5, sigma);
          final now = RidgeWeight.at(
            ridge: Ridge.of(nodes),
            x: x + 0.5,
            y: y + 0.5,
            sigmaAcross: sigma,
            blendPx: blend,
          );
          peakLegacy = math.max(peakLegacy, legacy);
          peakNew = math.max(peakNew, now);
          worstDiff = math.max(worstDiff, (now - legacy).abs());
        }
      }

      // Nas cristas do queixo, medidas em p01/p05/p06, a mesma comparação dá
      // 0,06% de perda de pico, 0,6% de desvio médio e 3,8% de desvio máximo.
      expect(peakNew, closeTo(peakLegacy, 0.01));
      expect(
        worstDiff,
        lessThan(0.06),
        reason: 'a crista contínua alterou o aspecto além do degrau',
      );
    });
  });

  group('RidgeWeight.stronger', () {
    test('dá o mesmo que avaliar as duas cristas', () {
      // Duas cristas afastadas, como os dois lados da cara: o corte por caixa
      // dispensa avaliar a distante, e o resultado tem de ser o mesmo — valor
      // e vencedor — em toda a parte, inclusive onde as duas se aproximam.
      final left = Ridge.of(RidgeWeight.densify([
        (p: const Offset(60, 100), weight: 0.4),
        (p: const Offset(100, 200), weight: 1.0),
        (p: const Offset(180, 260), weight: 0.7),
      ]));
      final right = Ridge.of(RidgeWeight.densify([
        (p: const Offset(420, 100), weight: 0.5),
        (p: const Offset(380, 200), weight: 0.9),
        (p: const Offset(300, 260), weight: 0.8),
      ]));
      const sigma = 45.0;
      const blend = 6.0;
      var worst = 0.0;
      var mismatches = 0;
      var cut = 0;
      for (var y = 0; y <= 360; y += 3) {
        for (var x = 0; x <= 480; x += 3) {
          final xc = x + 0.5;
          final yc = y + 0.5;
          final wL = RidgeWeight.at(
            ridge: left,
            x: xc,
            y: yc,
            sigmaAcross: sigma,
            blendPx: blend,
          );
          final wR = RidgeWeight.at(
            ridge: right,
            x: xc,
            y: yc,
            sigmaAcross: sigma,
            blendPx: blend,
          );
          final got = RidgeWeight.stronger(
            a: left,
            b: right,
            x: xc,
            y: yc,
            sigmaAcross: sigma,
            blendPx: blend,
          );
          worst = math.max(worst, (got.weight - math.max(wL, wR)).abs());
          if (got.aWins != (wL >= wR)) {
            mismatches++;
          }
          if (wL < 1e-12 || wR < 1e-12) {
            cut++;
          }
        }
      }
      expect(worst, 0);
      expect(mismatches, 0);
      // E há mesmo zonas onde um dos lados é irrelevante, senão o corte nunca
      // era exercido.
      expect(cut, greaterThan(0));
    });

    test('crista vazia de um lado não impede o outro', () {
      final only = Ridge.of(RidgeWeight.densify([
        (p: const Offset(0, 0), weight: 1.0),
        (p: const Offset(100, 0), weight: 1.0),
      ]));
      final empty = Ridge.of(const []);
      final got = RidgeWeight.stronger(
        a: empty,
        b: only,
        x: 50,
        y: 0,
        sigmaAcross: 30,
        blendPx: 4,
      );
      expect(got.weight, closeTo(1.0, 1e-9));
      expect(got.aWins, isFalse);
    });
  });
}
