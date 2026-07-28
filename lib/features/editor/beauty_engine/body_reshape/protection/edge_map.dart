import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Magnitude e orientação de bordas (Sobel) no domínio da imagem/mapa.
class EdgeMap {
  final Float32List magnitude;
  final Float32List orientation;
  final int width;
  final int height;
  final Size imageSize;

  const EdgeMap({
    required this.magnitude,
    required this.orientation,
    required this.width,
    required this.height,
    required this.imageSize,
  }) : assert(width >= 0 && height >= 0);

  bool get isEmpty => magnitude.isEmpty || width <= 0 || height <= 0;

  double sampleMagnitude(double nx, double ny) =>
      _sample(magnitude, nx, ny);

  double sampleOrientation(double nx, double ny) =>
      _sample(orientation, nx, ny);

  double sampleAtPixel(int x, int y) {
    if (isEmpty) {
      return 0;
    }
    final sx = x.clamp(0, width - 1);
    final sy = y.clamp(0, height - 1);
    return magnitude[sy * width + sx];
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

/// Extrai [EdgeMap] a partir de luminância ou RGBA.
class EdgeMapBuilder {
  const EdgeMapBuilder({
    this.normalizePercentile = 0.95,
  });

  /// Percentil usado para normalizar a magnitude (robustez a outliers).
  final double normalizePercentile;

  EdgeMap buildFromLuminance({
    required Float32List luminance,
    required int width,
    required int height,
    required Size imageSize,
  }) {
    if (width <= 0 || height <= 0 || luminance.length != width * height) {
      return EdgeMap(
        magnitude: Float32List(0),
        orientation: Float32List(0),
        width: 0,
        height: 0,
        imageSize: imageSize,
      );
    }

    final magnitude = Float32List(width * height);
    final orientation = Float32List(width * height);
    var maxMag = 1e-6;

    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final gx = _sample(luminance, width, x + 1, y - 1) +
            2 * _sample(luminance, width, x + 1, y) +
            _sample(luminance, width, x + 1, y + 1) -
            _sample(luminance, width, x - 1, y - 1) -
            2 * _sample(luminance, width, x - 1, y) -
            _sample(luminance, width, x - 1, y + 1);
        final gy = _sample(luminance, width, x - 1, y + 1) +
            2 * _sample(luminance, width, x, y + 1) +
            _sample(luminance, width, x + 1, y + 1) -
            _sample(luminance, width, x - 1, y - 1) -
            2 * _sample(luminance, width, x, y - 1) -
            _sample(luminance, width, x + 1, y - 1);
        final mag = math.sqrt(gx * gx + gy * gy);
        final idx = y * width + x;
        magnitude[idx] = mag;
        orientation[idx] = math.atan2(gy, gx);
        if (mag > maxMag) {
          maxMag = mag;
        }
      }
    }

    final scale = 1.0 / math.max(maxMag * normalizePercentile, 1e-6);
    for (var i = 0; i < magnitude.length; i++) {
      magnitude[i] = (magnitude[i] * scale).clamp(0.0, 1.0);
    }

    return EdgeMap(
      magnitude: magnitude,
      orientation: orientation,
      width: width,
      height: height,
      imageSize: imageSize,
    );
  }

  EdgeMap buildFromRgba({
    required Uint8List rgba,
    required int width,
    required int height,
    required Size imageSize,
  }) {
    final luminance = Float32List(width * height);
    for (var i = 0; i < width * height; i++) {
      final o = i * 4;
      final r = rgba[o] / 255.0;
      final g = rgba[o + 1] / 255.0;
      final b = rgba[o + 2] / 255.0;
      luminance[i] = 0.299 * r + 0.587 * g + 0.114 * b;
    }
    return buildFromLuminance(
      luminance: luminance,
      width: width,
      height: height,
      imageSize: imageSize,
    );
  }

  double _sample(Float32List values, int width, int x, int y) {
    return values[y * width + x];
  }
}
