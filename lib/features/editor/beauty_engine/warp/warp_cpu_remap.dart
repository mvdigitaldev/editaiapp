import 'dart:typed_data';
import 'dart:ui';

import '../models/warp_field.dart';

/// Aplica [WarpField] em CPU (preview/testes ate GPURenderer Sprint 07).
class WarpCpuRemap {
  const WarpCpuRemap();

  Uint8List apply({
    required Uint8List rgba,
    required int width,
    required int height,
    required WarpField field,
  }) {
    if (field.isIdentity || rgba.isEmpty) {
      return rgba;
    }

    final expectedBytes = width * height * 4;
    if (rgba.length != expectedBytes) {
      throw StateError(
        'rgba_buffer_size_mismatch: got ${rgba.length}, expected $expectedBytes',
      );
    }

    final output = Uint8List.fromList(rgba);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final normalized = Offset(x / width, y / height);
        final mask = field.sampleMask(normalized);
        if (mask <= 0.001) {
          continue;
        }

        final disp = field.sampleDisplacement(normalized);
        final srcX = x + disp.dx;
        final srcY = y + disp.dy;

        final warped = _sampleBilinear(rgba, width, height, srcX, srcY);
        final dstIdx = (y * width + x) * 4;

        for (var c = 0; c < 4; c++) {
          final original = rgba[dstIdx + c];
          final blended = (original * (1 - mask) + warped[c] * mask).round();
          output[dstIdx + c] = blended.clamp(0, 255);
        }
      }
    }

    return output;
  }

  /// Aplica warp em um tile usando coordenadas normalizadas da imagem completa.
  Uint8List applyRegion({
    required Uint8List tileRgba,
    required int tileWidth,
    required int tileHeight,
    required int offsetX,
    required int offsetY,
    required int fullWidth,
    required int fullHeight,
    required WarpField field,
  }) {
    if (field.isIdentity || tileRgba.isEmpty) {
      return tileRgba;
    }

    final expectedBytes = tileWidth * tileHeight * 4;
    if (tileRgba.length != expectedBytes) {
      throw StateError('tile_rgba_size_mismatch');
    }

    final output = Uint8List.fromList(tileRgba);

    for (var y = 0; y < tileHeight; y++) {
      for (var x = 0; x < tileWidth; x++) {
        final globalX = offsetX + x;
        final globalY = offsetY + y;
        final normalized = Offset(
          globalX / fullWidth,
          globalY / fullHeight,
        );
        final mask = field.sampleMask(normalized);
        if (mask <= 0.001) {
          continue;
        }

        final disp = field.sampleDisplacement(normalized);
        final srcX = globalX + disp.dx;
        final srcY = globalY + disp.dy;

        final warped = _sampleBilinear(tileRgba, tileWidth, tileHeight, srcX - offsetX, srcY - offsetY);
        final dstIdx = (y * tileWidth + x) * 4;

        for (var c = 0; c < 4; c++) {
          final original = tileRgba[dstIdx + c];
          final blended = (original * (1 - mask) + warped[c] * mask).round();
          output[dstIdx + c] = blended.clamp(0, 255);
        }
      }
    }

    return output;
  }

  /// Versão global — amostra deslocamento na imagem completa.
  Uint8List applyGlobal({
    required Uint8List tileRgba,
    required int tileWidth,
    required int tileHeight,
    required int offsetX,
    required int offsetY,
    required int fullWidth,
    required int fullHeight,
    required WarpField field,
    required Uint8List fullRgba,
  }) {
    if (field.isIdentity || tileRgba.isEmpty) {
      return tileRgba;
    }

    final output = Uint8List.fromList(tileRgba);

    for (var y = 0; y < tileHeight; y++) {
      for (var x = 0; x < tileWidth; x++) {
        final globalX = offsetX + x;
        final globalY = offsetY + y;
        final normalized = Offset(
          globalX / fullWidth,
          globalY / fullHeight,
        );
        final mask = field.sampleMask(normalized);
        if (mask <= 0.001) {
          continue;
        }

        final disp = field.sampleDisplacement(normalized);
        final srcX = globalX + disp.dx;
        final srcY = globalY + disp.dy;

        final warped = _sampleBilinear(fullRgba, fullWidth, fullHeight, srcX, srcY);
        final dstIdx = (y * tileWidth + x) * 4;

        for (var c = 0; c < 4; c++) {
          final original = tileRgba[dstIdx + c];
          final blended = (original * (1 - mask) + warped[c] * mask).round();
          output[dstIdx + c] = blended.clamp(0, 255);
        }
      }
    }

    return output;
  }

  List<int> _sampleBilinear(
    Uint8List rgba,
    int width,
    int height,
    double x,
    double y,
  ) {
    if (x < 0 || y < 0 || x >= width - 1 || y >= height - 1) {
      final cx = x.clamp(0, width - 1).round();
      final cy = y.clamp(0, height - 1).round();
      final idx = (cy * width + cx) * 4;
      return [rgba[idx], rgba[idx + 1], rgba[idx + 2], rgba[idx + 3]];
    }

    final x0 = x.floor();
    final y0 = y.floor();
    final tx = x - x0;
    final ty = y - y0;

    final c00 = _pixel(rgba, width, x0, y0);
    final c10 = _pixel(rgba, width, x0 + 1, y0);
    final c01 = _pixel(rgba, width, x0, y0 + 1);
    final c11 = _pixel(rgba, width, x0 + 1, y0 + 1);

    return List.generate(4, (c) {
      final v = _lerp(
        _lerp(c00[c].toDouble(), c10[c].toDouble(), tx),
        _lerp(c01[c].toDouble(), c11[c].toDouble(), tx),
        ty,
      );
      return v.round().clamp(0, 255);
    });
  }

  List<int> _pixel(Uint8List rgba, int width, int x, int y) {
    final idx = (y * width + x) * 4;
    return [rgba[idx], rgba[idx + 1], rgba[idx + 2], rgba[idx + 3]];
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
