import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../performance/adaptive_preview_policy.dart';
import 'image_source.dart';

/// Normaliza uma foto na ENTRADA do Beauty Engine (1× por foto):
///
/// 1. Aplica a orientação EXIF nos pixels ("bake"). Sem isso, os bytes crus
///    decodificados por `img.decodeImage`/pipeline ficam sem rotação enquanto
///    `decodeImageFromList` (Skia) aplica EXIF — landmarks e warp saem
///    deslocados em fotos de câmera em retrato.
/// 2. Aplica o teto de resolução de entrada
///    ([AdaptivePreviewPolicy.inputMaxEdge]) para evitar OOM com fotos de
///    sensores de 50–200MP.
///
/// Quando nada precisa mudar, os bytes originais são retornados intactos
/// (sem re-encode, sem perda). Quando há rotação/downsample, re-encoda
/// preservando o formato (PNG mantém alpha; demais viram JPEG q95).
abstract final class BeautyImageLoader {
  /// Versão assíncrona para uso na UI — roda em isolate via [compute],
  /// porque bake+re-encode de uma foto de 12MP leva ~1s em Dart puro.
  static Future<ImageSource> load(Uint8List bytes) {
    return compute(normalizeSync, bytes);
  }

  @visibleForTesting
  static ImageSource normalizeSync(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('image_decode_failed');
    }

    var normalized = decoded;
    var changed = false;

    final orientation = _exifOrientation(decoded);
    if (orientation != 1) {
      normalized = img.bakeOrientation(normalized);
      changed = true;
    }

    final longest = math.max(normalized.width, normalized.height);
    if (longest > AdaptivePreviewPolicy.inputMaxEdge) {
      final scale = AdaptivePreviewPolicy.inputMaxEdge / longest;
      normalized = img.copyResize(
        normalized,
        width: math.max(1, (normalized.width * scale).round()),
        height: math.max(1, (normalized.height * scale).round()),
        interpolation: img.Interpolation.cubic,
      );
      changed = true;
    }

    if (!changed) {
      return ImageSource(
        bytes: bytes,
        width: normalized.width,
        height: normalized.height,
      );
    }

    final encoded = _isPng(bytes)
        ? img.encodePng(normalized)
        : img.encodeJpg(normalized, quality: 95);
    return ImageSource(
      bytes: Uint8List.fromList(encoded),
      width: normalized.width,
      height: normalized.height,
    );
  }

  static int _exifOrientation(img.Image image) {
    final value = image.exif.imageIfd['Orientation'];
    if (value == null) return 1;
    final orientation = value.toInt();
    return (orientation >= 1 && orientation <= 8) ? orientation : 1;
  }

  static bool _isPng(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
  }
}
