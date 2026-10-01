import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/pose_landmark.dart';
import '../../../models/pose_result.dart';
import '../../../segment/person_mask.dart';
import '../displacement_field.dart';

/// Geometria da cintura medida na imagem: eixo do tronco e bordas da silhueta.
class BodyWaistGeometry {
  const BodyWaistGeometry({
    required this.shoulderMid,
    required this.hipMid,
    required this.tSamples,
    required this.edgeLeft,
    required this.edgeRight,
    required this.fromMask,
  });

  final Offset shoulderMid;
  final Offset hipMid;

  /// Posição ao longo do eixo ombro→quadril de cada amostra.
  final Float64List tSamples;

  /// Meia-largura da silhueta (px) para o lado esquerdo / direito da foto.
  final Float64List edgeLeft;
  final Float64List edgeRight;

  /// `false` quando não houve máscara e a borda veio só da pose.
  final bool fromMask;
}

/// Cache do campo unitário. O slider só entra em `α(t)`.
class BodyWaistFieldRuntime {
  PoseResult? pose;
  PersonMask? mask;
  int width = 0;
  int height = 0;
  Float32List? unitDx;
  Float32List? unitDy;
  Int32List? active;
  DisplacementField? field;
  BodyWaistGeometry? geometry;

  bool matches(PoseResult pose, PersonMask? mask, int width, int height) {
    return identical(this.pose, pose) &&
        identical(this.mask, mask) &&
        this.width == width &&
        this.height == height &&
        unitDx != null &&
        field != null;
  }
}

/// Cintura (Meitu Waist). Só Δ perpendicular ao eixo do tronco.
///
/// Direita do slider afina, esquerda alarga. Dentro da silhueta o tronco é
/// comprimido em direcção ao eixo, proporcional à distância (`D = −α·u`), para
/// a textura da roupa encolher por igual. Fora, o deslocamento da borda decai
/// por smoothstep numa banda de fundo `falloffEdge × meia-largura`: é o fundo
/// que estica para fechar o espaço, como nos apps.
abstract final class BodyWaistField {
  BodyWaistField._();

  /// `α = gain · t`. A borda anda `≈ α · meia-largura`.
  static const gain = 0.10;

  /// Centro e meia-altura da faixa, em fracção do eixo ombro→quadril.
  static const centerT = 0.66;
  static const halfSpanT = 0.30;

  /// Banda de fundo que acompanha a borda, em fracção da meia-largura.
  /// Injectividade: `1 − α · 1.5 / falloffEdge > 0` ⇒ folga 0,73 no extremo.
  static const falloffEdge = 0.55;

  static const sampleCount = 48;
  static const minVisibility = 0.5;

  static const _leftShoulder = 11;
  static const _rightShoulder = 12;
  static const _leftHip = 23;
  static const _rightHip = 24;

  static double alphaOf(double t) => gain * t.clamp(-1.0, 1.0);

  /// Maior deslocamento da borda possível no extremo do slider (px).
  static double maxEdgeShift(BodyWaistGeometry geometry) {
    var edge = 0.0;
    for (var k = 0; k < geometry.edgeLeft.length; k++) {
      edge = math.max(
        edge,
        math.max(geometry.edgeLeft[k], geometry.edgeRight[k]),
      );
    }
    return gain * edge;
  }

  /// Campo, ou `null` sem pose fiável / slider em zero.
  static DisplacementField? build({
    required PoseResult pose,
    required Size imageSize,
    PersonMask? mask,
    double t = 0,
    BodyWaistFieldRuntime? runtime,
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
    final packed = _packUnits(
      width: width,
      height: height,
      geometry: geometry,
    );
    final target = runtime ?? BodyWaistFieldRuntime();
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

  /// Eixo do tronco e bordas da silhueta ao longo da faixa da cintura.
  static BodyWaistGeometry? measure({
    required PoseResult pose,
    required Size imageSize,
    PersonMask? mask,
  }) {
    final ls = _pixel(pose, _leftShoulder, imageSize);
    final rs = _pixel(pose, _rightShoulder, imageSize);
    final lh = _pixel(pose, _leftHip, imageSize);
    final rh = _pixel(pose, _rightHip, imageSize);
    if (ls == null || rs == null || lh == null || rh == null) {
      return null;
    }
    final s = (ls + rs) / 2;
    final h = (lh + rh) / 2;
    final axis = h - s;
    final length = axis.distance;
    if (length < imageSize.height * 0.05) {
      return null;
    }
    final e = axis / length;
    final n = Offset(-e.dy, e.dx).dx >= 0
        ? Offset(-e.dy, e.dx)
        : Offset(e.dy, -e.dx);

    double halfAcross(Offset a, Offset b) =>
        ((b - a).dx * n.dx + (b - a).dy * n.dy).abs() * 0.5;
    final shoulderHalf = halfAcross(ls, rs);
    final hipHalf = halfAcross(lh, rh);

    final tValues = Float64List(sampleCount);
    final left = Float64List(sampleCount);
    final right = Float64List(sampleCount);
    final hasMask = mask != null &&
        mask.width > 0 &&
        mask.height > 0 &&
        mask.bytes.length >= mask.width * mask.height;

    for (var k = 0; k < sampleCount; k++) {
      final t = centerT - halfSpanT + 2 * halfSpanT * k / (sampleCount - 1);
      tValues[k] = t;
      final c = s + axis * t;
      final estimate = math.max(
        4.0,
        _lerp(0.90 * shoulderHalf, 1.75 * hipHalf, t.clamp(0.0, 1.0)),
      );
      left[k] = hasMask
          ? _searchEdge(mask, imageSize, c, -n, estimate)
          : estimate;
      right[k] = hasMask
          ? _searchEdge(mask, imageSize, c, n, estimate)
          : estimate;
    }
    _smooth(left);
    _smooth(right);

    return BodyWaistGeometry(
      shoulderMid: s,
      hipMid: h,
      tSamples: tValues,
      edgeLeft: left,
      edgeRight: right,
      fromMask: hasMask,
    );
  }

  /// Primeira saída da máscara a partir do eixo. Braço colado ao tronco
  /// continua a máscara; o tecto em volta da estimativa da pose segura-o.
  static double _searchEdge(
    PersonMask mask,
    Size imageSize,
    Offset center,
    Offset dir,
    double estimate,
  ) {
    final floor = 0.45 * estimate;
    final cap = 1.35 * estimate;
    if (_maskAt(mask, imageSize, center) < 0.5) {
      return estimate;
    }
    for (var u = floor; u <= cap; u += 1.0) {
      final p = center + dir * u;
      if (p.dx < 0 ||
          p.dy < 0 ||
          p.dx >= imageSize.width ||
          p.dy >= imageSize.height) {
        return u;
      }
      if (_maskAt(mask, imageSize, p) < 0.5) {
        return u;
      }
    }
    return cap;
  }

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
        for (var j = i - 4; j <= i + 4; j++) {
          sum += current[j.clamp(0, n - 1)];
        }
        next[i] = sum / 9;
      }
      current = next;
    }
    for (var i = 0; i < n; i++) {
      values[i] = current[i];
    }
  }

  static ({Float32List unitDx, Float32List unitDy, Int32List active})
      _packUnits({
    required int width,
    required int height,
    required BodyWaistGeometry geometry,
  }) {
    final s = geometry.shoulderMid;
    final axis = geometry.hipMid - s;
    final length = axis.distance;
    final e = axis / length;
    final n = Offset(-e.dy, e.dx).dx >= 0
        ? Offset(-e.dy, e.dx)
        : Offset(e.dy, -e.dx);

    const t0 = centerT - halfSpanT;
    const t1 = centerT + halfSpanT;
    var maxReach = 0.0;
    for (var k = 0; k < sampleCount; k++) {
      maxReach = math.max(
        maxReach,
        math.max(geometry.edgeLeft[k], geometry.edgeRight[k]) *
            (1 + falloffEdge),
      );
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final t in [t0, t1]) {
      final c = s + axis * t;
      for (final side in [-1.0, 1.0]) {
        final p = c + n * (side * maxReach);
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
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
      final py = y + 0.5 - s.dy;
      for (var x = x0; x <= x1; x++) {
        final px = x + 0.5 - s.dx;
        final t = (px * e.dx + py * e.dy) / length;
        final z = (t - centerT) / halfSpanT;
        if (z <= -1 || z >= 1) {
          continue;
        }
        final band = (1 - z * z) * (1 - z * z);
        final u = px * n.dx + py * n.dy;
        final edge = _edgeAt(
          geometry,
          t,
          u >= 0 ? geometry.edgeRight : geometry.edgeLeft,
        );
        final profile = _profile(u.abs(), edge);
        if (profile <= 1e-6) {
          continue;
        }
        final magnitude = band * profile * (u >= 0 ? 1.0 : -1.0);
        active.add(y * width + x);
        dxs.add(-magnitude * n.dx);
        dys.add(-magnitude * n.dy);
      }
    }
    return (
      unitDx: Float32List.fromList(dxs),
      unitDy: Float32List.fromList(dys),
      active: Int32List.fromList(active),
    );
  }

  /// `|u|` dentro da silhueta; fora, o valor da borda decai por smoothstep.
  static double _profile(double r, double edge) {
    if (r <= edge) {
      return r;
    }
    final falloff = falloffEdge * edge;
    final q = (r - edge) / falloff;
    if (q >= 1) {
      return 0;
    }
    return edge * (1 - q * q * (3 - 2 * q));
  }

  static double _edgeAt(BodyWaistGeometry g, double t, Float64List edges) {
    const last = sampleCount - 1;
    final f = ((t - g.tSamples[0]) / (g.tSamples[last] - g.tSamples[0]) * last)
        .clamp(0.0, last.toDouble());
    final i = f.floor().clamp(0, last - 1);
    final w = f - i;
    return edges[i] * (1 - w) + edges[i + 1] * w;
  }

  static void _scaleActive(BodyWaistFieldRuntime runtime, double alpha) {
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
