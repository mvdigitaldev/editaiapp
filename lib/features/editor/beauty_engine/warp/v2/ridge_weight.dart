import 'dart:math' as math;
import 'dart:typed_data';
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
/// Crista com os segmentos em vectores planos, preparada uma vez por efeito.
///
/// O peso é avaliado em cada pixel activo de cada efeito — dezenas de milhares
/// por campo, seis campos por cadeia — e a versão que percorria a lista de nós
/// pagava por pixel a indirecção de dois objectos `Offset` por segmento e uma
/// divisão pelo comprimento. Aqui isso é feito uma vez.
///
/// A caixa e o peso máximo servem para descartar uma crista inteira sem a
/// percorrer: a distância a qualquer ponto dela nunca é menor que a distância à
/// sua caixa, e a média ponderada nunca passa o maior peso dos nós, logo
/// `maxWeight · exp(−distCaixa² / 2σ²)` limita o peso por cima.
class Ridge {
  Ridge._({
    required this.segments,
    required this.maxWeight,
    required Float64List ax,
    required Float64List ay,
    required Float64List abx,
    required Float64List aby,
    required Float64List len2,
    required Float64List wa,
    required Float64List wb,
    required double left,
    required double top,
    required double right,
    required double bottom,
    required this.single,
  })  : _ax = ax,
        _ay = ay,
        _abx = abx,
        _aby = aby,
        _len2 = len2,
        _wa = wa,
        _wb = wb,
        _left = left,
        _top = top,
        _right = right,
        _bottom = bottom;

  factory Ridge.of(List<RidgeNode> nodes) {
    if (nodes.isEmpty) {
      return Ridge._empty;
    }
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    var maxWeight = 0.0;
    for (final n in nodes) {
      if (n.p.dx < left) left = n.p.dx;
      if (n.p.dx > right) right = n.p.dx;
      if (n.p.dy < top) top = n.p.dy;
      if (n.p.dy > bottom) bottom = n.p.dy;
      if (n.weight > maxWeight) maxWeight = n.weight;
    }
    if (nodes.length == 1) {
      return Ridge._(
        segments: 0,
        maxWeight: maxWeight,
        ax: Float64List(0),
        ay: Float64List(0),
        abx: Float64List(0),
        aby: Float64List(0),
        len2: Float64List(0),
        wa: Float64List(0),
        wb: Float64List(0),
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        single: nodes.first,
      );
    }
    final count = nodes.length - 1;
    final ax = Float64List(count);
    final ay = Float64List(count);
    final abx = Float64List(count);
    final aby = Float64List(count);
    final len2 = Float64List(count);
    final wa = Float64List(count);
    final wb = Float64List(count);
    for (var i = 0; i < count; i++) {
      final a = nodes[i];
      final b = nodes[i + 1];
      ax[i] = a.p.dx;
      ay[i] = a.p.dy;
      final dx = b.p.dx - a.p.dx;
      final dy = b.p.dy - a.p.dy;
      abx[i] = dx;
      aby[i] = dy;
      len2[i] = dx * dx + dy * dy;
      wa[i] = a.weight;
      wb[i] = b.weight;
    }
    return Ridge._(
      segments: count,
      maxWeight: maxWeight,
      ax: ax,
      ay: ay,
      abx: abx,
      aby: aby,
      len2: len2,
      wa: wa,
      wb: wb,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      single: null,
    );
  }

  static final Ridge _empty = Ridge._(
    segments: 0,
    maxWeight: 0,
    ax: Float64List(0),
    ay: Float64List(0),
    abx: Float64List(0),
    aby: Float64List(0),
    len2: Float64List(0),
    wa: Float64List(0),
    wb: Float64List(0),
    left: 0,
    top: 0,
    right: 0,
    bottom: 0,
    single: null,
  );

  final int segments;
  final double maxWeight;
  final Float64List _ax;
  final Float64List _ay;
  final Float64List _abx;
  final Float64List _aby;
  final Float64List _len2;
  final Float64List _wa;
  final Float64List _wb;
  final double _left;
  final double _top;
  final double _right;
  final double _bottom;

  /// Crista de um só nó, que decai como uma gaussiana isotrópica.
  final RidgeNode? single;

  bool get isEmpty => segments == 0 && single == null;

  /// Quadrado da distância do ponto à caixa da crista. Zero lá dentro.
  double _boxDistance2(double x, double y) {
    final dx = x < _left
        ? _left - x
        : x > _right
            ? x - _right
            : 0.0;
    final dy = y < _top
        ? _top - y
        : y > _bottom
            ? y - _bottom
            : 0.0;
    return dx * dx + dy * dy;
  }
}

abstract final class RidgeWeight {
  RidgeWeight._();

  /// Distâncias e parâmetros da projecção da chamada em curso. Crescem com a
  /// crista mais longa vista e ficam; são lidos e escritos dentro de [at] e
  /// [project], sem atravessar chamadas.
  static Float64List _projected = Float64List(0);
  static Float64List _alongSegment = Float64List(0);
  static Float64List _projX = Float64List(0);
  static Float64List _projY = Float64List(0);

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
    required Ridge ridge,
    required double x,
    required double y,
    required double sigmaAcross,
    required double blendPx,
  }) {
    if (sigmaAcross < 1e-6 || ridge.isEmpty) {
      return 0;
    }
    final lone = ridge.single;
    if (lone != null) {
      final ddx = x - lone.p.dx;
      final ddy = y - lone.p.dy;
      final g = lone.weight *
          math.exp(-(ddx * ddx + ddy * ddy) / (2 * sigmaAcross * sigmaAcross));
      return g > 1 ? 1 : g;
    }

    // A projecção de cada segmento serve duas vezes — para o mínimo e para a
    // média — e é chamada por pixel activo de seis efeitos. Guardá-la poupa
    // metade das projecções e a alocação de um registo por segmento.
    final segments = ridge.segments;
    if (_projected.length < segments) {
      _projected = Float64List(segments);
      _alongSegment = Float64List(segments);
    }
    var minD2 = double.infinity;
    for (var i = 0; i < segments; i++) {
      final abx = ridge._abx[i];
      final aby = ridge._aby[i];
      final len2 = ridge._len2[i];
      final ox = x - ridge._ax[i];
      final oy = y - ridge._ay[i];
      var t = 0.0;
      if (len2 > 1e-12) {
        t = ((ox * abx + oy * aby) / len2).clamp(0.0, 1.0);
      }
      // Mesma ordem de operações da versão que percorria os nós, para o
      // resultado não mudar nem no último bit.
      final px = x - (ridge._ax[i] + abx * t);
      final py = y - (ridge._ay[i] + aby * t);
      final d2 = px * px + py * py;
      _projected[i] = d2;
      _alongSegment[i] = t;
      if (d2 < minD2) {
        minD2 = d2;
      }
    }

    final tau = math.max(blendPx, 1e-3);
    final minD = math.sqrt(minD2);
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < segments; i++) {
      final t = _alongSegment[i];
      final excess = (math.sqrt(_projected[i]) - minD) / tau;
      final k = math.exp(-0.5 * excess * excess);
      final s = t * t * (3 - 2 * t);
      final wa = ridge._wa[i];
      numerator += (wa + (ridge._wb[i] - wa) * s) * k;
      denominator += k;
    }
    if (denominator <= 0) {
      return 0;
    }

    final g = (numerator / denominator) *
        math.exp(-minD2 / (2 * sigmaAcross * sigmaAcross));
    return g > 1 ? 1 : g;
  }

  /// Projecção contínua na polilinha: ponto mais perto (média na medial axis)
  /// e peso ao longo da crista. **Sem** decaimento transversal — quem precisa
  /// de sopro chama [at].
  static ({double qx, double qy, double alongWeight, double dist2}) project({
    required Ridge ridge,
    required double x,
    required double y,
    required double blendPx,
  }) {
    if (ridge.isEmpty) {
      return (qx: x, qy: y, alongWeight: 0, dist2: 0);
    }
    final lone = ridge.single;
    if (lone != null) {
      final dx = x - lone.p.dx;
      final dy = y - lone.p.dy;
      return (
        qx: lone.p.dx,
        qy: lone.p.dy,
        alongWeight: lone.weight,
        dist2: dx * dx + dy * dy,
      );
    }

    final segments = ridge.segments;
    if (_projected.length < segments) {
      _projected = Float64List(segments);
      _alongSegment = Float64List(segments);
    }
    if (_projX.length < segments) {
      _projX = Float64List(segments);
      _projY = Float64List(segments);
    }
    var minD2 = double.infinity;
    for (var i = 0; i < segments; i++) {
      final abx = ridge._abx[i];
      final aby = ridge._aby[i];
      final len2 = ridge._len2[i];
      final ox = x - ridge._ax[i];
      final oy = y - ridge._ay[i];
      var t = 0.0;
      if (len2 > 1e-12) {
        t = ((ox * abx + oy * aby) / len2).clamp(0.0, 1.0);
      }
      final qx = ridge._ax[i] + abx * t;
      final qy = ridge._ay[i] + aby * t;
      final px = x - qx;
      final py = y - qy;
      final d2 = px * px + py * py;
      _projected[i] = d2;
      _alongSegment[i] = t;
      _projX[i] = qx;
      _projY[i] = qy;
      if (d2 < minD2) {
        minD2 = d2;
      }
    }

    final tau = math.max(blendPx, 1e-3);
    final minD = math.sqrt(minD2);
    var numX = 0.0;
    var numY = 0.0;
    var numW = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < segments; i++) {
      final t = _alongSegment[i];
      final excess = (math.sqrt(_projected[i]) - minD) / tau;
      final k = math.exp(-0.5 * excess * excess);
      final s = t * t * (3 - 2 * t);
      final wa = ridge._wa[i];
      numX += _projX[i] * k;
      numY += _projY[i] * k;
      numW += (wa + (ridge._wb[i] - wa) * s) * k;
      denominator += k;
    }
    if (denominator <= 0) {
      return (qx: x, qy: y, alongWeight: 0, dist2: minD2);
    }
    return (
      qx: numX / denominator,
      qy: numY / denominator,
      alongWeight: numW / denominator,
      dist2: minD2,
    );
  }

  /// A mais forte de duas cristas, sem avaliar a que não pode ganhar.
  ///
  /// Os efeitos são bilaterais: tomam o maior peso entre o lado esquerdo e o
  /// direito, e alguns precisam de saber qual venceu. Mas na bochecha esquerda
  /// a crista direita está a meia cara de distância e o seu peso é
  /// indistinguível de zero. O limite por caixa custa duas subtracções e uma
  /// exponencial, e dispensa percorrer os segmentos desse lado.
  ///
  /// [aWins] segue a convenção `pesoA >= pesoB`, empate incluído. É por isso
  /// que o corte de `b` admite igualdade e o de `a` não: descartar `a` por
  /// empate poderia trocar o vencedor.
  static ({double weight, bool aWins}) stronger({
    required Ridge a,
    required Ridge b,
    required double x,
    required double y,
    required double sigmaAcross,
    required double blendPx,
  }) {
    if (sigmaAcross < 1e-6) {
      return (weight: 0, aWins: true);
    }
    final twoSigma2 = 2 * sigmaAcross * sigmaAcross;
    final boundA = a.isEmpty
        ? 0.0
        : a.maxWeight * math.exp(-a._boxDistance2(x, y) / twoSigma2);
    final boundB = b.isEmpty
        ? 0.0
        : b.maxWeight * math.exp(-b._boxDistance2(x, y) / twoSigma2);

    // Avaliar primeiro quem promete mais deixa o corte do outro mais apertado.
    if (boundA >= boundB) {
      final wA = at(
        ridge: a,
        x: x,
        y: y,
        sigmaAcross: sigmaAcross,
        blendPx: blendPx,
      );
      if (boundB <= wA) {
        return (weight: wA, aWins: true);
      }
      final wB = at(
        ridge: b,
        x: x,
        y: y,
        sigmaAcross: sigmaAcross,
        blendPx: blendPx,
      );
      return wA >= wB ? (weight: wA, aWins: true) : (weight: wB, aWins: false);
    }

    final wB = at(
      ridge: b,
      x: x,
      y: y,
      sigmaAcross: sigmaAcross,
      blendPx: blendPx,
    );
    if (boundA < wB) {
      return (weight: wB, aWins: false);
    }
    final wA = at(
      ridge: a,
      x: x,
      y: y,
      sigmaAcross: sigmaAcross,
      blendPx: blendPx,
    );
    return wA >= wB ? (weight: wA, aWins: true) : (weight: wB, aWins: false);
  }

}
