import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/pose_landmark.dart';
import '../../../models/pose_result.dart';
import '../../../segment/person_mask.dart';
import '../displacement_field.dart';

/// Linha dos ombros medida na imagem.
class BodyShouldersGeometry {
  const BodyShouldersGeometry({
    required this.mid,
    required this.across,
    required this.down,
    required this.shoulderWidth,
    required this.edgeLeft,
    required this.edgeRight,
    required this.fromMask,
  });

  /// Meio dos ombros; [across] aponta para a direita da foto, [down] para a
  /// anca.
  final Offset mid;
  final Offset across;
  final Offset down;
  final double shoulderWidth;

  /// Borda de fora de cada ombro, em px a partir de [mid] ao longo de
  /// [across] (esquerda / direita da foto).
  final double edgeLeft;
  final double edgeRight;
  final bool fromMask;
}

/// Cache do campo unitário. O slider só entra em `α(t)`.
class BodyShouldersFieldRuntime {
  PoseResult? pose;
  PersonMask? mask;
  int width = 0;
  int height = 0;
  Float32List? unitDx;
  Float32List? unitDy;
  Int32List? active;
  DisplacementField? field;
  BodyShouldersGeometry? geometry;

  bool matches(PoseResult pose, PersonMask? mask, int width, int height) {
    return identical(this.pose, pose) &&
        identical(this.mask, mask) &&
        this.width == width &&
        this.height == height &&
        unitDx != null &&
        field != null;
  }
}

/// Ombros (Meitu Linhas do pescoço → Width). Só Δ ao longo da linha dos
/// ombros, para fora do eixo do corpo.
///
/// Direita do slider alarga, esquerda estreita. Com `S` a largura dos ombros
/// e `u` a distância ao eixo: o pescoço (`|u| < 0.15 S`) fica; o campo sobe
/// por smoothstep até ao ponto do ombro (`0.5 S`), mantém-se até à borda da
/// silhueta (máscara) e cai depois dela em `0.35 S`, com o fundo a fechar o
/// espaço. Na vertical vale da base do pescoço até acima do busto. Os
/// declives ficam em `≈ 2 α`, longe de dobrar.
abstract final class BodyShouldersField {
  BodyShouldersField._();

  /// `α = gain · t`; cada ponta anda `α · S / 2`.
  static const gain = 0.07;

  static const neckHalf = 0.15;
  static const tipHalf = 0.50;
  static const outerFall = 0.35;

  /// Faixa vertical, em `S`, a partir da linha dos ombros (positivo = baixo).
  static const topFade = -0.35;
  static const topFull = -0.10;
  static const bottomFull = 0.22;
  static const bottomFade = 0.60;

  /// Borda procurada na máscara até `edgeReach × S` do eixo.
  static const edgeReach = 0.85;

  static const torsoToShoulders = 1.6;
  static const minShouldersToTorso = 0.35;
  static const minVisibility = 0.5;

  static double alphaOf(double t) => gain * t.clamp(-1.0, 1.0);

  static double maxEdgeShift(BodyShouldersGeometry geometry) =>
      gain * tipHalf * geometry.shoulderWidth;

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
    BodyShouldersFieldRuntime? runtime,
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
    final target = runtime ?? BodyShouldersFieldRuntime();
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

  /// Ombros visíveis, dentro da foto e de frente.
  static BodyShouldersGeometry? measure({
    required PoseResult pose,
    required Size imageSize,
    PersonMask? mask,
  }) {
    final ls = _pixel(pose, 11, imageSize);
    final rs = _pixel(pose, 12, imageSize);
    if (ls == null ||
        rs == null ||
        !_inFrame(ls, imageSize) ||
        !_inFrame(rs, imageSize)) {
      return null;
    }
    final shoulderWidth = (ls - rs).distance;
    if (shoulderWidth < 8) {
      return null;
    }
    final mid = (ls + rs) / 2;
    var across = (ls - rs) / shoulderWidth;
    if (across.dx < 0) {
      across = -across;
    }
    var down = Offset(-across.dy, across.dx);
    final lh = _pixel(pose, 23, imageSize);
    final rh = _pixel(pose, 24, imageSize);
    if (lh != null && rh != null) {
      final toHips = (lh + rh) / 2 - mid;
      if (toHips.dx * down.dx + toHips.dy * down.dy < 0) {
        down = -down;
      }
      if (shoulderWidth < minShouldersToTorso * toHips.distance) {
        return null;
      }
    } else if (down.dy < 0) {
      down = -down;
    }

    final hasMask = mask != null &&
        mask.width > 0 &&
        mask.height > 0 &&
        mask.bytes.length >= mask.width * mask.height;
    double edge(double side) {
      final fallback = 0.62 * shoulderWidth;
      if (!hasMask) {
        return fallback;
      }
      final hits = <double>[];
      for (final v in const [0.0, 0.05, 0.10, 0.15, 0.20]) {
        final row = mid + down * (v * shoulderWidth);
        final start = tipHalf * shoulderWidth;
        if (_maskAt(mask, imageSize, row + across * (side * start)) < 0.5) {
          hits.add(start);
          continue;
        }
        var found = edgeReach * shoulderWidth;
        for (var u = start; u <= edgeReach * shoulderWidth; u += 1) {
          final q = row + across * (side * u);
          if (!_inside(imageSize, q) || _maskAt(mask, imageSize, q) < 0.5) {
            found = u;
            break;
          }
        }
        hits.add(found);
      }
      hits.sort();
      return math.max(hits[hits.length ~/ 2], tipHalf * shoulderWidth);
    }

    return BodyShouldersGeometry(
      mid: mid,
      across: across,
      down: down,
      shoulderWidth: shoulderWidth,
      edgeLeft: edge(-1),
      edgeRight: edge(1),
      fromMask: hasMask,
    );
  }

  /// Perfil lateral unitário (sem sinal) a `|u|` do eixo.
  static double _lateral(double r, double s, double edge) {
    final rise = _smoothstep((r - neckHalf * s) / ((tipHalf - neckHalf) * s));
    if (r <= edge) {
      return rise;
    }
    return rise * (1 - _smoothstep((r - edge) / (outerFall * s)));
  }

  static double _vertical(double v, double s) {
    if (v < topFull * s) {
      return _smoothstep((v - topFade * s) / ((topFull - topFade) * s));
    }
    if (v > bottomFull * s) {
      return 1 -
          _smoothstep((v - bottomFull * s) / ((bottomFade - bottomFull) * s));
    }
    return 1;
  }

  static ({Float32List unitDx, Float32List unitDy, Int32List active})
      _packUnits({
    required int width,
    required int height,
    required BodyShouldersGeometry geometry,
  }) {
    final s = geometry.shoulderWidth;
    final amplitude = tipHalf * s;
    final reach =
        math.max(geometry.edgeLeft, geometry.edgeRight) + outerFall * s + 2;
    final corners = [
      for (final u in [-reach, reach])
        for (final v in [topFade * s, bottomFade * s])
          geometry.mid + geometry.across * u + geometry.down * v,
    ];
    final x0 = corners.map((p) => p.dx).reduce(math.min).floor();
    final x1 = corners.map((p) => p.dx).reduce(math.max).ceil();
    final y0 = corners.map((p) => p.dy).reduce(math.min).floor();
    final y1 = corners.map((p) => p.dy).reduce(math.max).ceil();

    final active = <int>[];
    final dxs = <double>[];
    final dys = <double>[];
    final a = geometry.across;
    final d = geometry.down;
    for (var y = math.max(0, y0); y <= math.min(height - 1, y1); y++) {
      final py = y + 0.5 - geometry.mid.dy;
      for (var x = math.max(0, x0); x <= math.min(width - 1, x1); x++) {
        final px = x + 0.5 - geometry.mid.dx;
        final u = px * a.dx + py * a.dy;
        final v = px * d.dx + py * d.dy;
        final vertical = _vertical(v, s);
        if (vertical <= 0) {
          continue;
        }
        final edge = u >= 0 ? geometry.edgeRight : geometry.edgeLeft;
        final lateral = _lateral(u.abs(), s, edge);
        if (lateral <= 0) {
          continue;
        }
        final magnitude =
            amplitude * vertical * lateral * (u >= 0 ? 1.0 : -1.0);
        if (magnitude.abs() < 1e-6) {
          continue;
        }
        active.add(y * width + x);
        dxs.add(magnitude * a.dx);
        dys.add(magnitude * a.dy);
      }
    }
    return (
      unitDx: Float32List.fromList(dxs),
      unitDy: Float32List.fromList(dys),
      active: Int32List.fromList(active),
    );
  }

  static void _scaleActive(BodyShouldersFieldRuntime runtime, double alpha) {
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
}
