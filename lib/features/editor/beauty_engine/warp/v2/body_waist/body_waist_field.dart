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

/// Faixa ao longo do eixo ombro→quadril (0 = ombros, 1 = ancas) e ganho.
class BodyTorsoBand {
  const BodyTorsoBand({
    required this.centerT,
    required this.halfSpanT,
    required this.gain,
    this.skipCenterGap = false,
  });

  final double centerT;
  final double halfSpanT;

  /// `α = gain · t`, com sinal: positivo afina à direita do slider.
  final double gain;

  /// Abaixo das ancas o eixo pode cair no vão entre as pernas: a borda é a
  /// saída da silhueta depois de entrar nela, em vez de desistir.
  final bool skipCenterGap;

  double get t0 => centerT - halfSpanT;
  double get t1 => centerT + halfSpanT;

  /// Cintura: direita afina, esquerda alarga.
  static const waist =
      BodyTorsoBand(centerT: 0.66, halfSpanT: 0.30, gain: 0.10);

  /// Quadris (Meitu Curvas → Hips): ancas e topo da coxa; ao contrário da
  /// Cintura, como no Meitu, direita alarga e esquerda afina.
  static const hips = BodyTorsoBand(
    centerT: 1.02,
    halfSpanT: 0.32,
    gain: -0.14,
    skipCenterGap: true,
  );
}

/// Cache do campo unitário. O slider só entra em `α(t)`.
class BodyWaistFieldRuntime {
  PoseResult? pose;
  PersonMask? mask;
  BodyTorsoBand? band;
  int width = 0;
  int height = 0;
  Float32List? unitDx;
  Float32List? unitDy;
  Int32List? active;
  DisplacementField? field;
  BodyWaistGeometry? geometry;

  bool matches(
    PoseResult pose,
    PersonMask? mask,
    BodyTorsoBand band,
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

/// Cintura (Meitu Waist) e Quadris (Meitu Hips): só Δ perpendicular ao eixo
/// do tronco, numa [BodyTorsoBand].
///
/// Cintura: direita do slider afina, esquerda alarga (Quadris ao contrário). Dentro da silhueta o tronco é
/// comprimido em direcção ao eixo, proporcional à distância (`D = −α·u`), para
/// a textura da roupa encolher por igual. Fora, o deslocamento da borda decai
/// por smoothstep numa banda de fundo `falloffEdge × meia-largura`: é o fundo
/// que estica para fechar o espaço, como nos apps.
abstract final class BodyWaistField {
  BodyWaistField._();

  /// Banda de fundo que acompanha a borda, em fracção da meia-largura.
  /// Injectividade: `1 − α · 1.5 / falloffEdge > 0` ⇒ folga 0,73 no extremo.
  static const falloffEdge = 0.55;

  static const sampleCount = 48;
  static const minVisibility = 0.5;

  static const _leftShoulder = 11;
  static const _rightShoulder = 12;
  static const _leftHip = 23;
  static const _rightHip = 24;

  static double alphaOf(double t, [BodyTorsoBand band = BodyTorsoBand.waist]) =>
      band.gain * t.clamp(-1.0, 1.0);

  /// Maior deslocamento da borda possível no extremo do slider (px).
  static double maxEdgeShift(
    BodyWaistGeometry geometry, [
    BodyTorsoBand band = BodyTorsoBand.waist,
  ]) {
    var edge = 0.0;
    for (var k = 0; k < geometry.edgeLeft.length; k++) {
      edge = math.max(
        edge,
        math.max(geometry.edgeLeft[k], geometry.edgeRight[k]),
      );
    }
    return band.gain.abs() * edge;
  }

  /// Campo, ou `null` sem pose fiável / slider em zero.
  static DisplacementField? build({
    required PoseResult pose,
    required Size imageSize,
    PersonMask? mask,
    double t = 0,
    BodyTorsoBand band = BodyTorsoBand.waist,
    BodyWaistFieldRuntime? runtime,
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
    final target = runtime ?? BodyWaistFieldRuntime();
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

  /// Eixo do tronco e bordas da silhueta ao longo da faixa.
  static BodyWaistGeometry? measure({
    required PoseResult pose,
    required Size imageSize,
    PersonMask? mask,
    BodyTorsoBand band = BodyTorsoBand.waist,
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
    final n =
        Offset(-e.dy, e.dx).dx >= 0 ? Offset(-e.dy, e.dx) : Offset(e.dy, -e.dx);

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
      final t = band.t0 + 2 * band.halfSpanT * k / (sampleCount - 1);
      tValues[k] = t;
      final c = s + axis * t;
      final estimate = math.max(
        4.0,
        _lerp(0.90 * shoulderHalf, 1.75 * hipHalf, t.clamp(0.0, 1.0)),
      );
      left[k] = hasMask
          ? _searchEdge(mask, imageSize, c, -n, estimate, band.skipCenterGap)
          : estimate;
      right[k] = hasMask
          ? _searchEdge(mask, imageSize, c, n, estimate, band.skipCenterGap)
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
  /// Com [skipCenterGap], um eixo fora da máscara (vão entre as pernas) anda
  /// até entrar na silhueta e mede a saída a partir daí.
  static double _searchEdge(
    PersonMask mask,
    Size imageSize,
    Offset center,
    Offset dir,
    double estimate,
    bool skipCenterGap,
  ) {
    var floor = 0.45 * estimate;
    final cap = 1.35 * estimate;
    if (_maskAt(mask, imageSize, center) < 0.5) {
      if (!skipCenterGap) {
        return estimate;
      }
      var entry = -1.0;
      for (var u = 1.0; u <= floor; u += 1.0) {
        final p = center + dir * u;
        if (_inside(imageSize, p) && _maskAt(mask, imageSize, p) >= 0.5) {
          entry = u;
          break;
        }
      }
      if (entry < 0) {
        return estimate;
      }
      floor = math.max(floor, entry);
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
    required BodyTorsoBand band,
  }) {
    final s = geometry.shoulderMid;
    final axis = geometry.hipMid - s;
    final length = axis.distance;
    final e = axis / length;
    final n =
        Offset(-e.dy, e.dx).dx >= 0 ? Offset(-e.dy, e.dx) : Offset(e.dy, -e.dx);

    final t0 = band.t0;
    final t1 = band.t1;
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
        final z = (t - band.centerT) / band.halfSpanT;
        if (z <= -1 || z >= 1) {
          continue;
        }
        final weight = (1 - z * z) * (1 - z * z);
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
        final magnitude = weight * profile * (u >= 0 ? 1.0 : -1.0);
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
