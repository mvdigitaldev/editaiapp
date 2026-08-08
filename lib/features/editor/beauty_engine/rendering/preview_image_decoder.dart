import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Converte RGBA bruto em [ui.Image] para preview sem JPEG.
abstract final class PreviewImageDecoder {
  static Future<ui.Image> fromRgba(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
