import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Display P3 usa a mesma curva do sRGB. Converter para sRGB aqui faz o
/// preview cru (sem perfil) coincidir com o JPEG que o Skia desenha.
abstract final class DisplayP3 {
  static bool isDisplayP3(img.IccProfile? profile) {
    if (profile == null) {
      return false;
    }
    final bytes = profile.decompressed();
    final text = String.fromCharCodes(
      bytes.where((b) => b >= 32 && b < 127),
    );
    if (text.contains('sRGB') && !text.contains('P3')) {
      return false;
    }
    return text.contains('P3');
  }

  /// Converte a imagem no lugar. Sem perfil P3, não mexe nos pixels.
  static bool applyToSrgb(img.Image image) {
    if (!isDisplayP3(image.iccProfile)) {
      return false;
    }
    for (final pixel in image) {
      final (r, g, b) = toSrgb(
        pixel.r / 255.0,
        pixel.g / 255.0,
        pixel.b / 255.0,
      );
      pixel
        ..r = r
        ..g = g
        ..b = b;
    }
    image.iccProfile = null;
    return true;
  }

  static (double r, double g, double b) toSrgb(double r, double g, double b) {
    final lr = _linearize(r);
    final lg = _linearize(g);
    final lb = _linearize(b);
    // Display P3 (D65) → XYZ → sRGB linear.
    final x = 0.4865709486482162 * lr +
        0.26566769316909306 * lg +
        0.1982172852343625 * lb;
    final y = 0.2289745640697488 * lr +
        0.6917385218365064 * lg +
        0.079286914093745 * lb;
    final z = 0.04511338185890264 * lg + 1.043944368900976 * lb;
    return (
      _encode(3.2404542 * x - 1.5371385 * y - 0.4985314 * z),
      _encode(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z),
      _encode(0.0556434 * x - 0.2040259 * y + 1.0572252 * z),
    );
  }

  static double _linearize(double channel) {
    if (channel <= 0.04045) {
      return channel / 12.92;
    }
    return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _encode(double linear) {
    final c = linear.clamp(0.0, 1.0);
    final encoded = c <= 0.0031308
        ? 12.92 * c
        : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
    return (encoded.clamp(0.0, 1.0) * 255.0);
  }
}

/// Perfil mínimo cujo texto contém «Display P3», para o teste.
img.IccProfile displayP3ProfileStub() {
  return img.IccProfile(
    'ICC_PROFILE',
    img.IccProfileCompression.none,
    Uint8List.fromList('Display P3'.codeUnits),
  );
}
