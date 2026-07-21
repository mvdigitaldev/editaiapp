import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'lut_filter_processor.dart';

/// Resultado do pipeline de exportação manual.
class ExportPipelineResult {
  const ExportPipelineResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.mimeType,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String mimeType;
}

/// Normaliza bytes exportados pelo pro_image_editor antes do upload.
class ExportPipeline {
  ExportPipeline({LutFilterProcessor? lutProcessor})
      : _lutProcessor = lutProcessor ?? LutFilterProcessor();

  final LutFilterProcessor _lutProcessor;

  Future<ExportPipelineResult> processEditedJpeg(
    Uint8List editedJpeg, {
    List<double>? colorMatrix,
    String? lutAssetPath,
    double lutIntensity = 1,
    int quality = 92,
  }) async {
    var output = editedJpeg;

    if (lutAssetPath != null &&
        lutAssetPath.isNotEmpty &&
        lutIntensity > 0) {
      output = await _lutProcessor.applyLutToJpeg(
        jpegBytes: output,
        lutAssetPath: lutAssetPath,
        intensity: lutIntensity,
        quality: quality,
      );
    }

    if (colorMatrix != null && colorMatrix.length == 20) {
      output = await _lutProcessor.applyColorMatrixToJpeg(
        jpegBytes: output,
        matrix: colorMatrix,
      );
    }

    final decoded = img.decodeImage(output);
    if (decoded == null) {
      throw StateError('Não foi possível decodificar a imagem exportada');
    }

    final normalized = Uint8List.fromList(
      img.encodeJpg(decoded, quality: quality),
    );

    return ExportPipelineResult(
      bytes: normalized,
      width: decoded.width,
      height: decoded.height,
      mimeType: 'image/jpeg',
    );
  }

  Future<ExportPipelineResult> processOriginalJpeg(
    Uint8List originalBytes, {
    int quality = 90,
  }) async {
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      throw StateError('Não foi possível decodificar a imagem original');
    }

    final normalized = Uint8List.fromList(
      img.encodeJpg(decoded, quality: quality),
    );

    return ExportPipelineResult(
      bytes: normalized,
      width: decoded.width,
      height: decoded.height,
      mimeType: 'image/jpeg',
    );
  }
}
