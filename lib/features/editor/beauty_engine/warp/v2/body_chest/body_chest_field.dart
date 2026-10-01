import 'dart:typed_data';
import 'dart:ui';

import '../../../models/pose_landmark.dart';
import '../../../models/pose_result.dart';
import '../displacement_field.dart';

/// Centros e raio do busto medidos na pose.
class BodyChestGeometry {
  const BodyChestGeometry({required this.centers, required this.radius});

  final List<Offset> centers;
  final double radius;
}

/// Cache do campo unitário. O slider só entra em `α(t)`.
class BodyChestFieldRuntime {
  PoseResult? pose;
  int width = 0;
  int height = 0;
  Float32List? unitDx;
  Float32List? unitDy;
  Int32List? active;
  DisplacementField? field;
  BodyChestGeometry? geometry;

  bool matches(PoseResult pose, int width, int height) {
    return identical(this.pose, pose) &&
        this.width == width &&
        this.height == height &&
        unitDx != null &&
        field != null;
  }
}

/// Busto (Meitu Busto → Chest). Escala radial em volta de cada seio.
///
/// Direita do slider aumenta, esquerda diminui. `D = α · w(ρ) · (q − c)`, com
/// `w = (1 − ρ²)²` e `ρ = |q − c| / R`: liso, zero na borda do disco, e a
/// derivada radial fica em `[1 − α, 1 + 0.8 α]`, logo nunca dobra. Os centros
/// saem da pose (o MediaPipe não marca o peito): abaixo da linha dos ombros a
/// `0.27 ×` o tronco, a `±0.27 ×` a largura dos ombros do eixo.
abstract final class BodyChestField {
  BodyChestField._();

  /// `α = gain · t`. No centro, `1 / (1 − α)` ≈ 1.11× no extremo. A largura
  /// da silhueta vem de `BodyTorsoBand.chest`, encadeada antes deste campo.
  static const gain = 0.10;

  /// Raio de cada seio em fracção da largura dos ombros.
  static const radiusToShoulders = 0.30;

  /// Afastamento lateral de cada centro ao eixo, em larguras dos ombros.
  static const lateral = 0.27;

  /// Descida dos centros abaixo da linha dos ombros.
  static const dropToTorso = 0.27;
  static const minDropToShoulders = 0.35;
  static const maxDropToShoulders = 0.55;

  /// Sem anca, o tronco estima-se em ombros.
  static const torsoToShoulders = 1.6;

  /// De perfil os ombros encolhem face ao tronco: sem busto.
  static const minShouldersToTorso = 0.35;

  static const minVisibility = 0.5;

  /// Máximo de `ρ (1 − ρ²)²`, em `ρ² = 1/5`.
  static const _peak = 0.2862;

  static double alphaOf(double t) => gain * t.clamp(-1.0, 1.0);

  static double maxEdgeShift(BodyChestGeometry geometry) =>
      gain * _peak * geometry.radius;

  static bool isAvailable({
    required PoseResult pose,
    required Size imageSize,
  }) =>
      measure(pose: pose, imageSize: imageSize) != null;

  static DisplacementField? build({
    required PoseResult pose,
    required Size imageSize,
    double t = 0,
    BodyChestFieldRuntime? runtime,
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
    final target = runtime ?? BodyChestFieldRuntime();
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

  /// Ombros visíveis e de frente; os dois centros dentro da foto.
  static BodyChestGeometry? measure({
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
    final mid = (ls + rs) / 2;
    final e = (ls - rs) / shoulderWidth;
    var down = Offset(-e.dy, e.dx);
    var torso = torsoToShoulders * shoulderWidth;
    final lh = _pixel(pose, 23, imageSize);
    final rh = _pixel(pose, 24, imageSize);
    if (lh != null && rh != null) {
      final toHips = (lh + rh) / 2 - mid;
      if (toHips.dx * down.dx + toHips.dy * down.dy < 0) {
        down = -down;
      }
      torso = toHips.distance;
      if (shoulderWidth < minShouldersToTorso * torso) {
        return null;
      }
    } else if (down.dy < 0) {
      down = -down;
    }
    final drop = (dropToTorso * torso).clamp(
      minDropToShoulders * shoulderWidth,
      maxDropToShoulders * shoulderWidth,
    );
    final line = mid + down * drop;
    final centers = [
      line + e * (lateral * shoulderWidth),
      line - e * (lateral * shoulderWidth),
    ];
    for (final c in centers) {
      if (c.dx < 0 ||
          c.dy < 0 ||
          c.dx > imageSize.width ||
          c.dy > imageSize.height) {
        return null;
      }
    }
    return BodyChestGeometry(
      centers: centers,
      radius: radiusToShoulders * shoulderWidth,
    );
  }

  static ({Float32List unitDx, Float32List unitDy, Int32List active})
      _packUnits({
    required int width,
    required int height,
    required BodyChestGeometry geometry,
  }) {
    final r = geometry.radius;
    final r2 = r * r;
    final active = <int>[];
    final dxs = <double>[];
    final dys = <double>[];
    final touched = <int, int>{};
    for (final c in geometry.centers) {
      final x0 = (c.dx - r).floor().clamp(0, width - 1);
      final x1 = (c.dx + r).ceil().clamp(0, width - 1);
      final y0 = (c.dy - r).floor().clamp(0, height - 1);
      final y1 = (c.dy + r).ceil().clamp(0, height - 1);
      for (var y = y0; y <= y1; y++) {
        final py = y + 0.5 - c.dy;
        for (var x = x0; x <= x1; x++) {
          final px = x + 0.5 - c.dx;
          final rho2 = (px * px + py * py) / r2;
          if (rho2 >= 1) {
            continue;
          }
          final w = (1 - rho2) * (1 - rho2);
          final dx = w * px;
          final dy = w * py;
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

  static void _scaleActive(BodyChestFieldRuntime runtime, double alpha) {
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
}
