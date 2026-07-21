import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Square 512×512 LUT (8×8 grid, 64³) — mesmo layout do `lookup.frag`
/// do flutter_image_filters.
abstract final class LutSquareTable {
  static const int dimension = 512;

  /// Gera LUT identidade 512×512 (PNG-ready RGBA).
  static img.Image buildIdentity({
    ColorTransform transform = _identityTransform,
  }) {
    final image = img.Image(width: dimension, height: dimension);

    for (var blue = 0; blue < 64; blue++) {
      final quadY = blue ~/ 8;
      final quadX = blue % 8;

      for (var green = 0; green < 64; green++) {
        for (var red = 0; red < 64; red++) {
          final rf = red / 63.0;
          final gf = green / 63.0;
          final bf = blue / 63.0;
          final mapped = transform(rf, gf, bf);

          final x = quadX * 64 + red;
          final y = quadY * 64 + green;
          image.setPixelRgba(
            x,
            y,
            (mapped.$1 * 255).round().clamp(0, 255),
            (mapped.$2 * 255).round().clamp(0, 255),
            (mapped.$3 * 255).round().clamp(0, 255),
            255,
          );
        }
      }
    }

    return image;
  }

  static (double, double, double) _identityTransform(
    double r,
    double g,
    double b,
  ) =>
      (r, g, b);

  /// LUT “Natural” — leve aquecimento.
  static img.Image buildNatural() {
    return buildIdentity(
      transform: (r, g, b) {
        final warmR = (r * 1.06 + 0.02).clamp(0.0, 1.0);
        final warmG = (g * 1.02).clamp(0.0, 1.0);
        final warmB = (b * 0.94).clamp(0.0, 1.0);
        return (warmR, warmG, warmB);
      },
    );
  }

  /// LUT “Cinema” — teal nas sombras, laranja nos highlights.
  static img.Image buildCinemaTealOrange() {
    return buildIdentity(
      transform: (r, g, b) {
        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        final shadow = (1 - luma).clamp(0.0, 1.0);
        final highlight = luma.clamp(0.0, 1.0);

        var nr = r + highlight * 0.12 - shadow * 0.06;
        var ng = g + highlight * 0.04 - shadow * 0.02;
        var nb = b + shadow * 0.14 - highlight * 0.08;

        return (nr.clamp(0.0, 1.0), ng.clamp(0.0, 1.0), nb.clamp(0.0, 1.0));
      },
    );
  }

  /// Aplica LUT square em buffer RGBA (CPU — paridade com shader GPU).
  static Uint8List apply({
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required Uint8List lutRgba,
    required int lutWidth,
    required int lutHeight,
    required double intensity,
  }) {
    if (intensity <= 0) {
      return Uint8List.fromList(sourceRgba);
    }

    final clampedIntensity = intensity.clamp(0.0, 1.0);
    final output = Uint8List.fromList(sourceRgba);

    for (var i = 0; i < output.length; i += 4) {
      final sr = output[i] / 255.0;
      final sg = output[i + 1] / 255.0;
      final sb = output[i + 2] / 255.0;
      final sa = output[i + 3];

      final mapped = _lookupFrom2DTexture(
        lutRgba: lutRgba,
        lutWidth: lutWidth,
        lutHeight: lutHeight,
        r: sr.clamp(0.0, 1.0),
        g: sg.clamp(0.0, 1.0),
        b: sb.clamp(0.0, 1.0),
      );

      output[i] = _lerpChannel(sr, mapped.$1, clampedIntensity);
      output[i + 1] = _lerpChannel(sg, mapped.$2, clampedIntensity);
      output[i + 2] = _lerpChannel(sb, mapped.$3, clampedIntensity);
      output[i + 3] = sa;
    }

    return output;
  }

  static int _lerpChannel(double source, double mapped, double intensity) {
    return (((source * (1 - intensity)) + (mapped * intensity)) * 255)
        .round()
        .clamp(0, 255);
  }

  static (double, double, double) _lookupFrom2DTexture({
    required Uint8List lutRgba,
    required int lutWidth,
    required int lutHeight,
    required double r,
    required double g,
    required double b,
  }) {
    final blueColor = b * 63.0;

    final quad1Y = (blueColor.floor() / 8).floor();
    final quad1X = blueColor.floor() - quad1Y * 8;
    final quad2Y = (blueColor.ceil() / 8).floor();
    final quad2X = blueColor.ceil() - quad2Y * 8;

    final texPos1X =
        (quad1X * 0.125) + 0.5 / 512 + ((0.125 - 1.0 / 512) * r);
    final texPos1Y =
        (quad1Y * 0.125) + 0.5 / 512 + ((0.125 - 1.0 / 512) * g);
    final texPos2X =
        (quad2X * 0.125) + 0.5 / 512 + ((0.125 - 1.0 / 512) * r);
    final texPos2Y =
        (quad2Y * 0.125) + 0.5 / 512 + ((0.125 - 1.0 / 512) * g);

    final color1 = _sampleBilinear(
      lutRgba,
      lutWidth,
      lutHeight,
      texPos1X,
      texPos1Y,
    );
    final color2 = _sampleBilinear(
      lutRgba,
      lutWidth,
      lutHeight,
      texPos2X,
      texPos2Y,
    );

    final fractBlue = blueColor - blueColor.floor();
    return (
      _lerpDouble(color1.$1, color2.$1, fractBlue),
      _lerpDouble(color1.$2, color2.$2, fractBlue),
      _lerpDouble(color1.$3, color2.$3, fractBlue),
    );
  }

  static (double, double, double) _sampleBilinear(
    Uint8List rgba,
    int width,
    int height,
    double u,
    double v,
  ) {
    final x = (u * width).clamp(0.0, width - 1.001);
    final y = (v * height).clamp(0.0, height - 1.001);

    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = math.min(x0 + 1, width - 1);
    final y1 = math.min(y0 + 1, height - 1);

    final fx = x - x0;
    final fy = y - y0;

    final c00 = _readRgb(rgba, width, x0, y0);
    final c10 = _readRgb(rgba, width, x1, y0);
    final c01 = _readRgb(rgba, width, x0, y1);
    final c11 = _readRgb(rgba, width, x1, y1);

    final top = (
      _lerpDouble(c00.$1, c10.$1, fx),
      _lerpDouble(c00.$2, c10.$2, fx),
      _lerpDouble(c00.$3, c10.$3, fx),
    );
    final bottom = (
      _lerpDouble(c01.$1, c11.$1, fx),
      _lerpDouble(c01.$2, c11.$2, fx),
      _lerpDouble(c01.$3, c11.$3, fx),
    );

    return (
      _lerpDouble(top.$1, bottom.$1, fy),
      _lerpDouble(top.$2, bottom.$2, fy),
      _lerpDouble(top.$3, bottom.$3, fy),
    );
  }

  static (double, double, double) _readRgb(
    Uint8List rgba,
    int width,
    int x,
    int y,
  ) {
    final index = ((y * width) + x) * 4;
    return (
      rgba[index] / 255.0,
      rgba[index + 1] / 255.0,
      rgba[index + 2] / 255.0,
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  /// Decodifica PNG LUT para RGBA flat.
  static ({Uint8List rgba, int width, int height}) decodeLutPng(
    Uint8List pngBytes,
  ) {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) {
      throw StateError('LUT PNG inválido');
    }

    final rgba = Uint8List(decoded.width * decoded.height * 4);
    var offset = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        rgba[offset++] = pixel.r.toInt();
        rgba[offset++] = pixel.g.toInt();
        rgba[offset++] = pixel.b.toInt();
        rgba[offset++] = pixel.a.toInt();
      }
    }

    return (rgba: rgba, width: decoded.width, height: decoded.height);
  }
}

typedef ColorTransform = (double, double, double) Function(
  double r,
  double g,
  double b,
);
