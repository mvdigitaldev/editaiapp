import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/mask_factory.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin/skin_weight_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_mask_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/face_parts_segmentation.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/face_parsing_class.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/face_parsing_mapper.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/face_parsing_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/parsing_fallback_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'skin_face_fixture.dart';

void main() {
  const width = 200;
  const height = 260;
  const imageSize = Size(width * 1.0, height * 1.0);

  final face = syntheticFace();
  final geometric = SkinMaskUtils.build(face, imageSize);

  FacePartsSegmentation syntheticSegmentation({required bool includeSkin}) {
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

  Uint8List legacySkinMask() {
    return SkinWeightMap.build(
      width: width,
      height: height,
      geometric: geometric,
      segmentation: syntheticSegmentation(includeSkin: true),
    ).weights;
  }

  FaceParsingResult mappedParsing() {
    return FaceParsingMapper.build(
      width: width,
      height: height,
      parts: syntheticSegmentation(includeSkin: true),
      face: face,
    );
  }

  group('ParsingFallbackPolicy', () {
    test('prefere multiclass quando há cobertura de pele', () {
      final parts = syntheticSegmentation(includeSkin: true);
      expect(
        ParsingFallbackPolicy.resolveSource(parts: parts, face: face),
        FaceParsingSource.mappedMulticlass,
      );
    });

    test('cai para geométrico sem segmentação', () {
      expect(
        ParsingFallbackPolicy.resolveSource(parts: null, face: face),
        FaceParsingSource.geometric,
      );
    });
  });

  group('MaskFactory IoU (Sprint 4)', () {
    test('SkinWeightMap(parsing) alinha com MaskFactory.buildSkin', () {
      final parsing = mappedParsing();
      final fromFactory = MaskFactory().buildSkin(
        parsing: parsing,
        geometric: geometric,
        width: width,
        height: height,
      );
      final fromWeightMap = SkinWeightMap.build(
        width: width,
        height: height,
        geometric: geometric,
        parsing: parsing,
      );

      expect(
        MaskFactory.iou(fromFactory.weights, fromWeightMap.weights),
        greaterThanOrEqualTo(0.99),
      );
    });

    test('pele com feather/proteção: IoU ≥ 0.70 vs pipeline legado', () {
      final parsing = mappedParsing();
      final fromParsing = MaskFactory().buildSkin(
        parsing: parsing,
        geometric: geometric,
        width: width,
        height: height,
      ).weights;

      expect(
        MaskFactory.iou(fromParsing, legacySkinMask()),
        greaterThanOrEqualTo(0.70),
      );
    });

    test('cabelo: IoU ≥ 0.85 vs segmentação multiclass', () {
      final parsing = mappedParsing();
      final factory = MaskFactory();

      final fromParsing = factory.buildRegionMask(
        parsing: parsing,
        include: MaskFactory.hairInclude,
        width: width,
        height: height,
        cacheRegion: FaceParsingClass.hair,
      );

      final legacy = Uint8List(width * height);
      final segmentation = syntheticSegmentation(includeSkin: true);
      for (var y = 0; y < height; y++) {
        final ny = (y + 0.5) / height;
        for (var x = 0; x < width; x++) {
          final nx = (x + 0.5) / width;
          if (segmentation.isClassAt(nx, ny, FacePartClass.hair)) {
            legacy[y * width + x] = 255;
          }
        }
      }

      expect(MaskFactory.iou(fromParsing, legacy), greaterThanOrEqualTo(0.85));
    });

    test('invariante A1: olhos e boca com peso zero via parsing', () {
      final map = MaskFactory().buildSkin(
        parsing: mappedParsing(),
        geometric: geometric,
        width: width,
        height: height,
      );

      int px(double n, int extent) => (n * extent).round().clamp(0, extent - 1);
      double w(Offset p) =>
          map.weightAt(px(p.dx, width), px(p.dy, height));

      expect(w(leftEyeCenter), 0);
      expect(w(rightEyeCenter), 0);
      expect(w(mouthCenter), 0);
    });
  });
}
