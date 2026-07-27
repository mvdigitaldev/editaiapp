import 'dart:io';

import 'package:editaiapp/core/utils/seamless_blend_curve.dart';
import 'package:editaiapp/core/utils/seamless_blend_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const engine = SeamlessBlendEngine();

  img.Image solidImage(int width, int height, int r, int g, int b) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(r, g, b));
    return image;
  }

  Future<String> writeTemp(img.Image image) async {
    final file = File(
      '${Directory.systemTemp.path}/seamless_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(img.encodeJpg(image));
    return file.path;
  }

  group('SeamlessBlendCurve', () {
    test('baixa fusão mantém cores puras por mais tempo na junção', () {
      const t = 0.35;
      final lowWeight = SeamlessBlendCurve.blendWeight(t, 0.08);
      final highWeight = SeamlessBlendCurve.blendWeight(t, 1.0);
      expect(lowWeight, lessThan(0.15));
      expect(highWeight, greaterThan(lowWeight));
    });
  });

  group('SeamlessBlendEngine', () {
    test('vertical: 2 imagens sólidas preservam faixas e altura total', () async {
      final red = solidImage(200, 100, 255, 0, 0);
      final blue = solidImage(200, 100, 0, 0, 255);

      final result = await engine.blend(
        imagePaths: [await writeTemp(red), await writeTemp(blue)],
        config: const SeamlessBlendConfig(fusionStrength: 0.0),
      );

      expect(result.width, 200);
      final overlap = SeamlessBlendEngine.overlapPixels(
        crossAxis: 200,
        sizeA: 100,
        sizeB: 100,
      );
      expect(result.height, 200 - overlap);
    });

    test('junções 1→2 e 2→3 com overlap uniforme em 3 fotos', () async {
      final a = solidImage(200, 120, 255, 0, 0);
      final b = solidImage(200, 80, 0, 255, 0);
      final c = solidImage(200, 120, 0, 0, 255);

      final result = await engine.blend(
        imagePaths: [
          await writeTemp(a),
          await writeTemp(b),
          await writeTemp(c),
        ],
        config: const SeamlessBlendConfig(fusionStrength: 0.8),
      );

      const totalRaw = 120 + 80 + 120;
      final overlapEach = (totalRaw - result.height) ~/ 2;
      expect(overlapEach, inInclusiveRange(14, 18));

      final dstY1 = 120 - overlapEach;
      final dstY2 = dstY1 + 80 - overlapEach;

      final above12 = result.image.getPixel(100, dstY1 - 4);
      final below12 = result.image.getPixel(100, dstY1 + overlapEach + 4);
      expect(above12.r, greaterThan(200));
      expect(below12.g, greaterThan(200));

      final above23 = result.image.getPixel(100, dstY2 - 4);
      final below23 = result.image.getPixel(100, dstY2 + overlapEach + 4);
      expect(above23.g, greaterThan(200));
      expect(below23.b, greaterThan(200));

      final midY = dstY1 + overlapEach + (80 - 2 * overlapEach) ~/ 2;
      final mid = result.image.getPixel(100, midY);
      expect(mid.g, greaterThan(200));
    });

    test('fusionStrength não altera altura total', () async {
      final paths = [
        await writeTemp(solidImage(120, 80, 255, 0, 0)),
        await writeTemp(solidImage(120, 80, 0, 0, 255)),
        await writeTemp(solidImage(120, 80, 0, 255, 0)),
      ];

      final low = await engine.blend(
        imagePaths: paths,
        config: const SeamlessBlendConfig(fusionStrength: 0.0),
      );
      final high = await engine.blend(
        imagePaths: paths,
        config: const SeamlessBlendConfig(fusionStrength: 1.0),
      );

      expect(high.height, low.height);
    });

    test('rejeita menos de 2 fotos', () async {
      expect(
        () => engine.blend(imagePaths: []),
        throwsArgumentError,
      );
    });
  });
}
