import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../body_reshape/protection/rigidity_map.dart';
import '../models/warp_field.dart';

/// Aplica [WarpField] em CPU (preview/testes / fallback GPU).
///
/// Sprint 11: anti-ghosting na borda e atenuação por [RigidityMap].
class WarpCpuRemap {
  const WarpCpuRemap({
    this.fastMode = false,
    this.antiGhosting = true,
    this.rigidityMap,
    this.edgeSoftness = 0.12,
  });

  /// Mantido por compatibilidade; o remap liquify já é rápido.
  final bool fastMode;

  /// Evita amostragem cruzada corpo↔fundo na faixa de máscara intermediária.
  final bool antiGhosting;

  /// Limita deslocamento em fundo estrutural (linhas rígidas).
  final RigidityMap? rigidityMap;

  final double edgeSoftness;

  WarpCpuRemap copyWith({
    bool? fastMode,
    bool? antiGhosting,
    RigidityMap? rigidityMap,
    double? edgeSoftness,
    bool clearRigidityMap = false,
  }) {
    return WarpCpuRemap(
      fastMode: fastMode ?? this.fastMode,
      antiGhosting: antiGhosting ?? this.antiGhosting,
      rigidityMap:
          clearRigidityMap ? null : (rigidityMap ?? this.rigidityMap),
      edgeSoftness: edgeSoftness ?? this.edgeSoftness,
    );
  }

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
    final bounds = field.activePixelBounds();
    final x0 = bounds == null ? 0 : bounds.left.floor().clamp(0, width - 1);
    final y0 = bounds == null ? 0 : bounds.top.floor().clamp(0, height - 1);
    final x1 = bounds == null
        ? width
        : (bounds.right.ceil() + 1).clamp(0, width);
    final y1 = bounds == null
        ? height
        : (bounds.bottom.ceil() + 1).clamp(0, height);

    final rigidity = rigidityMap ?? field.rigidityMap;

    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        _remapPixel(
          rgba: rgba,
          output: output,
          width: width,
          height: height,
          x: x,
          y: y,
          field: field,
          sampleRgba: rgba,
          sampleWidth: width,
          sampleHeight: height,
          rigidity: rigidity,
        );
      }
    }

    return output;
  }

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
    final rigidity = rigidityMap ?? field.rigidityMap;

    for (var y = 0; y < tileHeight; y++) {
      for (var x = 0; x < tileWidth; x++) {
        _remapPixel(
          rgba: tileRgba,
          output: output,
          width: tileWidth,
          height: tileHeight,
          x: x,
          y: y,
          field: field,
          sampleRgba: tileRgba,
          sampleWidth: tileWidth,
          sampleHeight: tileHeight,
          globalX: offsetX + x,
          globalY: offsetY + y,
          fullWidth: fullWidth,
          fullHeight: fullHeight,
          rigidity: rigidity,
        );
      }
    }

    return output;
  }

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
    final rigidity = rigidityMap ?? field.rigidityMap;

    for (var y = 0; y < tileHeight; y++) {
      for (var x = 0; x < tileWidth; x++) {
        _remapPixel(
          rgba: tileRgba,
          output: output,
          width: tileWidth,
          height: tileHeight,
          x: x,
          y: y,
          field: field,
          sampleRgba: fullRgba,
          sampleWidth: fullWidth,
          sampleHeight: fullHeight,
          globalX: offsetX + x,
          globalY: offsetY + y,
          fullWidth: fullWidth,
          fullHeight: fullHeight,
          rigidity: rigidity,
        );
      }
    }

    return output;
  }

  void _remapPixel({
    required Uint8List rgba,
    required Uint8List output,
    required int width,
    required int height,
    required int x,
    required int y,
    required WarpField field,
    required Uint8List sampleRgba,
    required int sampleWidth,
    required int sampleHeight,
    RigidityMap? rigidity,
    int? globalX,
    int? globalY,
    int? fullWidth,
    int? fullHeight,
  }) {
    final gx = globalX ?? x;
    final gy = globalY ?? y;
    final fw = fullWidth ?? width;
    final fh = fullHeight ?? height;

    final normalized = Offset(gx / fw, gy / fh);
    final rawMask = field.sampleMask(normalized);
    if (rawMask <= 0.001) {
      return;
    }

    var mask = rawMask.clamp(0.0, 1.0);
    var disp = field.sampleDisplacement(normalized);

    // Fundo rígido: não curva linhas estruturais.
    if (rigidity != null && !rigidity.isEmpty) {
      final r = rigidity.sampleNormalized(normalized.dx, normalized.dy);
      final soft = (1.0 - r) * (1.0 - r);
      disp = Offset(disp.dx * soft, disp.dy * soft);
      if (r >= 0.55) {
        return;
      }
    }

    // Anti-ghosting: na transição de máscara, reduz o pull e evita double-exposure.
    if (antiGhosting) {
      final soft = edgeSoftness.clamp(0.02, 0.4);
      if (mask < 1.0 - soft) {
        final edgeScale = (mask / (1.0 - soft)).clamp(0.0, 1.0);
        mask *= edgeScale;
        disp = Offset(disp.dx * edgeScale, disp.dy * edgeScale);
      }
    }

    if (mask <= 0.001) {
      return;
    }

    // Liquify-style: atenuar o deslocamento pela máscara.
    // NÃO misturar cores original↔warped — isso cria fantasma (double exposure).
    var srcX = gx + disp.dx * mask;
    var srcY = gy + disp.dy * mask;

    // Clamp anti-ghosting: não amostrar muito longe da silhueta ativa.
    if (antiGhosting) {
      final maxPull = math.max(fw, fh) * 0.08;
      final pull = Offset(srcX - gx, srcY - gy);
      final mag = pull.distance;
      if (mag > maxPull && mag > 1e-6) {
        final s = maxPull / mag;
        srcX = gx + pull.dx * s;
        srcY = gy + pull.dy * s;
      }
    }

    final warped = _sampleBilinear(
      sampleRgba,
      sampleWidth,
      sampleHeight,
      srcX,
      srcY,
    );
    final dstIdx = (y * width + x) * 4;

    output[dstIdx] = warped[0];
    output[dstIdx + 1] = warped[1];
    output[dstIdx + 2] = warped[2];
    output[dstIdx + 3] = rgba[dstIdx + 3];
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
