import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/quality/image_quality_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List gradient({int width = 64, int height = 64, int shift = 0}) {
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        rgba[i] = ((x * 4 + shift) % 256);
        rgba[i + 1] = ((y * 4 + shift) % 256);
        rgba[i + 2] = 128;
        rgba[i + 3] = 255;
      }
    }
    return rgba;
  }

  group('ImageQualityMetrics', () {
    test('imagens idênticas: ssim=1, psnr=inf, dE2000=0', () {
      final a = gradient();
      final b = Uint8List.fromList(a);

      expect(
        ImageQualityMetrics.ssim(a, b, width: 64, height: 64),
        closeTo(1.0, 1e-9),
      );
      expect(ImageQualityMetrics.psnr(a, b), double.infinity);
      expect(ImageQualityMetrics.deltaE2000Mean(a, b), closeTo(0.0, 1e-9));
    });

    test('diferença pequena pontua melhor que diferença grande', () {
      final base = gradient();
      final small = gradient(shift: 2);
      final large = gradient(shift: 40);

      final ssimSmall =
          ImageQualityMetrics.ssim(base, small, width: 64, height: 64);
      final ssimLarge =
          ImageQualityMetrics.ssim(base, large, width: 64, height: 64);
      expect(ssimSmall, greaterThan(ssimLarge));

      expect(
        ImageQualityMetrics.psnr(base, small),
        greaterThan(ImageQualityMetrics.psnr(base, large)),
      );
      expect(
        ImageQualityMetrics.deltaE2000Mean(base, small),
        lessThan(ImageQualityMetrics.deltaE2000Mean(base, large)),
      );
    });

    test('dE2000 conhecido: preto vs branco ~100, cinzas próximos <2', () {
      Uint8List solid(int r, int g, int b) {
        final rgba = Uint8List(4 * 4);
        for (var i = 0; i < rgba.length; i += 4) {
          rgba[i] = r;
          rgba[i + 1] = g;
          rgba[i + 2] = b;
          rgba[i + 3] = 255;
        }
        return rgba;
      }

      final blackWhite = ImageQualityMetrics.deltaE2000Mean(
        solid(0, 0, 0),
        solid(255, 255, 255),
      );
      expect(blackWhite, greaterThan(90));

      final closeGrays = ImageQualityMetrics.deltaE2000Mean(
        solid(128, 128, 128),
        solid(132, 132, 132),
      );
      expect(closeGrays, lessThan(2));
    });

    test('máscara restringe o dE2000 à região marcada', () {
      // Metade esquerda alterada; máscara cobre só a direita (inalterada).
      final a = gradient(width: 8, height: 8);
      final b = Uint8List.fromList(a);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 4; x++) {
          b[(y * 8 + x) * 4] = 255;
        }
      }
      final mask = Uint8List(64);
      for (var y = 0; y < 8; y++) {
        for (var x = 4; x < 8; x++) {
          mask[y * 8 + x] = 255;
        }
      }

      expect(
        ImageQualityMetrics.deltaE2000Mean(a, b, mask: mask),
        closeTo(0.0, 1e-9),
      );
      expect(
        ImageQualityMetrics.deltaE2000Mean(a, b),
        greaterThan(1),
      );
    });
  });
}
