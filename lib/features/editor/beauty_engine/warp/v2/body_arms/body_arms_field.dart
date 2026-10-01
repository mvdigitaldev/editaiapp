import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/pose_landmark.dart';
import '../../../models/pose_result.dart';
import '../../../segment/person_mask.dart';
import '../displacement_field.dart';

/// Um segmento do braço (ombro→cotovelo ou cotovelo→pulso) medido na imagem.
class BodyArmSegment {
  const BodyArmSegment({
    required this.a,
    required this.b,
    required this.normal,
    required this.startS,
    required this.endS,
    required this.lo,
    required this.hi,
    required this.gapLo,
    required this.gapHi,
  });

  final Offset a;
  final Offset b;

  /// Perpendicular unitária ao segmento; `lo`/`hi` são distâncias com sinal
  /// ao longo dela.
  final Offset normal;

  /// Posição do início / fim no braço inteiro (0 no ombro, 1 no pulso).
  final double startS;
  final double endS;

  /// Bordas da silhueta do braço (px, com sinal ao longo de [normal]).
  final Float64List lo;
  final Float64List hi;

  /// Vão de cada lado até à pessoa outra vez (tronco, cabeça); 0 = encostado.
  final Float64List gapLo;
  final Float64List gapHi;

  double get maxHalfWidth {
    var m = 0.0;
    for (var k = 0; k < lo.length; k++) {
      m = math.max(m, (hi[k] - lo[k]).abs() / 2);
    }
    return m;
  }
}

class BodyArmsGeometry {
  const BodyArmsGeometry({required this.arms, required this.fromMask});

  /// Um braço é uma lista de dois segmentos; só entram os braços visíveis.
  final List<List<BodyArmSegment>> arms;
  final bool fromMask;
}

/// Cache do campo unitário. O slider só entra em `α(t)`.
class BodyArmsFieldRuntime {
  PoseResult? pose;
  PersonMask? mask;
  int width = 0;
  int height = 0;
  Float32List? unitDx;
  Float32List? unitDy;
  Int32List? active;
  DisplacementField? field;
  BodyArmsGeometry? geometry;

  bool matches(PoseResult pose, PersonMask? mask, int width, int height) {
    return identical(this.pose, pose) &&
        identical(this.mask, mask) &&
        this.width == width &&
        this.height == height &&
        unitDx != null &&
        field != null;
  }
}

/// Braços (Meitu Braços → Arms). Só Δ perpendicular a cada segmento.
///
/// Direita do slider afina, esquerda engrossa. Cada segmento escala em volta
/// do centro do braço medido na máscara; o lado encostado ao tronco ou à
/// cabeça fica parado e o braço escala em volta dele (`abertura =
/// smoothstep(vão / (0.8 · meia))`, como nas coxas). Fora do braço a borda
/// decai em `0.55 × meia-largura`, no máximo `0.45 × vão`: o tronco e a cara
/// do outro lado do vão não mexem. No cotovelo os dois segmentos misturam-se
/// com pesos normalizados; a faixa sobe depois do ombro e pára antes do pulso,
/// por isso a mão fica.
abstract final class BodyArmsField {
  BodyArmsField._();

  /// `α = gain · t`. Movimento natural.
  static const gain = 0.08;

  static const falloffOuter = 0.55;
  static const falloffGap = 0.45;
  static const openGap = 0.8;

  /// Faixa ao longo do braço (0 ombro, 1 pulso).
  static const bandStart = 0.04;
  static const bandRise = 0.18;
  static const bandEnd = 0.80;
  static const bandFall = 0.14;

  static const sampleCount = 32;
  static const minVisibility = 0.5;

  /// Meia-largura estimada em fracção da largura dos ombros: braço → pulso.
  static const upperHalf = 0.14;
  static const lowerHalf = 0.10;

  /// Até onde se procura a borda. Braços cheios passam de `1.7 ×` a
  /// estimativa; o tronco ao lado de um braço colado fica sempre além.
  static const exitReach = 2.6;

  /// Largura da passagem braço↔antebraço, em meias-larguras do braço, na
  /// diferença de distâncias aos dois segmentos. Sem ela ganha o segmento
  /// mais próximo e a bissectriz do cotovelo fica vincada.
  static const elbowBlend = 1.0;

  static const _arms = [(11, 13, 15), (12, 14, 16)];

  static double alphaOf(double t) => gain * t.clamp(-1.0, 1.0);

  static double maxEdgeShift(BodyArmsGeometry geometry) {
    var m = 0.0;
    for (final arm in geometry.arms) {
      for (final seg in arm) {
        m = math.max(m, 2 * seg.maxHalfWidth);
      }
    }
    return gain * m;
  }

  /// Algum braço reconhecido nesta pose? Só pela pose, sem máscara.
  static bool isAvailable({
    required PoseResult pose,
    required Size imageSize,
  }) =>
      measure(pose: pose, imageSize: imageSize) != null;

  static DisplacementField? build({
    required PoseResult pose,
    required Size imageSize,
    PersonMask? mask,
    double t = 0,
    BodyArmsFieldRuntime? runtime,
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
    final target = runtime ?? BodyArmsFieldRuntime();
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

  /// Ombro, cotovelo e pulso visíveis e dentro da foto, por braço.
  static BodyArmsGeometry? measure({
    required PoseResult pose,
    required Size imageSize,
    PersonMask? mask,
  }) {
    final ls = _pixel(pose, 11, imageSize);
    final rs = _pixel(pose, 12, imageSize);
    if (ls == null || rs == null) {
      return null;
    }
    final shoulderWidth = (ls - rs).distance;
    if (shoulderWidth < 4) {
      return null;
    }
    final hasMask = mask != null &&
        mask.width > 0 &&
        mask.height > 0 &&
        mask.bytes.length >= mask.width * mask.height;
    final arms = <List<BodyArmSegment>>[];
    for (final (si, ei, wi) in _arms) {
      final shoulder = _pixel(pose, si, imageSize);
      final elbow = _pixel(pose, ei, imageSize);
      final wrist = _pixel(pose, wi, imageSize);
      if (shoulder == null ||
          elbow == null ||
          wrist == null ||
          !_inFrame(elbow, imageSize) ||
          !_inFrame(wrist, imageSize)) {
        continue;
      }
      final upper = (elbow - shoulder).distance;
      final lower = (wrist - elbow).distance;
      if (upper < 4 || lower < 4) {
        continue;
      }
      final total = upper + lower;
      arms.add([
        _measureSegment(
          shoulder,
          elbow,
          0,
          upper / total,
          shoulderWidth,
          imageSize,
          hasMask ? mask : null,
        ),
        _measureSegment(
          elbow,
          wrist,
          upper / total,
          1,
          shoulderWidth,
          imageSize,
          hasMask ? mask : null,
        ),
      ]);
    }
    if (arms.isEmpty) {
      return null;
    }
    return BodyArmsGeometry(arms: arms, fromMask: hasMask);
  }

  static BodyArmSegment _measureSegment(
    Offset a,
    Offset b,
    double startS,
    double endS,
    double shoulderWidth,
    Size imageSize,
    PersonMask? mask,
  ) {
    final axis = b - a;
    final e = axis / axis.distance;
    final n = Offset(-e.dy, e.dx);
    final lo = Float64List(sampleCount);
    final hi = Float64List(sampleCount);
    final gapLo = Float64List(sampleCount);
    final gapHi = Float64List(sampleCount);
    for (var k = 0; k < sampleCount; k++) {
      final s = k / (sampleCount - 1);
      final p = a + axis * s;
      final armS = startS + (endS - startS) * s;
      final estimate =
          math.max(3.0, shoulderWidth * _lerp(upperHalf, lowerHalf, armS));
      var minus = estimate;
      var plus = estimate;
      var gMinus = double.infinity;
      var gPlus = double.infinity;
      if (mask != null) {
        if (_maskAt(mask, imageSize, p) >= 0.5) {
          (minus, gMinus) = _side(mask, imageSize, p, -n, estimate);
          (plus, gPlus) = _side(mask, imageSize, p, n, estimate);
        } else {
          // Eixo da pose fora do braço: nesta amostra não se mexe.
          gMinus = 0;
          gPlus = 0;
        }
      }
      lo[k] = -minus;
      hi[k] = plus;
      gapLo[k] = math.min(gMinus, 4 * estimate);
      gapHi[k] = math.min(gPlus, 4 * estimate);
    }
    _smooth(lo);
    _smooth(hi);
    _smooth(gapLo);
    _smooth(gapHi);
    return BodyArmSegment(
      a: a,
      b: b,
      normal: n,
      startS: startS,
      endS: endS,
      lo: lo,
      hi: hi,
      gapLo: gapLo,
      gapHi: gapHi,
    );
  }

  /// Borda e vão de um lado. Sem saída da máscara até [exitReach] × a
  /// estimativa, o braço está encostado: borda na estimativa e vão 0.
  static (double, double) _side(
    PersonMask mask,
    Size imageSize,
    Offset p,
    Offset dir,
    double estimate,
  ) {
    final cap = exitReach * estimate;
    double? exit;
    for (var u = 1.0; u <= cap; u += 1.0) {
      final q = p + dir * u;
      if (!_inside(imageSize, q)) {
        return (u, double.infinity);
      }
      if (_maskAt(mask, imageSize, q) < 0.5) {
        exit = u;
        break;
      }
    }
    if (exit == null) {
      return (estimate, 0);
    }
    final far = exit + 4 * estimate;
    for (var u = exit; u <= far; u += 1.0) {
      final q = p + dir * u;
      if (!_inside(imageSize, q)) {
        return (exit, double.infinity);
      }
      if (_maskAt(mask, imageSize, q) >= 0.5) {
        return (exit, u - exit);
      }
    }
    return (exit, double.infinity);
  }

  static double _bandWeight(double s) {
    if (s <= bandStart || s >= bandEnd + bandFall) {
      return 0;
    }
    return _smoothstep((s - bandStart) / bandRise) *
        (1 - _smoothstep((s - bandEnd) / bandFall));
  }

  /// Deslocamento unitário ao longo de `normal` (antes de `−α · faixa`).
  static double _profile(BodyArmSegment seg, double s, double u) {
    const last = sampleCount - 1;
    final f = (s.clamp(0.0, 1.0) * last).clamp(0.0, last.toDouble());
    final i = f.floor().clamp(0, last - 1);
    final w = f - i;
    double at(Float64List v) => v[i] * (1 - w) + v[i + 1] * w;

    final lo = at(seg.lo);
    final hi = at(seg.hi);
    final half = (hi - lo) / 2;
    if (half <= 0.5) {
      return 0;
    }
    final gLo = math.max(0.0, at(seg.gapLo));
    final gHi = math.max(0.0, at(seg.gapHi));
    final aLo = _smoothstep(gLo / (openGap * half));
    final aHi = _smoothstep(gHi / (openGap * half));
    final amp = math.max(aLo, aHi);
    if (amp <= 1e-6) {
      return 0;
    }
    final anchor = lo + (hi - lo) * (aLo / (aLo + aHi));
    if (u >= lo && u <= hi) {
      return amp * (u - anchor);
    }
    final upper = u > hi;
    final edge = upper ? hi : lo;
    final gap = upper ? gHi : gLo;
    final falloff = math.min(falloffOuter * half, falloffGap * gap);
    if (falloff <= 1e-6) {
      return 0;
    }
    final r = (u - edge).abs() / falloff;
    if (r >= 1) {
      return 0;
    }
    return amp * (edge - anchor) * (1 - _smoothstep(r));
  }

  static ({Float32List unitDx, Float32List unitDy, Int32List active})
      _packUnits({
    required int width,
    required int height,
    required BodyArmsGeometry geometry,
  }) {
    final active = <int>[];
    final dxs = <double>[];
    final dys = <double>[];
    final touched = <int, int>{};
    for (final arm in geometry.arms) {
      var reach = 0.0;
      for (final seg in arm) {
        reach = math.max(reach, seg.maxHalfWidth * (2 + falloffOuter) + 2);
      }
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = -double.infinity;
      var maxY = -double.infinity;
      for (final seg in arm) {
        for (final p in [seg.a, seg.b]) {
          minX = math.min(minX, p.dx - reach);
          maxX = math.max(maxX, p.dx + reach);
          minY = math.min(minY, p.dy - reach);
          maxY = math.max(maxY, p.dy + reach);
        }
      }
      final x0 = minX.floor().clamp(0, width - 1);
      final x1 = maxX.ceil().clamp(0, width - 1);
      final y0 = minY.floor().clamp(0, height - 1);
      final y1 = maxY.ceil().clamp(0, height - 1);
      final upper = arm[0];
      final lower = arm[1];
      final blend = math.max(
        4.0,
        elbowBlend * (upper.maxHalfWidth + lower.maxHalfWidth) / 2,
      );
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          final (dUpper, sUpper, vUpper) = _sample(upper, x, y);
          final (dLower, sLower, vLower) = _sample(lower, x, y);
          // Peso do antebraço pela diferença de distâncias, numa largura de
          // braço: contínuo na bissectriz do cotovelo.
          final wl = _smoothstep((dUpper - dLower) / (2 * blend) + 0.5);
          final wu = 1 - wl;
          final armS = wu * sUpper + wl * sLower;
          final band = _bandWeight(armS);
          if (band <= 0) {
            continue;
          }
          final dx = -band *
              (wu * vUpper * upper.normal.dx + wl * vLower * lower.normal.dx);
          final dy = -band *
              (wu * vUpper * upper.normal.dy + wl * vLower * lower.normal.dy);
          if (dx.abs() < 1e-6 && dy.abs() < 1e-6) {
            continue;
          }
          final i = y * width + x;
          final k = touched[i];
          if (k != null) {
            dxs[k] += dx;
            dys[k] += dy;
          } else {
            touched[i] = active.length;
            active.add(i);
            dxs.add(dx);
            dys.add(dy);
          }
        }
      }
    }
    return (
      unitDx: Float32List.fromList(dxs),
      unitDy: Float32List.fromList(dys),
      active: Int32List.fromList(active),
    );
  }

  /// Distância ao segmento recortado, posição no braço e perfil no pixel.
  static (double, double, double) _sample(BodyArmSegment seg, int x, int y) {
    final axis = seg.b - seg.a;
    final length2 = axis.dx * axis.dx + axis.dy * axis.dy;
    final px = x + 0.5 - seg.a.dx;
    final py = y + 0.5 - seg.a.dy;
    final s = (px * axis.dx + py * axis.dy) / length2;
    final sc = s.clamp(0.0, 1.0);
    final ex = px - axis.dx * sc;
    final ey = py - axis.dy * sc;
    final u = px * seg.normal.dx + py * seg.normal.dy;
    return (
      math.sqrt(ex * ex + ey * ey),
      seg.startS + (seg.endS - seg.startS) * sc,
      _profile(seg, s, u),
    );
  }

  static void _scaleActive(BodyArmsFieldRuntime runtime, double alpha) {
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
        for (var j = i - 2; j <= i + 2; j++) {
          sum += current[j.clamp(0, n - 1)];
        }
        next[i] = sum / 5;
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

  static bool _inFrame(Offset p, Size size) =>
      p.dx >= 0 && p.dy >= 0 && p.dx <= size.width && p.dy <= size.height;

  static bool _inside(Size size, Offset p) =>
      p.dx >= 0 && p.dy >= 0 && p.dx < size.width && p.dy < size.height;

  static double _maskAt(PersonMask mask, Size imageSize, Offset p) =>
      mask.sampleNormalized(p.dx / imageSize.width, p.dy / imageSize.height);

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
