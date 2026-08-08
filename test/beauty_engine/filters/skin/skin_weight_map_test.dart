import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin/skin_weight_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_mask_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/face_parts_segmentation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'skin_face_fixture.dart';

void main() {
  const width = 200;
  const height = 260;
  const imageSize = Size(width * 1.0, height * 1.0);

  final face = syntheticFace();
  final geometric = SkinMaskUtils.build(face, imageSize);

  int px(double normalized, int extent) =>
      (normalized * extent).round().clamp(0, extent - 1);

  double weightAtNormalized(SkinWeightMap map, Offset point) {
    return map.weightAt(px(point.dx, width), px(point.dy, height));
  }

  group('SkinWeightMap (fallback geométrico)', () {
    final map = SkinWeightMap.build(
      width: width,
      height: height,
      geometric: geometric,
    );

    test('marca a bochecha como pele', () {
      expect(weightAtNormalized(map, cheekSample), greaterThan(0.5));
      expect(map.fromSegmentation, isFalse);
      expect(map.coverage, greaterThan(0.02));
    });

    test('invariante A1: olhos e boca com peso zero', () {
      expect(weightAtNormalized(map, leftEyeCenter), 0);
      expect(weightAtNormalized(map, rightEyeCenter), 0);
      expect(weightAtNormalized(map, mouthCenter), 0);
    });

    test('invariante A1: fora do rosto (cantos) com peso zero', () {
      for (final corner in const [
        Offset(0.02, 0.02),
        Offset(0.98, 0.02),
        Offset(0.02, 0.98),
        Offset(0.98, 0.98),
      ]) {
        expect(weightAtNormalized(map, corner), 0, reason: '$corner');
      }
    });

    test('transição é suave (sem degrau) na borda do rosto', () {
      // Caminha horizontalmente da bochecha para fora do rosto e verifica
      // que nenhum passo de 1px salta mais de 25% de peso.
      final y = px(cheekSample.dy, height);
      var previous = map.weightAt(px(0.5, width), y);
      for (var x = px(0.5, width) + 1; x < width; x++) {
        final current = map.weightAt(x, y);
        expect((current - previous).abs(), lessThan(0.25),
            reason: 'degrau em x=$x');
        previous = current;
      }
    });
  });

  group('SkinWeightMap (segmentação multiclass)', () {
    FacePartsSegmentation segmentationWithFaceSkin({
      required bool includeSkin,
    }) {
      const segSize = 64;
      final classes = Uint8List(segSize * segSize)
        ..fillRange(0, segSize * segSize, FacePartClass.background.index);
      if (includeSkin) {
        for (var y = 0; y < segSize; y++) {
          for (var x = 0; x < segSize; x++) {
            final nx = (x + 0.5) / segSize;
            final ny = (y + 0.5) / segSize;
            final dx = (nx - faceCenter.dx) / faceRadiusX;
            final dy = (ny - faceCenter.dy) / faceRadiusY;
            if (dx * dx + dy * dy <= 1) {
              classes[y * segSize + x] = FacePartClass.faceSkin.index;
            } else if (ny < faceCenter.dy - faceRadiusY * 0.6) {
              classes[y * segSize + x] = FacePartClass.hair.index;
            }
          }
        }
      }
      return FacePartsSegmentation(
        classes: classes,
        width: segSize,
        height: segSize,
      );
    }

    test('usa a segmentação quando a cobertura é plausível', () {
      final map = SkinWeightMap.build(
        width: width,
        height: height,
        geometric: geometric,
        segmentation: segmentationWithFaceSkin(includeSkin: true),
      );

      expect(map.fromSegmentation, isTrue);
      expect(weightAtNormalized(map, cheekSample), greaterThan(0.5));
      // Proteção dos landmarks continua valendo sobre a segmentação.
      expect(weightAtNormalized(map, leftEyeCenter), 0);
      expect(weightAtNormalized(map, mouthCenter), 0);
    });

    test('cai no fallback geométrico quando a segmentação não tem pele', () {
      final map = SkinWeightMap.build(
        width: width,
        height: height,
        geometric: geometric,
        segmentation: segmentationWithFaceSkin(includeSkin: false),
      );

      expect(map.fromSegmentation, isFalse);
      expect(weightAtNormalized(map, cheekSample), greaterThan(0.5));
    });

    test('cabelo classificado não entra na máscara de pele', () {
      final segmentation = segmentationWithFaceSkin(includeSkin: true);
      final map = SkinWeightMap.build(
        width: width,
        height: height,
        geometric: geometric,
        segmentation: segmentation,
      );

      // Ponto acima do rosto marcado como cabelo na segmentação.
      final hairPoint = Offset(faceCenter.dx, faceCenter.dy - faceRadiusY * 0.95);
      expect(
        segmentation.isClassAt(hairPoint.dx, hairPoint.dy, FacePartClass.hair),
        isFalse,
        reason: 'sanidade: dentro da elipse ainda é pele',
      );
      final aboveFace = Offset(faceCenter.dx, faceCenter.dy - faceRadiusY * 1.4);
      expect(weightAtNormalized(map, aboveFace), 0);
    });
  });

  group('SkinWeightMap degenerado', () {
    test('máscara vazia devolve mapa vazio', () {
      final map = SkinWeightMap.build(
        width: width,
        height: height,
        geometric: const SkinProcessingMask(
          faceBounds: Rect.zero,
          protectedRegions: [],
          cheekRegions: [],
          cheekEllipses: [],
          underEyeRegions: [],
          underEyeEllipses: [],
          eyebrowRegions: [],
          eyelashRegions: [],
          innerMouthRegions: [],
          innerMouthEllipse: null,
          foreheadRegions: [],
          contourRegions: [],
        ),
      );

      expect(map.isEmpty, isTrue);
      expect(map.coverage, 0);
    });
  });
}
