import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../models/pose_landmark.dart';
import '../../../models/pose_result.dart';
import '../displacement_field.dart';

/// Eixo do pescoço medido na pose.
class BodyNeckGeometry {
  const BodyNeckGeometry({
    required this.base,
    required this.up,
    required this.across,
    required this.length,
    required this.halfWidth,
  });

  /// Meio dos ombros; [up] aponta para a boca e [length] é essa distância.
  final Offset base;
  final Offset up;
  final Offset across;
  final double length;
  final double halfWidth;
}

/// Cache do campo unitário. O slider só entra em `α(t)`.
class BodyNeckFieldRuntime {
  PoseResult? pose;
  int width = 0;
  int height = 0;
  Float32List? unitDx;
  Float32List? unitDy;
  Int32List? active;
  DisplacementField? field;
  BodyNeckGeometry? geometry;

  bool matches(PoseResult pose, int width, int height) {
    return identical(this.pose, pose) &&
        this.width == width &&
        this.height == height &&
        unitDx != null &&
        field != null;
  }
}

/// Pescoço (Meitu Linhas do pescoço → Width). Só Δ perpendicular ao eixo
/// ombros→boca.
///
/// Direita do slider afina, esquerda engrossa. A máscara não serve (o cabelo
/// cai ao lado do pescoço): a meia-largura `H` estima-se em `0.17 ×` a
/// largura dos ombros. Dentro, `D = −α · u` comprime para o eixo, como a
/// Cintura; fora, a borda decai em `0.8 H`. Na vertical, em fracções `v` da
/// distância ombros→boca, sobe de 0 a 0.18, fica cheio até 0.50 e acaba em
/// 0.72, antes do queixo: a cara não se mexe.
abstract final class BodyNeckField {
  BodyNeckField._();

  /// `α = gain · t`; a borda do pescoço anda `α · H`.
  static const gain = 0.15;

  static const halfToShoulders = 0.17;
  static const falloffOuter = 0.8;

  static const riseEnd = 0.18;
  static const fullEnd = 0.50;
  static const fallEnd = 0.72;

  static const minVisibility = 0.5;

  static double alphaOf(double t) => gain * t.clamp(-1.0, 1.0);

  static double maxEdgeShift(BodyNeckGeometry geometry) =>
      gain * geometry.halfWidth;

  static bool isAvailable({
    required PoseResult pose,
    required Size imageSize,
  }) =>
      measure(pose: pose, imageSize: imageSize) != null;

  static DisplacementField? build({
    required PoseResult pose,
    required Size imageSize,
    double t = 0,
    BodyNeckFieldRuntime? runtime,
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
    if (runtime != null && runtime.matches(pose, width, height)) {
      _scaleActive(runtime, alpha);
      return runtime.field;
    }
    final geometry = measure(pose: pose, imageSize: imageSize);
    if (geometry == null) {
      return null;
    }
    final packed = _packUnits(width: width, height: height, geometry: geometry);
    final target = runtime ?? BodyNeckFieldRuntime();
    target
      ..pose = pose
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

  /// Ombros e boca (ou nariz) visíveis e dentro da foto, boca acima dos
  /// ombros a pelo menos `0.3 ×` a largura deles.
  static BodyNeckGeometry? measure({
    required PoseResult pose,
    required Size imageSize,
  }) {
    final ls = _pixel(pose, 11, imageSize);
    final rs = _pixel(pose, 12, imageSize);
    if (ls == null || rs == null) {
      return null;
    }
    final shoulderWidth = (ls - rs).distance;
    if (shoulderWidth < 8) {
      return null;
    }
    final ml = _pixel(pose, 9, imageSize);
    final mr = _pixel(pose, 10, imageSize);
    final head =
        ml != null && mr != null ? (ml + mr) / 2 : _pixel(pose, 0, imageSize);
    if (head == null || !_inFrame(head, imageSize)) {
      return null;
    }
    final base = (ls + rs) / 2;
    final toHead = head - base;
    final length = toHead.distance;
    if (length < 0.3 * shoulderWidth || toHead.dy >= 0) {
      return null;
    }
    final up = toHead / length;
    var across = Offset(-up.dy, up.dx);
    if (across.dx < 0) {
      across = -across;
    }
    return BodyNeckGeometry(
      base: base,
      up: up,
      across: across,
      length: length,
      halfWidth: halfToShoulders * shoulderWidth,
    );
  }

  static double _vertical(double v) {
    if (v <= 0 || v >= fallEnd) {
      return 0;
    }
    if (v < riseEnd) {
      return _smoothstep(v / riseEnd);
    }
    if (v > fullEnd) {
      return 1 - _smoothstep((v - fullEnd) / (fallEnd - fullEnd));
    }
    return 1;
  }

  /// `u` dentro do pescoço; fora, o valor da borda decai por smoothstep.
  static double _lateral(double r, double half) {
    if (r <= half) {
      return r;
    }
    final q = (r - half) / (falloffOuter * half);
    if (q >= 1) {
      return 0;
    }
    return half * (1 - _smoothstep(q));
  }

  static ({Float32List unitDx, Float32List unitDy, Int32List active})
      _packUnits({
    required int width,
    required int height,
    required BodyNeckGeometry geometry,
  }) {
    final half = geometry.halfWidth;
    final reach = half * (1 + falloffOuter) + 2;
    final corners = [
      for (final u in [-reach, reach])
        for (final v in [0.0, fallEnd * geometry.length])
          geometry.base + geometry.across * u + geometry.up * v,
    ];
    final x0 = math.max(0, corners.map((p) => p.dx).reduce(math.min).floor());
    final x1 =
        math.min(width - 1, corners.map((p) => p.dx).reduce(math.max).ceil());
    final y0 = math.max(0, corners.map((p) => p.dy).reduce(math.min).floor());
    final y1 =
        math.min(height - 1, corners.map((p) => p.dy).reduce(math.max).ceil());

    final a = geometry.across;
    final up = geometry.up;
    final active = <int>[];
    final dxs = <double>[];
    final dys = <double>[];
    for (var y = y0; y <= y1; y++) {
      final py = y + 0.5 - geometry.base.dy;
      for (var x = x0; x <= x1; x++) {
        final px = x + 0.5 - geometry.base.dx;
        final vertical = _vertical((px * up.dx + py * up.dy) / geometry.length);
        if (vertical <= 0) {
          continue;
        }
        final u = px * a.dx + py * a.dy;
        final lateral = _lateral(u.abs(), half);
        if (lateral <= 0) {
          continue;
        }
        final magnitude = -vertical * lateral * (u >= 0 ? 1.0 : -1.0);
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

  static void _scaleActive(BodyNeckFieldRuntime runtime, double alpha) {
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
