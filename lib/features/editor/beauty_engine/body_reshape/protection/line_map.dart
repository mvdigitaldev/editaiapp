import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'edge_map.dart';

/// Confiança de estruturas retilíneas (sem classificar portas/móveis).
class LineMap {
  final Float32List strength;
  final Float32List direction;
  final int width;
  final int height;
  final Size imageSize;

  const LineMap({
    required this.strength,
    required this.direction,
    required this.width,
    required this.height,
    required this.imageSize,
  }) : assert(width >= 0 && height >= 0);

  bool get isEmpty => strength.isEmpty || width <= 0 || height <= 0;

  bool get hasLines {
    for (final value in strength) {
      if (value > 0.25) {
        return true;
      }
    }
    return false;
  }

  double sampleStrength(double nx, double ny) => _sample(strength, nx, ny);

  double sampleDirection(double nx, double ny) => _sample(direction, nx, ny);

  double sampleAtPixel(int x, int y) {
    if (isEmpty) {
      return 0;
    }
    final sx = x.clamp(0, width - 1);
    final sy = y.clamp(0, height - 1);
    return strength[sy * width + sx];
  }

  double _sample(Float32List values, double nx, double ny) {
    if (isEmpty || values.length != width * height) {
      return 0;
    }
    final fx = (nx.clamp(0.0, 1.0) * (width - 1));
    final fy = (ny.clamp(0.0, 1.0) * (height - 1));
    final x0 = fx.floor().clamp(0, width - 1);
    final y0 = fy.floor().clamp(0, height - 1);
    final x1 = (x0 + 1).clamp(0, width - 1);
    final y1 = (y0 + 1).clamp(0, height - 1);
    final tx = fx - x0;
    final ty = fy - y0;
    final v00 = values[y0 * width + x0];
    final v10 = values[y0 * width + x1];
    final v01 = values[y1 * width + x0];
    final v11 = values[y1 * width + x1];
    final top = v00 + (v10 - v00) * tx;
    final bottom = v01 + (v11 - v01) * tx;
    return top + (bottom - top) * ty;
  }
}

/// Estima linhas por consistência de orientação ao longo da tangente da borda.
class LineMapBuilder {
  const LineMapBuilder({
    this.edgeThreshold = 0.18,
    this.sampleRadius = 4,
    this.orientationToleranceRad = 0.35,
  });

  final double edgeThreshold;
  final int sampleRadius;
  final double orientationToleranceRad;

  LineMap build(EdgeMap edges) {
    if (edges.isEmpty) {
      return LineMap(
        strength: Float32List(0),
        direction: Float32List(0),
        width: 0,
        height: 0,
        imageSize: edges.imageSize,
      );
    }

    final width = edges.width;
    final height = edges.height;
    final strength = Float32List(width * height);
    final direction = Float32List(width * height);

    for (var y = sampleRadius; y < height - sampleRadius; y++) {
      for (var x = sampleRadius; x < width - sampleRadius; x++) {
        final idx = y * width + x;
        final mag = edges.magnitude[idx];
        if (mag < edgeThreshold) {
          continue;
        }

        final orient = edges.orientation[idx];
        // Direção da linha = perpendicular ao gradiente.
        final lineAngle = orient + math.pi * 0.5;
        final tx = math.cos(lineAngle);
        final ty = math.sin(lineAngle);

        var hits = 0;
        var samples = 0;
        for (var s = -sampleRadius; s <= sampleRadius; s++) {
          if (s == 0) {
            continue;
          }
          final sx = (x + tx * s).round();
          final sy = (y + ty * s).round();
          if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
            continue;
          }
          samples++;
          final nIdx = sy * width + sx;
          if (edges.magnitude[nIdx] < edgeThreshold * 0.7) {
            continue;
          }
          final delta = _angleDelta(edges.orientation[nIdx], orient);
          if (delta <= orientationToleranceRad) {
            hits++;
          }
        }

        if (samples == 0) {
          continue;
        }
        final coherence = hits / samples;
        // Exige coerência alta para contar como linha (evita textura/estampa).
        final line = coherence < 0.45
            ? 0.0
            : ((coherence - 0.45) / 0.55).clamp(0.0, 1.0) * mag;
        strength[idx] = line;
        direction[idx] = lineAngle;
      }
    }

    return LineMap(
      strength: strength,
      direction: direction,
      width: width,
      height: height,
      imageSize: edges.imageSize,
    );
  }

  double _angleDelta(double a, double b) {
    var d = (a - b).abs() % math.pi;
    if (d > math.pi * 0.5) {
      d = math.pi - d;
    }
    return d;
  }
}
