import 'dart:io';
import 'dart:math' as math;

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
      '${Directory.systemTemp.path}/seamless_test_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 20)}.jpg',
    );
    await file.writeAsBytes(img.encodeJpg(image));
    return file.path;
  }

  group('CollageAspectPreset', () {
    test('canvasSize 16:9 landscape e portrait', () {
      final land = CollageAspectPreset.ratio16x9Landscape.canvasSize(1600);
      expect(land.width, 1600);
      expect(land.height, closeTo(900, 1));

      final port = CollageAspectPreset.ratio16x9Portrait.canvasSize(1600);
      expect(port.height, 1600);
      expect(port.width, closeTo(900, 1));
    });

    test('canvasSize square e 4:3', () {
      final sq = CollageAspectPreset.square.canvasSize(1000);
      expect(sq.width, 1000);
      expect(sq.height, 1000);

      final fourThree = CollageAspectPreset.ratio4x3Landscape.canvasSize(1200);
      expect(fourThree.width, 1200);
      expect(fourThree.height, closeTo(900, 1));
    });
  });

  group('SeamlessBlendCurve', () {
    test('baixa fusão mantém cores puras por mais tempo na junção', () {
      const t = 0.35;
      final lowWeight = SeamlessBlendCurve.blendWeight(t, 0.08);
      final highWeight = SeamlessBlendCurve.blendWeight(t, 1.0);
      expect(lowWeight, lessThan(0.15));
      expect(highWeight, greaterThan(lowWeight));
    });

    test('fusion alta aumenta overlap; 2 fotos em 100% cobrem o eixo', () {
      const axis = 1000;
      final low = SeamlessBlendCurve.overlapPixels(
        axisLength: axis,
        photoCount: 2,
        fusionStrength: 0.0,
      );
      final high = SeamlessBlendCurve.overlapPixels(
        axisLength: axis,
        photoCount: 2,
        fusionStrength: 1.0,
      );
      expect(high, greaterThan(low));
      expect(high, axis);

      final slot = SeamlessBlendCurve.slotSpan(
        axisLength: axis,
        photoCount: 2,
        overlap: high,
      );
      expect(slot, axis);
    });
  });

  group('SeamlessBlendEngine', () {
    test('respeita aspect 9:16 no canvas', () async {
      final paths = [
        await writeTemp(solidImage(400, 600, 255, 0, 0)),
        await writeTemp(solidImage(400, 600, 0, 0, 255)),
      ];

      final result = await engine.blend(
        imagePaths: paths,
        config: const SeamlessBlendConfig(
          aspect: CollageAspectPreset.ratio16x9Portrait,
          fusionStrength: 0.5,
          maxEdge: 900,
        ),
      );

      expect(result.height, 900);
      expect(result.width / result.height, closeTo(9 / 16, 0.02));
    });

    test('respeita aspect 16:9 landscape', () async {
      final paths = [
        await writeTemp(solidImage(600, 400, 255, 0, 0)),
        await writeTemp(solidImage(600, 400, 0, 0, 255)),
      ];

      final result = await engine.blend(
        imagePaths: paths,
        config: const SeamlessBlendConfig(
          aspect: CollageAspectPreset.ratio16x9Landscape,
          fusionStrength: 0.4,
          maxEdge: 1600,
        ),
      );

      expect(result.width, 1600);
      expect(result.width / result.height, closeTo(16 / 9, 0.02));
    });

    test('respeita aspect 1:1', () async {
      final paths = [
        await writeTemp(solidImage(300, 300, 255, 0, 0)),
        await writeTemp(solidImage(300, 300, 0, 255, 0)),
      ];

      final result = await engine.blend(
        imagePaths: paths,
        config: const SeamlessBlendConfig(
          aspect: CollageAspectPreset.square,
          fusionStrength: 0.3,
          maxEdge: 800,
        ),
      );

      expect(result.width, 800);
      expect(result.height, 800);
    });

    test('2 fotos fusion=1 mantém dimensões do preset', () async {
      final paths = [
        await writeTemp(solidImage(200, 200, 255, 0, 0)),
        await writeTemp(solidImage(200, 200, 0, 0, 255)),
      ];

      final result = await engine.blend(
        imagePaths: paths,
        config: const SeamlessBlendConfig(
          aspect: CollageAspectPreset.square,
          fusionStrength: 1.0,
          maxEdge: 500,
        ),
      );

      expect(result.width, 500);
      expect(result.height, 500);

      // Centro deve ser mistura (não vermelho puro nem azul puro).
      final mid = result.image.getPixel(250, 250);
      expect(mid.r, lessThan(250));
      expect(mid.b, lessThan(250));
      expect(mid.r + mid.b, greaterThan(100));
    });

    test('fusionStrength alto aumenta overlap efetivo (slot maior)', () {
      const axis = 900;
      final lowO = SeamlessBlendCurve.overlapPixels(
        axisLength: axis,
        photoCount: 3,
        fusionStrength: 0.0,
      );
      final highO = SeamlessBlendCurve.overlapPixels(
        axisLength: axis,
        photoCount: 3,
        fusionStrength: 1.0,
      );
      final lowSlot = SeamlessBlendCurve.slotSpan(
        axisLength: axis,
        photoCount: 3,
        overlap: lowO,
      );
      final highSlot = SeamlessBlendCurve.slotSpan(
        axisLength: axis,
        photoCount: 3,
        overlap: highO,
      );
      expect(highO, greaterThan(lowO));
      expect(highSlot, greaterThan(lowSlot));
    });

    test('rejeita menos de 2 fotos', () async {
      expect(
        () => engine.blend(imagePaths: []),
        throwsArgumentError,
      );
    });
  });
}
