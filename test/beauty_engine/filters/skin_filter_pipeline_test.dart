import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_mask_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_mesh_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/render_target.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(200, 300);
  late FaceMeshResult face;

  setUp(() {
    face = _fakeFaceMesh();
  });

  group('SkinFilterPipeline Sprint 17', () {
    const pipeline = SkinFilterPipeline();

    test('hasActiveSkin detects skin params', () {
      expect(pipeline.hasActiveSkin(const {}), isFalse);
      expect(
        pipeline.hasActiveSkin(const {'skin_smooth': 0.2}),
        isTrue,
      );
      expect(pipeline.hasActiveSkin(const {'eye_puffy': 0.8}), isTrue);
      expect(pipeline.hasActiveSkin(const {'eye_puffy': 0}), isFalse);
    });

    test('olheiras do tab Olhos entra no mesmo clareamento da pele', () {
      final both = pipeline.darkCircleSides(const {'eye_puffy': 0.9});
      expect(both.left, 0.9);
      expect(both.right, 0.9);

      final fromLegacy = pipeline.darkCircleSides(const {
        'eye_puffy_left': 0.6,
        'eye_puffy_right': 0,
      });
      expect(fromLegacy.left, 0.6);
      expect(fromLegacy.right, 0.6);

      final withSkin = pipeline.darkCircleSides(const {
        'remove_dark_circles': 0.4,
        'eye_puffy': 0.2,
      });
      expect(withSkin.left, 0.4);
      expect(withSkin.right, 0.4);
    });

    test('olheira é um crescente debaixo dos dois olhos e poupa a íris', () {
      final mask = SkinMaskUtils.build(_eyesFace(), imageSize);
      expect(mask.underEyeEllipses.length, 2);
      expect(mask.eyeEllipses.length, 2);

      for (final eye in mask.eyeEllipses) {
        expect(
          SkinMaskUtils.underEyeWeight(eye.center.dx, eye.center.dy, mask),
          lessThan(0.05),
          reason: 'íris em ${eye.center}',
        );
        final insideLid = eye.center.dy + eye.radiusY * 0.85;
        expect(
          SkinMaskUtils.underEyeWeight(eye.center.dx, insideLid, mask),
          lessThan(0.08),
          reason: 'dentro do olho em (${eye.center.dx}, $insideLid)',
        );
        final trough = eye.center.dy + eye.radiusY * 1.55;
        expect(
          SkinMaskUtils.underEyeWeight(eye.center.dx, trough, mask),
          greaterThan(0.40),
          reason: 'sulco em (${eye.center.dx}, $trough)',
        );
      }
    });

    test('skin mask protects eye regions', () {
      final mask = SkinMaskUtils.build(face, imageSize);
      expect(mask.isEmpty, isFalse);
      expect(mask.protectedRegions, isNotEmpty);
      expect(mask.innerMouthEllipse, isNotNull);
      expect(mask.innerMouthEllipse!.isValid, isTrue);

      final eye = mask.protectedRegions.first;
      final center = eye.center;
      expect(SkinMaskUtils.isProtected(center.dx, center.dy, mask), isTrue);
    });

    test('teeth mask uses soft ellipse and color gating', () {
      final mask = SkinMaskUtils.build(face, imageSize);
      final mouthCenter = mask.innerMouthEllipse?.center ??
          mask.innerMouthRegions.first.center;

      expect(
        SkinMaskUtils.teethRegionWeight(
          mouthCenter.dx,
          mouthCenter.dy,
          mask,
        ),
        greaterThan(0),
      );
      expect(
        SkinMaskUtils.teethPixelWeight(220, 215, 210),
        greaterThan(0.5),
      );
      expect(SkinMaskUtils.teethPixelWeight(180, 90, 90), lessThan(0.5));
      expect(
        SkinMaskUtils.teethWhiteningWeight(
          mouthCenter.dx,
          mouthCenter.dy,
          mask,
          220,
          215,
          210,
        ),
        greaterThan(0),
      );
    });

    test('buildPostStages returns skin engine stage', () {
      final stages = pipeline.buildPostStages(
        parameters: const {'skin_smooth': 0.3, 'blush': 0.2},
        face: face,
        imageSize: imageSize,
      );
      expect(stages, hasLength(1));
      expect(stages.first.shaderName, RenderShaders.skinEngine);
    });

    test('skin engine pass runs on CPU backend', () async {
      const width = 120;
      const height = 160;
      final mask = SkinMaskUtils.build(
        face,
        Size(width.toDouble(), height.toDouble()),
      );
      final renderer = GpuRendererImpl();
      final rgba = _solidRgba(width: width, height: height);
      final input = await renderer.upload(
        TextureUpload(bytes: rgba, width: width, height: height),
      );

      final output = await renderer.applyPass(
        input: input,
        shaderName: RenderShaders.skinEngine,
        uniforms: {
          'mask': mask,
          'skin_smooth': 0.4,
          'blush': 0.3,
        },
      );

      expect(output.id, isNot(equals(input.id)));
      renderer.release(input);
      renderer.release(output);
      renderer.dispose();
    });
  });
}

FaceMeshResult _eyesFace() {
  final landmarks = List<FaceLandmark>.generate(
    FaceMeshResult.expectedLandmarkCount,
    (index) => FaceLandmark(
      index: index,
      normalized: const Offset(0.5, 0.55),
      z: 0,
    ),
  );
  void box(Set<int> indices, Rect rect) {
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
      rect.center,
    ];
    var i = 0;
    for (final index in indices) {
      landmarks[index] = FaceLandmark(
        index: index,
        normalized: corners[i % corners.length],
        z: 0,
      );
      i++;
    }
  }

  box(
    {33, 7, 163, 144, 145, 153, 154, 155, 133, 246, 161, 160, 159, 158, 157, 173},
    Rect.fromCenter(center: const Offset(0.38, 0.40), width: 0.10, height: 0.04),
  );
  box(
    {263, 249, 390, 373, 374, 380, 381, 382, 362, 466, 388, 387, 386, 385, 384, 398},
    Rect.fromCenter(center: const Offset(0.62, 0.40), width: 0.10, height: 0.04),
  );

  return FaceMeshResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTWH(40, 40, 120, 180),
    confidence: 0.95,
  );
}

FaceMeshResult _fakeFaceMesh() {
  final landmarks = List.generate(
    FaceMeshResult.expectedLandmarkCount,
    (index) {
      final x = 0.35 + (index % 40) * 0.008;
      final y = 0.25 + (index ~/ 40) * 0.012;
      return FaceLandmark(
        index: index,
        normalized: Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)),
        z: index.isEven ? 0.01 : -0.01,
      );
    },
  );

  return FaceMeshResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTWH(60, 70, 80, 120),
    confidence: 0.95,
  );
}

Uint8List _solidRgba({required int width, required int height}) {
  final data = Uint8List(width * height * 4);
  for (var i = 0; i < data.length; i += 4) {
    data[i] = 180;
    data[i + 1] = 140;
    data[i + 2] = 120;
    data[i + 3] = 255;
  }
  return data;
}
