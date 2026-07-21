import 'dart:math' as math;
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/presets/lut_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/lut_square_table.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/render_target.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LutSquareTable', () {
    test('intensity 0 keeps source unchanged', () {
      final source = _solidRgba(width: 4, height: 4, r: 120, g: 80, b: 200);
      final lutRgba = _imageToRgba(LutSquareTable.buildIdentity());

      final output = LutSquareTable.apply(
        sourceRgba: source,
        width: 4,
        height: 4,
        lutRgba: lutRgba,
        lutWidth: LutSquareTable.dimension,
        lutHeight: LutSquareTable.dimension,
        intensity: 0,
      );

      expect(output, source);
    });

    test('identity LUT at intensity 1 is near-original', () {
      final source = _solidRgba(width: 4, height: 4, r: 120, g: 80, b: 200);
      final lutRgba = _imageToRgba(LutSquareTable.buildIdentity());

      final output = LutSquareTable.apply(
        sourceRgba: source,
        width: 4,
        height: 4,
        lutRgba: lutRgba,
        lutWidth: LutSquareTable.dimension,
        lutHeight: LutSquareTable.dimension,
        intensity: 1,
      );

      expect(_meanAbsDiff(source, output), lessThan(2));
    });

    test('natural LUT changes pixels at intensity 1', () {
      final source = _solidRgba(width: 8, height: 8, r: 100, g: 120, b: 140);
      final lutRgba = _imageToRgba(LutSquareTable.buildNatural());

      final output = LutSquareTable.apply(
        sourceRgba: source,
        width: 8,
        height: 8,
        lutRgba: lutRgba,
        lutWidth: LutSquareTable.dimension,
        lutHeight: LutSquareTable.dimension,
        intensity: 1,
      );

      expect(_meanAbsDiff(source, output), greaterThan(1));
    });
  });

  group('LutEngine parity', () {
    late LutEngine engine;
    late Uint8List naturalLutPng;

    setUp(() {
      engine = LutEngine();
      naturalLutPng = Uint8List.fromList(
        img.encodePng(LutSquareTable.buildNatural()),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
        final key = const StringCodec().decodeMessage(message);
        if (key == LutEngine.bundledNatural) {
          return naturalLutPng.buffer.asByteData();
        }
        return null;
      });
    });

    test('LutEngine.applyToRgba matches PassLut (Manual vs Beauty)', () async {
      final source = _solidRgba(width: 6, height: 6, r: 90, g: 110, b: 130);

      final engineOutput = await engine.applyToRgba(
        sourceRgba: Uint8List.fromList(source),
        width: 6,
        height: 6,
        lutAssetPath: LutEngine.bundledNatural,
        intensity: 0.75,
      );

      final renderer = GpuRendererImpl();
      final input = await renderer.upload(
        TextureUpload(bytes: source, width: 6, height: 6),
      );
      final passOutput = await renderer.runPipeline(
        input: input,
        stages: [
          RenderPipelineStage(
            shaderName: RenderShaders.lutApply,
            uniforms: {
              'lutAssetPath': LutEngine.bundledNatural,
              'intensity': 0.75,
            },
          ),
        ],
      );
      final passPixels = await renderer.readPixels(passOutput);

      expect(_ssim(engineOutput, passPixels), greaterThan(0.98));

      renderer.release(input);
      renderer.release(passOutput);
      renderer.dispose();
    });

    test('intensity 0..1 blends between source and full LUT', () {
      final source = _solidRgba(width: 4, height: 4, r: 100, g: 120, b: 140);
      final lutRgba = _imageToRgba(LutSquareTable.buildNatural());

      final full = LutSquareTable.apply(
        sourceRgba: source,
        width: 4,
        height: 4,
        lutRgba: lutRgba,
        lutWidth: LutSquareTable.dimension,
        lutHeight: LutSquareTable.dimension,
        intensity: 1,
      );
      final half = LutSquareTable.apply(
        sourceRgba: source,
        width: 4,
        height: 4,
        lutRgba: lutRgba,
        lutWidth: LutSquareTable.dimension,
        lutHeight: LutSquareTable.dimension,
        intensity: 0.5,
      );

      expect(_meanAbsDiff(source, half), lessThan(_meanAbsDiff(source, full)));
      expect(_meanAbsDiff(source, half), greaterThan(0));
    });
  });
}

Uint8List _solidRgba({
  required int width,
  required int height,
  required int r,
  required int g,
  required int b,
}) {
  final data = Uint8List(width * height * 4);
  for (var i = 0; i < data.length; i += 4) {
    data[i] = r;
    data[i + 1] = g;
    data[i + 2] = b;
    data[i + 3] = 255;
  }
  return data;
}

Uint8List _imageToRgba(img.Image image) {
  final rgba = Uint8List(image.width * image.height * 4);
  var offset = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      rgba[offset++] = pixel.r.toInt();
      rgba[offset++] = pixel.g.toInt();
      rgba[offset++] = pixel.b.toInt();
      rgba[offset++] = pixel.a.toInt();
    }
  }
  return rgba;
}

double _meanAbsDiff(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}

/// SSIM simplificado por canal RGB (amostra completa).
double _ssim(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  final n = a.length ~/ 4;
  var sum = 0.0;

  for (var channel = 0; channel < 3; channel++) {
    var meanA = 0.0;
    var meanB = 0.0;
    for (var i = channel; i < a.length; i += 4) {
      meanA += a[i];
      meanB += b[i];
    }
    meanA /= n;
    meanB /= n;

    var varA = 0.0;
    var varB = 0.0;
    var cov = 0.0;
    for (var i = channel; i < a.length; i += 4) {
      final da = a[i] - meanA;
      final db = b[i] - meanB;
      varA += da * da;
      varB += db * db;
      cov += da * db;
    }
    varA /= n;
    varB /= n;
    cov /= n;

    const c1 = 6.5025; // (0.01 * 255)^2
    const c2 = 58.5225; // (0.03 * 255)^2
    final ssim = ((2 * meanA * meanB + c1) * (2 * cov + c2)) /
        ((meanA * meanA + meanB * meanB + c1) * (varA + varB + c2));
    sum += ssim.clamp(0.0, 1.0);
  }

  return sum / 3;
}
