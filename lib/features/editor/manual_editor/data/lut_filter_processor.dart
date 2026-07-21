import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/presets/lut_engine.dart';
import 'package:image/image.dart' as img;

/// Aplica LUT via LutEngine compartilhado (Sprint 09) + color matrix legado.
class LutFilterProcessor {
  LutFilterProcessor({LutEngine? engine}) : _engine = engine ?? LutEngine();

  final LutEngine _engine;

  Future<Uint8List> applyColorMatrixToJpeg({
    required Uint8List jpegBytes,
    required List<double> matrix,
  }) async {
    if (matrix.length != 20) {
      return jpegBytes;
    }

    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) {
      return jpegBytes;
    }

    final filtered = _applyMatrix(decoded, matrix);
    return Uint8List.fromList(img.encodeJpg(filtered, quality: 92));
  }

  Future<Uint8List> applyLutToJpeg({
    required Uint8List jpegBytes,
    required String lutAssetPath,
    double intensity = 1,
    int quality = 92,
  }) {
    return _engine.applyToJpeg(
      jpegBytes: jpegBytes,
      lutAssetPath: lutAssetPath,
      intensity: intensity,
      quality: quality,
    );
  }

  img.Image _applyMatrix(img.Image source, List<double> matrix) {
    final output = img.Image.from(source);
    for (var y = 0; y < output.height; y++) {
      for (var x = 0; x < output.width; x++) {
        final pixel = source.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final a = pixel.a.toDouble();

        final nr = (r * matrix[0] + g * matrix[1] + b * matrix[2] + matrix[4])
            .clamp(0, 255);
        final ng = (r * matrix[5] + g * matrix[6] + b * matrix[7] + matrix[9])
            .clamp(0, 255);
        final nb = (r * matrix[10] + g * matrix[11] + b * matrix[12] + matrix[14])
            .clamp(0, 255);

        output.setPixelRgba(x, y, nr.toInt(), ng.toInt(), nb.toInt(), a.toInt());
      }
    }
    return output;
  }
}
