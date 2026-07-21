import 'dart:typed_data';

/// Handle opaco para textura GPU.
class TextureHandle {
  final int id;
  final int width;
  final int height;

  const TextureHandle({
    required this.id,
    required this.width,
    required this.height,
  });
}

/// Upload de bytes para textura GPU.
class TextureUpload {
  final Uint8List bytes;
  final int width;
  final int height;

  const TextureUpload({
    required this.bytes,
    required this.width,
    required this.height,
  });
}
