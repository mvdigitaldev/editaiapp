import 'dart:typed_data';

/// Entrada de imagem para detecção e processamento (sem dependência de UI).
class ImageSource {
  final Uint8List bytes;
  final int width;
  final int height;
  final int rotation;

  const ImageSource({
    required this.bytes,
    required this.width,
    required this.height,
    this.rotation = 0,
  });
}
