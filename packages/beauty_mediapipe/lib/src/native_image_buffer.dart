import 'dart:typed_data';

/// Buffer de imagem para FFI nativo (RGBA ou NV21 conforme plataforma).
class NativeImageBuffer {
  final Uint8List bytes;
  final int width;
  final int height;
  final int rotation;

  const NativeImageBuffer({
    required this.bytes,
    required this.width,
    required this.height,
    this.rotation = 0,
  });
}
