import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Resultado do resize com dimensões para a API.
class ResizeResult {
  const ResizeResult(this.file, this.width, this.height);
  final File file;
  final int width;
  final int height;
}

/// Redimensiona e comprime imagem para upload no fluxo de edição.
/// - Multi-image: max 1.0 MP por imagem, dimensões múltiplas de 16
/// - Single image: max 1.5 MP
/// BFL aceita 64–4096px, múltiplos de 16.
Future<ResizeResult> resizeAndCompressForEdit({
  required String inputPath,
  required num maxMegapixels,
  int jpegQuality = 90,
}) async {
  final bytes = await File(inputPath).readAsBytes();
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw Exception('Não foi possível decodificar a imagem');
  }

  int w = image.width;
  int h = image.height;
  if (w <= 0 || h <= 0) {
    throw Exception('Imagem sem dimensões válidas');
  }

  final maxPixels = maxMegapixels * 1000000;
  int newW = w;
  int newH = h;

  if (w * h > maxPixels) {
    final scale = math.sqrt(maxPixels / (w * h));
    newW = (w * scale).floor();
    newH = (h * scale).floor();
  }

  newW = (newW ~/ 16) * 16;
  newH = (newH ~/ 16) * 16;
  newW = newW.clamp(64, 4096);
  newH = newH.clamp(64, 4096);

  final resized = img.copyResize(image, width: newW, height: newH);
  final jpegBytes = img.encodeJpg(resized, quality: jpegQuality);
  if (jpegBytes.isEmpty) {
    throw Exception('Falha ao comprimir imagem');
  }

  final tempDir = Directory.systemTemp;
  final tempFile = File('${tempDir.path}/edit_input_${DateTime.now().millisecondsSinceEpoch}.jpg');
  await tempFile.writeAsBytes(jpegBytes);
  return ResizeResult(tempFile, newW, newH);
}
