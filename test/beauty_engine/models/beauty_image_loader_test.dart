import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/models/beauty_image_loader.dart';
import 'package:editaiapp/features/editor/beauty_engine/performance/adaptive_preview_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('BeautyImageLoader.normalizeSync', () {
    test('aplica orientação EXIF nos pixels (bake) e corrige dimensões', () {
      // 100x60 com metade esquerda vermelha e direita azul.
      final image = img.Image(width: 100, height: 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 100; x++) {
          image.setPixelRgb(x, y, x < 50 ? 255 : 0, 0, x < 50 ? 0 : 255);
        }
      }
      // Orientação 6 = girar 90° horário para exibir.
      image.exif.imageIfd['Orientation'] = 6;
      final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 95));

      final source = BeautyImageLoader.normalizeSync(jpeg);

      // Dimensões trocam: 100x60 vira 60x100.
      expect(source.width, 60);
      expect(source.height, 100);

      final decoded = img.decodeImage(source.bytes)!;
      expect(decoded.width, 60);
      expect(decoded.height, 100);
      // Após girar 90° horário, a metade esquerda (vermelha) vira o topo.
      final top = decoded.getPixel(30, 10);
      final bottom = decoded.getPixel(30, 90);
      expect(top.r, greaterThan(150));
      expect(top.b, lessThan(100));
      expect(bottom.b, greaterThan(150));
      expect(bottom.r, lessThan(100));
      // A orientação não pode sobrar nos bytes normalizados (dupla rotação).
      final orientation = decoded.exif.imageIfd['Orientation']?.toInt() ?? 1;
      expect(orientation, 1);
    });

    test('reduz fotos acima do teto de resolução de entrada', () {
      final image = img.Image(width: 5000, height: 100);
      final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 90));

      final source = BeautyImageLoader.normalizeSync(jpeg);

      expect(source.width, AdaptivePreviewPolicy.inputMaxEdge);
      expect(source.height, (100 * 4096 / 5000).round());
    });

    test('retorna bytes originais intactos quando nada precisa mudar', () {
      final image = img.Image(width: 320, height: 240);
      img.fill(image, color: img.ColorRgb8(10, 200, 30));
      final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 90));

      final source = BeautyImageLoader.normalizeSync(jpeg);

      expect(source.width, 320);
      expect(source.height, 240);
      expect(identical(source.bytes, jpeg), isTrue);
    });

    test('preserva PNG (e alpha) no re-encode', () {
      final image = img.Image(width: 5000, height: 50, numChannels: 4);
      final png = Uint8List.fromList(img.encodePng(image));

      final source = BeautyImageLoader.normalizeSync(png);

      expect(source.width, AdaptivePreviewPolicy.inputMaxEdge);
      // Continua PNG.
      expect(source.bytes[0], 0x89);
      expect(source.bytes[1], 0x50);
    });
  });
}
