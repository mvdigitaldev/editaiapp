import 'dart:typed_data';
import 'dart:ui';

import '../../models/warp_field.dart';
import 'skin/skin_weight_map.dart';

/// Contexto de amostragem de máscara pós-warp (Sprint 5).
///
/// Após o warp facial, cada pixel de saída exibe conteúdo de outra posição
/// anatômica. As máscaras continuam em coordenadas pré-warp (landmarks);
/// esta classe remapeia a coordenada de saída → fonte para amostrar a máscara.
class MaskSamplingContext {
  const MaskSamplingContext({
    this.tileMapping = const SkinTileMapping(),
    this.faceWarp,
  });

  final SkinTileMapping tileMapping;
  final WarpField? faceWarp;

  /// Coordenada normalizada (0..1) na imagem completa para amostrar máscara.
  Offset maskNormalized({
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    final resolved = tileMapping.resolve(width, height);
    var nx = resolved.normalizedX(x);
    var ny = resolved.normalizedY(y);

    final warp = faceWarp;
    if (warp != null && !warp.isIdentity) {
      final remapped = warp.sourceNormalizedForMask(Offset(nx, ny));
      nx = remapped.dx;
      ny = remapped.dy;
    }
    return Offset(nx, ny);
  }

  double weightAt({
    required Uint8List weights,
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    if (weights.isEmpty) return 0;
    final sample = maskNormalized(x: x, y: y, width: width, height: height);
    final sx = (sample.dx * width).floor().clamp(0, width - 1);
    final sy = (sample.dy * height).floor().clamp(0, height - 1);
    return weights[sy * width + sx] / 255.0;
  }
}
