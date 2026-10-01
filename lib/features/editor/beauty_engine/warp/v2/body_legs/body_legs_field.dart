import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/pose_landmark.dart';
import '../../../models/pose_result.dart';
import '../../../segment/person_mask.dart';
import '../displacement_field.dart';

/// Uma perna medida na imagem: eixo anca→tornozelo e bordas da silhueta.
class BodyLegGeometry {
  const BodyLegGeometry({
    required this.hip,
    required this.ankle,
    required this.kneeS,
    required this.normal,
    required this.innerSign,
    required this.sSamples,
    required this.outer,
    required this.inner,
    required this.gap,
  });

  final Offset hip;
  final Offset ankle;

  /// Joelho projectado no eixo anca→tornozelo (0..1). Sem joelho, 0.5.
  final double kneeS;

  /// Perpendicular ao eixo, virada para a direita da foto.
  final Offset normal;

  /// `+1` quando o lado de dentro (a outra perna) fica em `+normal`.
  final double innerSign;

  /// Posição ao longo do eixo anca→tornozelo de cada amostra.
  final Float64List sSamples;

  /// Distância com sinal do eixo à borda de fora / de dentro (px, ao longo de
  /// [normal]).
  final Float64List outer;
  final Float64List inner;

  /// Vão até à outra perna, a partir da borda de dentro (0 = encostadas).
  final Float64List gap;

  /// Meia-largura máxima da perna (px).
  double get maxHalfWidth {
    var m = 0.0;
    for (var k = 0; k < outer.length; k++) {
      m = math.max(m, (outer[k] - inner[k]).abs() / 2);
    }
    return m;
  }
}

class BodyLegsGeometry {
  const BodyLegsGeometry({required this.legs, required this.fromMask});

  final List<BodyLegGeometry> legs;
  final bool fromMask;
}

/// Faixa ao longo de anca→tornozelo: sobe em `[start, start + rise]` e desce
/// em `[end, end + fall]`. Com [kneeRelative], os valores são fracções da
/// posição do joelho de cada perna.
class BodyLegBand {
  const BodyLegBand({
    required this.start,
    required this.rise,
    required this.end,
    required this.fall,
    required this.gain,
    this.kneeRelative = false,
    this.requiresKnee = true,
  });

  final double start;
  final double rise;
  final double end;
  final double fall;
  final bool kneeRelative;

  /// `α = gain · t`. Cada borda livre anda `≈ α · meia-largura`.
  final double gain;

  /// Sem joelho fiável na foto não há campo. Quando é `false`, o joelho que
  /// falta estima-se pelo tronco.
  final bool requiresKnee;

  /// Pernas: da virilha ao tornozelo. Só com a perna à vista.
  static const legs = BodyLegBand(
    start: 0.08,
    rise: 0.20,
    end: 0.80,
    fall: 0.15,
    gain: 0.12,
  );

  /// Coxas: da virilha ao joelho, com cauda que acaba um pouco abaixo dele
  /// (em `1.2 ×` o joelho) para o efeito não parar seco no joelho. Metade do
  /// ganho das Pernas: a coxa de saia ou com a mão em cima pede um movimento
  /// seguro, como o do Meitu.
  static const thighs = BodyLegBand(
    start: 0.16,
    rise: 0.36,
    end: 0.75,
    fall: 0.45,
    gain: 0.06,
    kneeRelative: true,
    requiresKnee: false,
  );

  ({double start, double rise, double end, double fall}) resolve(
    double kneeS,
  ) {
    final k = kneeRelative ? kneeS : 1.0;
    return (start: start * k, rise: rise * k, end: end * k, fall: fall * k);
  }

  double weight(double s, double kneeS) {
    final r = resolve(kneeS);
    if (s <= r.start || s >= r.end + r.fall) {
      return 0;
    }
    return BodyLegsField._smoothstep((s - r.start) / r.rise) *
        (1 - BodyLegsField._smoothstep((s - r.end) / r.fall));
  }
}

/// Cache do campo unitário. O slider só entra em `α(t)`.
class BodyLegsFieldRuntime {
  PoseResult? pose;
  PersonMask? mask;
  BodyLegBand? band;
  int width = 0;
  int height = 0;
  Float32List? unitDx;
  Float32List? unitDy;
  Int32List? active;
  DisplacementField? field;
  BodyLegsGeometry? geometry;

  bool matches(
    PoseResult pose,
    PersonMask? mask,
    BodyLegBand band,
    int width,
    int height,
  ) {
    return identical(this.pose, pose) &&
        identical(this.mask, mask) &&
        identical(this.band, band) &&
        this.width == width &&
        this.height == height &&
        unitDx != null &&
        field != null;
  }
}

/// Pernas (Meitu Pernas → Legs). Só Δ perpendicular ao eixo de cada perna.
///
/// Direita do slider afina, esquerda engrossa. Cada perna escala por igual em
/// volta do seu próprio centro (medido na máscara), por isso as duas bordas
/// andam o mesmo e a forma da perna fica. Onde as coxas se tocam, a linha de
/// contacto fica parada e a perna escala em volta dela; a âncora passa ao
/// centro à medida que o vão abre (`abertura = smoothstep(vão / (0.8 · meia))`).
/// Fora da perna, o deslocamento da borda decai por smoothstep: para fora em
/// `0.55 × meia-largura`, para dentro no máximo até a meio do vão.
abstract final class BodyLegsField {
  BodyLegsField._();

  static const falloffOuter = 0.55;
  static const falloffInnerGap = 0.45;

  /// Vão (em meias-larguras) a partir do qual a perna escala do centro.
  static const openGap = 0.8;

  static const sampleCount = 64;
  static const minVisibility = 0.5;

  /// Canela que tem de se ver abaixo do joelho, em fracção da coxa, quando o
  /// tornozelo não está na foto. As Pernas afinam até ao tornozelo: com só a
  /// coxa à vista (saia, foto cortada) o Meitu também não as reconhece.
  static const minBelowKnee = 0.6;

  /// Coxa mínima (anca→joelho) em fracção do tronco (ombros→ancas).
  static const minThighToTorso = 0.5;

  static const _sStart = 0.0;
  static const _sEnd = 1.0;

  /// Coxa estimada (anca→joelho) em fracção do tronco, quando a faixa aceita
  /// joelho fora da foto.
  static const estimatedThighToTorso = 0.95;

  /// Coxa que tem de se ver abaixo da anca, em fracção da coxa estimada.
  static const minVisibleThigh = 0.3;

  static double alphaOf(double t, [BodyLegBand band = BodyLegBand.legs]) =>
      band.gain * t.clamp(-1.0, 1.0);

  /// Maior deslocamento de borda possível no extremo do slider (px).
  static double maxEdgeShift(
    BodyLegsGeometry geometry, [
    BodyLegBand band = BodyLegBand.legs,
  ]) {
    var m = 0.0;
    for (final leg in geometry.legs) {
      m = math.max(m, 2 * leg.maxHalfWidth);
    }
    return band.gain * m;
  }

  /// A ferramenta reconhece pernas nesta pose? Só pela pose, sem máscara:
  /// o painel usa-o para desligar o botão, como o Meitu.
  static bool isAvailable({
    required PoseResult pose,
    required Size imageSize,
    BodyLegBand band = BodyLegBand.legs,
  }) =>
      measure(pose: pose, imageSize: imageSize, band: band) != null;

  static DisplacementField? build({
    required PoseResult pose,
    required Size imageSize,
    PersonMask? mask,
    double t = 0,
    BodyLegBand band = BodyLegBand.legs,
    BodyLegsFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      return null;
    }
    final alpha = alphaOf(t, band);
    if (alpha.abs() <= 1e-9) {
      return null;
    }
    if (runtime != null && runtime.matches(pose, mask, band, width, height)) {
      _scaleActive(runtime, alpha);
      return runtime.field;
    }
    final geometry =
        measure(pose: pose, imageSize: imageSize, mask: mask, band: band);
    if (geometry == null) {
      return null;
    }
    final packed = _packUnits(
      width: width,
      height: height,
      geometry: geometry,
      band: band,
    );
    final target = runtime ?? BodyLegsFieldRuntime();
    target
      ..pose = pose
      ..mask = mask
      ..band = band
      ..width = width
      ..height = height
      ..unitDx = packed.unitDx
      ..unitDy = packed.unitDy
      ..active = packed.active
      ..geometry = geometry
      ..field = DisplacementField.zeros(width: width, height: height);
    _scaleActive(target, alpha);
    return target.field;
  }

  static BodyLegsGeometry? measure({
    required PoseResult pose,
    required Size imageSize,
    PersonMask? mask,
    BodyLegBand band = BodyLegBand.legs,
  }) {
    var a = _legAxis(pose, imageSize, 23, 25, 27);
    var b = _legAxis(pose, imageSize, 24, 26, 28);
    if (a == null ||
        b == null ||
        (a.$1 - b.$1).distance < 2 ||
        !_thighInFrame(pose, imageSize, a, b)) {
      if (band.requiresKnee) {
        return null;
      }
      final estimated = _estimatedAxes(pose, imageSize);
      if (estimated == null) {
        return null;
      }
      (a, b) = estimated;
    }
    final hipDistance = (a.$1 - b.$1).distance;
    final hasMask = mask != null &&
        mask.width > 0 &&
        mask.height > 0 &&
        mask.bytes.length >= mask.width * mask.height;
    final legs = <BodyLegGeometry>[
      _measureLeg(a, b, hipDistance, imageSize, hasMask ? mask : null),
      _measureLeg(b, a, hipDistance, imageSize, hasMask ? mask : null),
    ];
    return BodyLegsGeometry(legs: legs, fromMask: hasMask);
  }

  /// Anca, tornozelo e joelho. Sem tornozelo visível, prolonga-se
  /// anca→joelho ×2. O joelho tem de estar dentro da foto: o MediaPipe
  /// extrapola-o fora do quadro com visibilidade alta, e sem coxa à vista a
  /// faixa cairia na anca, onde costumam estar as mãos.
  static (Offset, Offset, Offset?)? _legAxis(
    PoseResult pose,
    Size imageSize,
    int hipIndex,
    int kneeIndex,
    int ankleIndex,
  ) {
    final hip = _pixel(pose, hipIndex, imageSize);
    final knee = _pixel(pose, kneeIndex, imageSize);
    if (hip == null || knee == null || !_inFrame(knee, imageSize)) {
      return null;
    }
    final ankle = _pixel(pose, ankleIndex, imageSize);
    if (ankle != null) {
      return (hip, ankle, knee);
    }
    return (hip, hip + (knee - hip) * 2, knee);
  }

  /// Joelhos estimados pelo tronco: coxa de `0.95 ×` ombros→ancas, na
  /// perpendicular à linha das ancas, para longe dos ombros. Exige que se veja
  /// pelo menos `0.3` dessa coxa abaixo das ancas.
  static ((Offset, Offset, Offset?), (Offset, Offset, Offset?))? _estimatedAxes(
      PoseResult pose, Size imageSize) {
    final ha = _pixel(pose, 23, imageSize);
    final hb = _pixel(pose, 24, imageSize);
    final ls = _pixel(pose, 11, imageSize);
    final rs = _pixel(pose, 12, imageSize);
    if (ha == null || hb == null || ls == null || rs == null) {
      return null;
    }
    final hips = ha - hb;
    if (hips.distance < 2) {
      return null;
    }
    final hipMid = (ha + hb) / 2;
    final torso = hipMid - (ls + rs) / 2;
    if (torso.distance < 2) {
      return null;
    }
    var down = Offset(-hips.dy, hips.dx) / hips.distance;
    if (down.dx * torso.dx + down.dy * torso.dy < 0) {
      down = -down;
    }
    final thigh = down * (estimatedThighToTorso * torso.distance);
    (Offset, Offset, Offset?)? axis(Offset hip) {
      if (!_inFrame(hip + thigh * minVisibleThigh, imageSize)) {
        return null;
      }
      return (hip, hip + thigh * 2, hip + thigh);
    }

    final a = axis(ha);
    final b = axis(hb);
    return a == null || b == null ? null : (a, b);
  }

  static bool _inFrame(Offset p, Size size) =>
      p.dx >= 0 && p.dy >= 0 && p.dx <= size.width && p.dy <= size.height;

  /// Numa foto cortada acima do joelho o MediaPipe também o põe dentro do
  /// quadro, encostado à borda e com a coxa curta. Exige-se o tornozelo na foto
  /// ou canela à vista e, com ombros, coxa de pelo menos metade do tronco.
  static bool _thighInFrame(
    PoseResult pose,
    Size imageSize,
    (Offset, Offset, Offset?) a,
    (Offset, Offset, Offset?) b,
  ) {
    final ls = _pixel(pose, 11, imageSize);
    final rs = _pixel(pose, 12, imageSize);
    final torso = ls == null || rs == null
        ? null
        : ((ls + rs) / 2 - (a.$1 + b.$1) / 2).distance;
    for (final (leg, ankleIndex) in [(a, 27), (b, 28)]) {
      final hip = leg.$1;
      final knee = leg.$3!;
      final thigh = knee - hip;
      final ankle = _pixel(pose, ankleIndex, imageSize);
      final shinInFrame = ankle != null && _inFrame(ankle, imageSize);
      if (!shinInFrame && !_inFrame(knee + thigh * minBelowKnee, imageSize)) {
        return false;
      }
      if (torso != null && thigh.distance < minThighToTorso * torso) {
        return false;
      }
    }
    return true;
  }

  static BodyLegGeometry _measureLeg(
    (Offset, Offset, Offset?) leg,
    (Offset, Offset, Offset?) other,
    double hipDistance,
    Size imageSize,
    PersonMask? mask,
  ) {
    final hip = leg.$1;
    final ankle = leg.$2;
    final axis = ankle - hip;
    final length = math.max(1.0, axis.distance);
    final e = axis / length;
    final n =
        Offset(-e.dy, e.dx).dx >= 0 ? Offset(-e.dy, e.dx) : Offset(e.dy, -e.dx);
    final otherAxis = other.$2 - other.$1;
    final knee = leg.$3;
    final kneeS = knee == null
        ? 0.5
        : (((knee - hip).dx * e.dx + (knee - hip).dy * e.dy) / length)
            .clamp(0.25, 0.75);

    final sValues = Float64List(sampleCount);
    final outer = Float64List(sampleCount);
    final inner = Float64List(sampleCount);
    final gap = Float64List(sampleCount);

    final mid = other.$1 + otherAxis * 0.5 - (hip + axis * 0.5);
    final innerSign = (mid.dx * n.dx + mid.dy * n.dy) >= 0 ? 1.0 : -1.0;
    final innerDir = n * innerSign;
    final outerDir = -innerDir;

    for (var k = 0; k < sampleCount; k++) {
      final s = _sStart + (_sEnd - _sStart) * k / (sampleCount - 1);
      sValues[k] = s;
      final p = hip + axis * s;
      final q = other.$1 + otherAxis * s;
      final across = ((q - p).dx * innerDir.dx + (q - p).dy * innerDir.dy)
          .clamp(2.0, double.infinity);
      final halfway = across / 2;
      final estimate = math.max(
        3.0,
        math.min(halfway, hipDistance * _lerp(0.50, 0.18, s)),
      );

      var outerU = estimate;
      var innerU = math.min(estimate, halfway);
      var gapU = math.max(0.0, across - 2 * innerU);
      if (mask != null && _maskAt(mask, imageSize, p) >= 0.5) {
        outerU = _searchExit(
          mask,
          imageSize,
          p,
          outerDir,
          0.3 * estimate,
          1.8 * estimate,
        );
        final exit = _searchExit(mask, imageSize, p, innerDir, 0, halfway);
        innerU = exit;
        if (exit >= halfway) {
          gapU = 0;
        } else {
          final reentry = _searchEntry(
            mask,
            imageSize,
            p,
            innerDir,
            exit,
            across,
          );
          gapU = reentry - exit;
        }
      }
      outer[k] = -innerSign * outerU;
      inner[k] = innerSign * innerU;
      gap[k] = gapU;
    }
    _smooth(outer);
    _smooth(inner);
    _smooth(gap);
    return BodyLegGeometry(
      hip: hip,
      ankle: ankle,
      kneeS: kneeS,
      normal: n,
      innerSign: innerSign,
      sSamples: sValues,
      outer: outer,
      inner: inner,
      gap: gap,
    );
  }

  /// Primeira saída da máscara em `[from, to]`; devolve `to` se não sair.
  static double _searchExit(
    PersonMask mask,
    Size imageSize,
    Offset center,
    Offset dir,
    double from,
    double to,
  ) {
    for (var u = from; u <= to; u += 1.0) {
      final p = center + dir * u;
      if (!_inside(imageSize, p) || _maskAt(mask, imageSize, p) < 0.5) {
        return u;
      }
    }
    return to;
  }

  /// Primeira entrada na máscara em `[from, to]`; devolve `to` se não entrar.
  static double _searchEntry(
    PersonMask mask,
    Size imageSize,
    Offset center,
    Offset dir,
    double from,
    double to,
  ) {
    for (var u = from; u <= to; u += 1.0) {
      final p = center + dir * u;
      if (!_inside(imageSize, p)) {
        return to;
      }
      if (_maskAt(mask, imageSize, p) >= 0.5) {
        return u;
      }
    }
    return to;
  }

  static bool _inside(Size size, Offset p) =>
      p.dx >= 0 && p.dy >= 0 && p.dx < size.width && p.dy < size.height;

  static double _maskAt(PersonMask mask, Size imageSize, Offset p) {
    return mask.sampleNormalized(
        p.dx / imageSize.width, p.dy / imageSize.height);
  }

  /// Mediana de 5 contra dentes da máscara, depois caixa ×2.
  static void _smooth(Float64List values) {
    final n = values.length;
    final median = Float64List(n);
    for (var i = 0; i < n; i++) {
      final window = <double>[
        for (var j = i - 2; j <= i + 2; j++) values[j.clamp(0, n - 1)],
      ]..sort();
      median[i] = window[2];
    }
    var current = median;
    for (var pass = 0; pass < 2; pass++) {
      final next = Float64List(n);
      for (var i = 0; i < n; i++) {
        var sum = 0.0;
        for (var j = i - 3; j <= i + 3; j++) {
          sum += current[j.clamp(0, n - 1)];
        }
        next[i] = sum / 7;
      }
      current = next;
    }
    for (var i = 0; i < n; i++) {
      values[i] = current[i];
    }
  }

  static double _smoothstep(double x) {
    final q = x.clamp(0.0, 1.0);
    return q * q * (3 - 2 * q);
  }

  /// Deslocamento unitário ao longo de `normal` (antes de `−α · band`).
  static double _profile(BodyLegGeometry leg, double s, double u) {
    const last = sampleCount - 1;
    final f = (s * last).clamp(0.0, last.toDouble());
    final i = f.floor().clamp(0, last - 1);
    final w = f - i;
    double at(Float64List v) => v[i] * (1 - w) + v[i + 1] * w;

    final outerU = at(leg.outer);
    final innerU = at(leg.inner);
    final gap = math.max(0.0, at(leg.gap));
    final lo = math.min(outerU, innerU);
    final hi = math.max(outerU, innerU);
    final half = (hi - lo) / 2;
    if (half <= 0.5) {
      return 0;
    }
    final center = (lo + hi) / 2;
    final open = _smoothstep(gap / (openGap * half));
    final anchor = innerU + (center - innerU) * open;

    if (u >= lo && u <= hi) {
      return u - anchor;
    }
    final upper = u > hi;
    final edge = upper ? hi : lo;
    final isInner = upper == (leg.innerSign > 0);
    final falloff = isInner
        ? math.min(falloffOuter * half, falloffInnerGap * gap)
        : falloffOuter * half;
    if (falloff <= 1e-6) {
      return 0;
    }
    final r = (u - edge).abs() / falloff;
    if (r >= 1) {
      return 0;
    }
    return (edge - anchor) * (1 - _smoothstep(r));
  }

  static ({Float32List unitDx, Float32List unitDy, Int32List active})
      _packUnits({
    required int width,
    required int height,
    required BodyLegsGeometry geometry,
    required BodyLegBand band,
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final leg in geometry.legs) {
      final reach = leg.maxHalfWidth * (2 + falloffOuter) + 2;
      final r = band.resolve(leg.kneeS);
      for (final s in [r.start, r.end + r.fall]) {
        final c = leg.hip + (leg.ankle - leg.hip) * s;
        for (final side in [-1.0, 1.0]) {
          final p = c + leg.normal * (side * reach);
          minX = math.min(minX, p.dx);
          maxX = math.max(maxX, p.dx);
          minY = math.min(minY, p.dy);
          maxY = math.max(maxY, p.dy);
        }
      }
    }
    final x0 = minX.floor().clamp(0, width - 1);
    final x1 = maxX.ceil().clamp(0, width - 1);
    final y0 = minY.floor().clamp(0, height - 1);
    final y1 = maxY.ceil().clamp(0, height - 1);

    final active = <int>[];
    final dxs = <double>[];
    final dys = <double>[];
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        var dx = 0.0;
        var dy = 0.0;
        for (final leg in geometry.legs) {
          final axis = leg.ankle - leg.hip;
          final length2 = axis.dx * axis.dx + axis.dy * axis.dy;
          final px = x + 0.5 - leg.hip.dx;
          final py = y + 0.5 - leg.hip.dy;
          final s = (px * axis.dx + py * axis.dy) / length2;
          final w = band.weight(s, leg.kneeS);
          if (w <= 0) {
            continue;
          }
          final u = px * leg.normal.dx + py * leg.normal.dy;
          final v = _profile(leg, s, u);
          if (v == 0) {
            continue;
          }
          dx -= w * v * leg.normal.dx;
          dy -= w * v * leg.normal.dy;
        }
        if (dx.abs() < 1e-6 && dy.abs() < 1e-6) {
          continue;
        }
        active.add(y * width + x);
        dxs.add(dx);
        dys.add(dy);
      }
    }
    return (
      unitDx: Float32List.fromList(dxs),
      unitDy: Float32List.fromList(dys),
      active: Int32List.fromList(active),
    );
  }

  static void _scaleActive(BodyLegsFieldRuntime runtime, double alpha) {
    final field = runtime.field!;
    final active = runtime.active!;
    final ux = runtime.unitDx!;
    final uy = runtime.unitDy!;
    for (var k = 0; k < active.length; k++) {
      final i = active[k];
      field.dx[i] = alpha * ux[k];
      field.dy[i] = alpha * uy[k];
    }
  }

  static Offset? _pixel(PoseResult pose, int index, Size imageSize) {
    PoseLandmark? hit;
    for (final l in pose.landmarks) {
      if (l.index == index) {
        hit = l;
        break;
      }
    }
    if (hit == null || hit.visibility < minVisibility) {
      return null;
    }
    return Offset(
      hit.normalized.dx * imageSize.width,
      hit.normalized.dy * imageSize.height,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
