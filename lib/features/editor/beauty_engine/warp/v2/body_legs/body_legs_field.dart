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
    required this.normal,
    required this.innerSign,
    required this.sSamples,
    required this.outer,
    required this.inner,
    required this.gap,
  });

  final Offset hip;
  final Offset ankle;

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

/// Cache do campo unitário. O slider só entra em `α(t)`.
class BodyLegsFieldRuntime {
  PoseResult? pose;
  PersonMask? mask;
  int width = 0;
  int height = 0;
  Float32List? unitDx;
  Float32List? unitDy;
  Int32List? active;
  DisplacementField? field;
  BodyLegsGeometry? geometry;

  bool matches(PoseResult pose, PersonMask? mask, int width, int height) {
    return identical(this.pose, pose) &&
        identical(this.mask, mask) &&
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

  /// `α = gain · t`. Cada borda livre anda `≈ α · meia-largura`.
  static const gain = 0.12;

  /// Faixa ao longo de anca→tornozelo: sobe de 0.08 a 0.28, desce de 0.80 a
  /// 0.95. Acima fica a anca/virilha; abaixo, o tornozelo e o pé.
  static const bandIn = 0.08;
  static const bandInSpan = 0.20;
  static const bandOut = 0.80;
  static const bandOutSpan = 0.15;

  static const falloffOuter = 0.55;
  static const falloffInnerGap = 0.45;

  /// Vão (em meias-larguras) a partir do qual a perna escala do centro.
  static const openGap = 0.8;

  static const sampleCount = 64;
  static const minVisibility = 0.5;

  static const _sStart = 0.0;
  static const _sEnd = 1.0;

  static double alphaOf(double t) => gain * t.clamp(-1.0, 1.0);

  /// Maior deslocamento de borda possível no extremo do slider (px).
  static double maxEdgeShift(BodyLegsGeometry geometry) {
    var m = 0.0;
    for (final leg in geometry.legs) {
      m = math.max(m, 2 * leg.maxHalfWidth);
    }
    return gain * m;
  }

  static DisplacementField? build({
    required PoseResult pose,
    required Size imageSize,
    PersonMask? mask,
    double t = 0,
    BodyLegsFieldRuntime? runtime,
  }) {
    final width = imageSize.width.round();
    final height = imageSize.height.round();
    if (width <= 0 || height <= 0) {
      return null;
    }
    final alpha = alphaOf(t);
    if (alpha.abs() <= 1e-9) {
      return null;
    }
    if (runtime != null && runtime.matches(pose, mask, width, height)) {
      _scaleActive(runtime, alpha);
      return runtime.field;
    }
    final geometry = measure(pose: pose, imageSize: imageSize, mask: mask);
    if (geometry == null) {
      return null;
    }
    final packed = _packUnits(width: width, height: height, geometry: geometry);
    final target = runtime ?? BodyLegsFieldRuntime();
    target
      ..pose = pose
      ..mask = mask
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
  }) {
    final a = _legAxis(pose, imageSize, 23, 25, 27);
    final b = _legAxis(pose, imageSize, 24, 26, 28);
    if (a == null || b == null) {
      return null;
    }
    final hipDistance = (a.$1 - b.$1).distance;
    if (hipDistance < 2) {
      return null;
    }
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

  /// Anca e tornozelo. Sem tornozelo visível, prolonga-se anca→joelho.
  static (Offset, Offset)? _legAxis(
    PoseResult pose,
    Size imageSize,
    int hipIndex,
    int kneeIndex,
    int ankleIndex,
  ) {
    final hip = _pixel(pose, hipIndex, imageSize);
    if (hip == null) {
      return null;
    }
    final ankle = _pixel(pose, ankleIndex, imageSize);
    if (ankle != null) {
      return (hip, ankle);
    }
    final knee = _pixel(pose, kneeIndex, imageSize);
    if (knee == null) {
      return null;
    }
    return (hip, hip + (knee - hip) * 2);
  }

  static BodyLegGeometry _measureLeg(
    (Offset, Offset) leg,
    (Offset, Offset) other,
    double hipDistance,
    Size imageSize,
    PersonMask? mask,
  ) {
    final hip = leg.$1;
    final ankle = leg.$2;
    final axis = ankle - hip;
    final length = math.max(1.0, axis.distance);
    final e = axis / length;
    final n = Offset(-e.dy, e.dx).dx >= 0
        ? Offset(-e.dy, e.dx)
        : Offset(e.dy, -e.dx);
    final otherAxis = other.$2 - other.$1;

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
    return mask.sampleNormalized(p.dx / imageSize.width, p.dy / imageSize.height);
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

  static double _band(double s) {
    if (s <= bandIn || s >= bandOut + bandOutSpan) {
      return 0;
    }
    return _smoothstep((s - bandIn) / bandInSpan) *
        (1 - _smoothstep((s - bandOut) / bandOutSpan));
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
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final leg in geometry.legs) {
      final reach = leg.maxHalfWidth * (2 + falloffOuter) + 2;
      for (final s in [bandIn, bandOut + bandOutSpan]) {
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
          final band = _band(s);
          if (band <= 0) {
            continue;
          }
          final u = px * leg.normal.dx + py * leg.normal.dy;
          final v = _profile(leg, s, u);
          if (v == 0) {
            continue;
          }
          dx -= band * v * leg.normal.dx;
          dy -= band * v * leg.normal.dy;
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
