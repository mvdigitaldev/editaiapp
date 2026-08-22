import 'dart:typed_data';

import 'displacement_field.dart';

/// Pedido do renderer V2. Nomes neste library; o `WarpRequest` MLS vive noutro
/// sítio e não se reutiliza (exige `TriMesh`).
class WarpRequest {
  const WarpRequest({
    required this.sourceRgba,
    required this.width,
    required this.height,
    required this.field,
  });

  final Uint8List sourceRgba;
  final int width;
  final int height;
  final DisplacementField field;
}

/// `rgba` é `v2Raw`. Origem inválida preserva o destino e marca as máscaras;
/// não há clamp para a borda da fonte.
class WarpResult {
  WarpResult({
    required this.rgba,
    required this.coverage,
    required this.invalidSource,
  });

  final Uint8List rgba;
  final Uint8List coverage;
  final Uint8List invalidSource;
}

/// Remap backward bilinear isolado. Sem landmarks, máscaras, fill ou V1.
///
/// Convenção: `source = destination - displacement`.
/// Origem válida: `src` no rect fechado `[0, width-1] × [0, height-1]`.
/// Origem inválida: não amostra; RGBA de destino inalterado; `coverage=0`;
/// `invalidSource=1`.
abstract final class BackwardBilinearWarp {
  BackwardBilinearWarp._();

  static WarpResult apply(WarpRequest request) {
    final width = request.width;
    final height = request.height;
    final source = request.sourceRgba;
    final field = request.field;
    final expectedBytes = width * height * 4;
    if (width <= 0 || height <= 0) {
      throw ArgumentError('warp_invalid_size: ${width}x$height');
    }
    if (source.length != expectedBytes) {
      throw StateError(
        'rgba_buffer_size_mismatch: got ${source.length}, expected $expectedBytes',
      );
    }
    if (field.width != width || field.height != height) {
      throw StateError(
        'displacement_field_size_mismatch: field ${field.width}x${field.height} '
        'image ${width}x$height',
      );
    }

    final pixelCount = width * height;
    final rgba = Uint8List.fromList(source);
    final coverage = Uint8List(pixelCount);
    final invalidSource = Uint8List(pixelCount);
    final maxX = width - 1;
    final maxY = height - 1;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final srcX = x - field.dx[i];
        final srcY = y - field.dy[i];
        if (srcX < 0 || srcY < 0 || srcX > maxX || srcY > maxY) {
          invalidSource[i] = 1;
          coverage[i] = 0;
          continue;
        }
        coverage[i] = 255;
        invalidSource[i] = 0;
        _writeBilinear(rgba, source, width, height, i * 4, srcX, srcY);
      }
    }

    return WarpResult(
      rgba: rgba,
      coverage: coverage,
      invalidSource: invalidSource,
    );
  }

  /// Amostra só com origem já validada. Na última coluna/linha os taps
  /// coincidem (bilinear degenerado) — isso não é clamp de coordenada OOB.
  static void _writeBilinear(
    Uint8List dst,
    Uint8List src,
    int width,
    int height,
    int dstIdx,
    double srcX,
    double srcY,
  ) {
    final x0 = srcX.floor();
    final y0 = srcY.floor();
    final x1 = x0 + 1 < width ? x0 + 1 : x0;
    final y1 = y0 + 1 < height ? y0 + 1 : y0;
    final tx = srcX - x0;
    final ty = srcY - y0;
    final i00 = (y0 * width + x0) * 4;
    final i10 = (y0 * width + x1) * 4;
    final i01 = (y1 * width + x0) * 4;
    final i11 = (y1 * width + x1) * 4;
    for (var c = 0; c < 4; c++) {
      final v = _lerp(
        _lerp(src[i00 + c].toDouble(), src[i10 + c].toDouble(), tx),
        _lerp(src[i01 + c].toDouble(), src[i11 + c].toDouble(), tx),
        ty,
      );
      dst[dstIdx + c] = v.round().clamp(0, 255);
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
