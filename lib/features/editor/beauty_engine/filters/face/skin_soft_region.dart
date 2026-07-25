import 'dart:math' as math;
import 'dart:ui';

/// Elipse normalizada (0..1) com feather nas bordas.
class NormalizedEllipse {
  const NormalizedEllipse({
    required this.center,
    required this.radiusX,
    required this.radiusY,
  });

  final Offset center;
  final double radiusX;
  final double radiusY;

  bool get isValid => radiusX > 0 && radiusY > 0;

  Rect get boundingRect => Rect.fromCenter(
        center: center,
        width: radiusX * 2,
        height: radiusY * 2,
      );

  /// Peso 0..1; [edgeFeather] controla a suavidade da borda.
  double weight(double nx, double ny, {double edgeFeather = 0.03}) {
    if (!isValid) {
      return 0;
    }
    final dx = (nx - center.dx) / radiusX;
    final dy = (ny - center.dy) / radiusY;
    final radial = math.sqrt(dx * dx + dy * dy);
    if (radial >= 1.0 + edgeFeather) {
      return 0;
    }
    if (radial <= 1.0 - edgeFeather) {
      return 1;
    }
    return ((1.0 + edgeFeather - radial) / (2 * edgeFeather)).clamp(0.0, 1.0);
  }
}

/// Peso suave para retângulos normalizados (fallback).
double softRectWeight(
  double nx,
  double ny,
  Rect region, {
  double edgeFeather = 0.025,
}) {
  if (!region.contains(Offset(nx, ny))) {
    return 0;
  }
  final left = nx - region.left;
  final top = ny - region.top;
  final right = region.right - nx;
  final bottom = region.bottom - ny;
  final edgeDistance = math.min(
    math.min(left, right),
    math.min(top, bottom),
  );
  return (edgeDistance / edgeFeather).clamp(0.0, 1.0);
}
