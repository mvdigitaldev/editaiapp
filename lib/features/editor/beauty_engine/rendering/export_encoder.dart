import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../body_reshape/rendering/export_warp.dart';
import '../body_reshape/rendering/native_export_backend.dart';
import 'gpu_texture_store.dart';

/// Exporta textura GPU → JPEG/PNG bytes.
///
/// Preferência: encoder nativo (ImageIO / Bitmap) via [ExportWarp]; fallback
/// `package:image` em Dart.
class ExportEncoder {
  const ExportEncoder({this.exportWarp});

  final ExportWarp? exportWarp;

  Future<Uint8List> encodeJpegAsync(
    TextureEntry entry, {
    int quality = 90,
  }) async {
    final native = await exportWarp?.encodeJpegNative(
      rgba: entry.rgba,
      width: entry.width,
      height: entry.height,
      quality: quality,
    );
    if (native != null && native.isNotEmpty) {
      return native;
    }
    return encodeJpeg(entry, quality: quality);
  }

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

/// Encode JPEG direto de RGBA (útil para backends nativos / testes).
extension ExportEncoderNative on NativeExportBackend {
  Future<Uint8List?> tryEncodeJpeg({
    required Uint8List rgba,
    required int width,
    required int height,
    int quality = 90,
  }) {
    return encodeJpeg(
      rgba: rgba,
      width: width,
      height: height,
      quality: quality,
    );
  }
}
