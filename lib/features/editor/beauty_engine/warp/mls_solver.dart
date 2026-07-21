import 'dart:ui';

import 'models/control_point.dart';

/// Solver MLS rigido 2D (Schaefer et al.).
abstract class MlsSolver {
  const MlsSolver._();

  static const _epsilon = 1e-8;
  static const _inverseIterations = 6;

  /// MLS rigido: mapeia ponto [x] no espaco source → target.
  static Offset forward(List<ControlPoint> points, Offset x) {
    if (points.isEmpty) {
      return x;
    }

    final weights = List<double>.filled(points.length, 0);
    var sumW = 0.0;
    var pStarX = 0.0;
    var pStarY = 0.0;
    var qStarX = 0.0;
    var qStarY = 0.0;

    for (var i = 0; i < points.length; i++) {
      final dx = x.dx - points[i].source.dx;
      final dy = x.dy - points[i].source.dy;
      final w = 1.0 / (dx * dx + dy * dy + _epsilon);
      weights[i] = w;
      sumW += w;
      pStarX += w * points[i].source.dx;
      pStarY += w * points[i].source.dy;
      qStarX += w * points[i].target.dx;
      qStarY += w * points[i].target.dy;
    }

    pStarX /= sumW;
    pStarY /= sumW;
    qStarX /= sumW;
    qStarY /= sumW;

    var a = 0.0;
    var b = 0.0;
    var mu = 0.0;

    for (var i = 0; i < points.length; i++) {
      final w = weights[i];
      final pPrimeX = points[i].source.dx - pStarX;
      final pPrimeY = points[i].source.dy - pStarY;
      final qPrimeX = points[i].target.dx - qStarX;
      final qPrimeY = points[i].target.dy - qStarY;

      mu += w * (pPrimeX * pPrimeX + pPrimeY * pPrimeY);
      a += w * (pPrimeX * qPrimeX + pPrimeY * qPrimeY);
      b += w * (pPrimeX * qPrimeY - pPrimeY * qPrimeX);
    }

    if (mu < _epsilon) {
      return x;
    }

    final xPrimeX = x.dx - pStarX;
    final xPrimeY = x.dy - pStarY;

    return Offset(
      qStarX + (a * xPrimeX - b * xPrimeY) / mu,
      qStarY + (b * xPrimeX + a * xPrimeY) / mu,
    );
  }

  /// Inverso aproximado: encontra source tal que forward(source) ≈ [target].
  static Offset inverse(List<ControlPoint> points, Offset target) {
    if (points.isEmpty) {
      return target;
    }

    var guess = target;
    for (var i = 0; i < _inverseIterations; i++) {
      final mapped = forward(points, guess);
      guess = Offset(
        guess.dx + target.dx - mapped.dx,
        guess.dy + target.dy - mapped.dy,
      );
    }
    return guess;
  }
}
