import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'gpu_texture_store.dart';

/// Exporta textura GPU → JPEG/PNG bytes.
class ExportEncoder {
  const ExportEncoder();

  Uint8List encodeJpeg(
    TextureEntry entry, {
    int quality = 90,
  }) {
    final image = img.Image.fromBytes(
      width: entry.width,
      height: entry.height,
      bytes: entry.rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  Uint8List encodePng(TextureEntry entry) {
    final image = img.Image.fromBytes(
      width: entry.width,
      height: entry.height,
      bytes: entry.rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodePng(image));
  }
}
