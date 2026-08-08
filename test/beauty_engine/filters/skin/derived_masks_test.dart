import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/derived_masks.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/mask_sampling.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin/skin_weight_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_mask_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_tone_calibration.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/face_parsing_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'skin_face_fixture.dart';

void main() {
  const width = 120;
  const height = 160;
  const imageSize = Size(width * 1.0, height * 1.0);

  Uint8List syntheticRgba() {
    final out = Uint8List(width * height * 4);
    for (var p = 0; p < width * height; p++) {
      final i = p * 4;
      out[i] = 210;
      out[i + 1] = 170;
      out[i + 2] = 140;
      out[i + 3] = 255;
    }
    return out;
  }

  group('SkinToneCalibration', () {
    test('amostra tom nas bochechas', () {
      final face = syntheticFace();
      final geometric = SkinMaskUtils.build(face, imageSize);
      final skin = SkinWeightMap.build(
        width: width,
        height: height,
        geometric: geometric,
      );
      final tone = SkinToneCalibration.sample(
        rgba: syntheticRgba(),
        skinWeights: skin.weights,
        geometric: geometric,
        width: width,
        height: height,
      );
      expect(tone.isValid, isTrue);
      expect(tone.shineKnee, greaterThan(0));
    });
  });

  group('DerivedMaskBuilder', () {
    test('olheiras v2 intersectam pele', () {
      final face = syntheticFace();
      final geometric = SkinMaskUtils.build(face, imageSize);
      final skin = SkinWeightMap.build(
        width: width,
        height: height,
        geometric: geometric,
      );
      final parsing = FaceParsingMapper.build(
        width: width,
        height: height,
        face: face,
      );
      final bundle = DerivedMaskBuilder.build(
        rgba: syntheticRgba(),
        width: width,
        height: height,
        geometric: geometric,
        skinWeights: skin.weights,
        parsing: parsing,
      );

      var underEyeHits = 0;
      for (final w in bundle.underEye) {
        if (w > 0) underEyeHits++;
      }
      expect(underEyeHits, greaterThan(0));
    });

    test('dentes respeitam região interna da boca', () {
      final face = syntheticFace();
      final geometric = SkinMaskUtils.build(face, imageSize);
      final skin = SkinWeightMap.build(
        width: width,
        height: height,
        geometric: geometric,
      );
      final rgba = syntheticRgba();
      for (var y = 0; y < height; y++) {
        final ny = (y + 0.5) / height;
        for (var x = 0; x < width; x++) {
          final nx = (x + 0.5) / width;
          if (SkinMaskUtils.teethRegionWeight(nx, ny, geometric) > 0.5) {
            final i = (y * width + x) * 4;
            rgba[i] = 240;
            rgba[i + 1] = 235;
            rgba[i + 2] = 228;
          }
        }
      }
      final bundle = DerivedMaskBuilder.build(
        rgba: rgba,
        width: width,
        height: height,
        geometric: geometric,
        skinWeights: skin.weights,
      );

      final weightAtMouth = bundle.teeth[
        (mouthCenter.dy * height).floor().clamp(0, height - 1) * width +
            (mouthCenter.dx * width).floor().clamp(0, width - 1)
      ];
      expect(weightAtMouth, greaterThan(0));
    });
  });

  group('MaskSamplingContext pós-warp', () {
    test('faceWarp desloca amostragem da máscara', () {
      final disp = Float32List(32);
      for (var c = 0; c < 16; c++) {
        disp[c * 2] = 18;
        disp[c * 2 + 1] = -10;
      }
      final field = WarpField(
        gridWidth: 4,
        gridHeight: 4,
        displacement: disp,
        mask: Float32List(16)..fillRange(0, 16, 1),
        imageSize: imageSize,
        region: MeshRegion.faceOval,
        intensity: 1,
      );

      const plain = MaskSamplingContext();
      final warped = MaskSamplingContext(faceWarp: field);
      final a = plain.maskNormalized(x: 60, y: 80, width: width, height: height);
      final b = warped.maskNormalized(x: 60, y: 80, width: width, height: height);
      expect((a - b).distance, greaterThan(0.001));
    });
  });
}
