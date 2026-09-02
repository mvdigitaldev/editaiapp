import 'dart:math' as math;
import 'dart:ui';

/// Nó de uma crista: posição em pixels e peso de influência.
typedef RidgeNode = ({Offset p, double weight});

/// Peso de crista por distância a uma polilinha, contínuo em todo o plano.
///
/// A distância à polilinha é contínua, mas tomar o peso interpolado **apenas do
/// segmento mais próximo** não é. Na medial axis da crista dois segmentos ficam
/// à mesma distância e as respectivas projecções caem em pontos de peso
/// diferente, pelo que o peso dá um degrau ao trocar de vencedor. É o mesmo
/// defeito de argmin discreto que tirou o `max(gaussianas)` da silhueta, só que
/// escondido um nível abaixo.
///
/// Medido no `v_chin` a t=1 (p01): o vencedor mudava de segmento entre x=390 e
/// x=391 e o peso saltava 0,8224 → 0,7420. Com amplitude de 30 px isso dava um
/// degrau de 1,4 px em `dx` num único pixel, ou seja `∂dx/∂x ≈ −1,4`, e como o
/// campo só tem componente horizontal, `detJ = 1 + ∂dx/∂x` ficava em −0,40: o
/// warp invertia.
///
/// Aqui o peso é a média dos segmentos ponderada por proximidade, com
/// [blendPx] a controlar a largura da transição. Longe da medial axis o
/// segmento mais próximo domina e o resultado é o de sempre; sobre ela a troca
/// distribui-se por alguns pixels em vez de acontecer num só. O decaimento
/// continua a usar a distância mínima, que já era contínua.
abstract final class RidgeWeight {
  RidgeWeight._();

  /// Densifica uma crista inserindo o ponto médio entre âncoras consecutivas.
  static List<RidgeNode> densify(List<RidgeNode> anchors) {
    if (anchors.length < 2) {
      return anchors;
    }
    final out = <RidgeNode>[];
    for (var i = 0; i < anchors.length; i++) {
      out.add(anchors[i]);
      if (i + 1 < anchors.length) {
        final a = anchors[i];
        final b = anchors[i + 1];
        out.add((
          p: Offset((a.p.dx + b.p.dx) * 0.5, (a.p.dy + b.p.dy) * 0.5),
          weight: (a.weight + b.weight) * 0.5,
        ));
      }
    }
    return out;
  }

  static double at({
    required List<RidgeNode> nodes,
    required double x,
    required double y,
    required double sigmaAcross,
    required double blendPx,
  }) {
    if (sigmaAcross < 1e-6 || nodes.isEmpty) {
      return 0;
    }
    if (nodes.length == 1) {
      final ddx = x - nodes.first.p.dx;
      final ddy = y - nodes.first.p.dy;
      final g = nodes.first.weight *
          math.exp(-(ddx * ddx + ddy * ddy) / (2 * sigmaAcross * sigmaAcross));
      return g > 1 ? 1 : g;
    }

    var minD2 = double.infinity;
    for (var i = 0; i < nodes.length - 1; i++) {
      final d2 = _distance2ToSegment(nodes[i].p, nodes[i + 1].p, x, y).d2;
      if (d2 < minD2) {
        minD2 = d2;
      }
    }

    final tau = math.max(blendPx, 1e-3);
    final minD = math.sqrt(minD2);
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < nodes.length - 1; i++) {
      final a = nodes[i];
      final b = nodes[i + 1];
      final hit = _distance2ToSegment(a.p, b.p, x, y);
      final excess = (math.sqrt(hit.d2) - minD) / tau;
      final k = math.exp(-0.5 * excess * excess);
      final s = hit.t * hit.t * (3 - 2 * hit.t);
      numerator += (a.weight + (b.weight - a.weight) * s) * k;
      denominator += k;
    }
    if (denominator <= 0) {
      return 0;
    }

    final g = (numerator / denominator) *
        math.exp(-minD2 / (2 * sigmaAcross * sigmaAcross));
    return g > 1 ? 1 : g;
  }

  static ({double d2, double t}) _distance2ToSegment(
    Offset a,
    Offset b,
    double x,
    double y,
  ) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final len2 = abx * abx + aby * aby;
    var t = 0.0;
    if (len2 > 1e-12) {
      t = (((x - a.dx) * abx + (y - a.dy) * aby) / len2).clamp(0.0, 1.0);
    }
    final qx = a.dx + abx * t;
    final qy = a.dy + aby * t;
    final dx = x - qx;
    final dy = y - qy;
    return (d2: dx * dx + dy * dy, t: t);
  }
}
