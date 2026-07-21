import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_source.dart';
import '../performance/adaptive_preview_policy.dart';

/// Converte JPEG/PNG em RGBA quando necessário para o pipeline GPU.
abstract final class ImageSourceRgba {
  static ImageSource ensureRgba(ImageSource source) {
    final expectedLength = source.width * source.height * 4;
    if (source.bytes.length == expectedLength) {
      return source;
    }

    if (!_looksLikeEncodedImage(source.bytes)) {
      return source;
    }

    final decoded = img.decodeImage(source.bytes);
    if (decoded == null) {
      throw StateError('image_decode_failed');
    }

    final rgba = Uint8List(decoded.width * decoded.height * 4);
    var offset = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        rgba[offset++] = pixel.r.toInt();
        rgba[offset++] = pixel.g.toInt();
        rgba[offset++] = pixel.b.toInt();
        rgba[offset++] = pixel.a.toInt();
      }
    }

    return ImageSource(
      bytes: rgba,
      width: decoded.width,
      height: decoded.height,
      rotation: source.rotation,
    );
  }

  /// Reduz imagem para preview adaptativo (Sprint 25).
  static ImageSource downscaleForPreview(
    ImageSource source, {
    int? maxEdge,
  }) {
    final rgbaSource = ensureRgba(source);
    final edgeLimit = maxEdge ?? AdaptivePreviewPolicy.maxEdgeForSource(rgbaSource);
    final longest = rgbaSource.width > rgbaSource.height
        ? rgbaSource.width
        : rgbaSource.height;
    if (longest <= edgeLimit) {
      return rgbaSource;
    }

    final scale = edgeLimit / longest;
    final targetWidth =
        (rgbaSource.width * scale).round().clamp(1, edgeLimit).toInt();
    final targetHeight =
        (rgbaSource.height * scale).round().clamp(1, edgeLimit).toInt();

    final decoded = img.Image.fromBytes(
      width: rgbaSource.width,
      height: rgbaSource.height,
      bytes: rgbaSource.bytes.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final resized = img.copyResize(
      decoded,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
    );

    final rgba = Uint8List(targetWidth * targetHeight * 4);
    var offset = 0;
    for (var y = 0; y < resized.height; y++) {
      for (var x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        rgba[offset++] = pixel.r.toInt();
        rgba[offset++] = pixel.g.toInt();
        rgba[offset++] = pixel.b.toInt();
        rgba[offset++] = pixel.a.toInt();
      }
    }

    return ImageSource(
      bytes: rgba,
      width: targetWidth,
      height: targetHeight,
      rotation: source.rotation,
    );
  }

  static bool _looksLikeEncodedImage(Uint8List bytes) {
    if (bytes.length < 4) {
      return false;
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return true;
    }
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    return false;
  }
}
