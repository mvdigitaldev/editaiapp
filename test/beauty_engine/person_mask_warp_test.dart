import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/matte_preprocessor.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/person_mask_bridge.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/person_matte.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_warp_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/body_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/models/control_point.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_field_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WarpFieldBuilder person mask', () {
    test('zeros mask and displacement outside person silhouette', () {
      // Silhueta só no centro (2x2 white block in 8x8).
      final bytes = Uint8List(8 * 8);
      for (var y = 3; y <= 4; y++) {
        for (var x = 3; x <= 4; x++) {
          bytes[y * 8 + x] = 255;
        }
      }
      final personMask = PersonMask(bytes: bytes, width: 8, height: 8);
      const imageSize = Size(80, 80);

      final field = const WarpFieldBuilder(
        gridWidth: 9,
        gridHeight: 9,
        maskFeatherPx: 40,
      ).build(
        controlPoints: const [
          ControlPoint(source: Offset(20, 40), target: Offset(30, 40)),
          ControlPoint(source: Offset(60, 40), target: Offset(50, 40)),
          ControlPoint(source: Offset(40, 20), target: Offset(40, 20)),
          ControlPoint(source: Offset(40, 60), target: Offset(40, 60)),
        ],
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: 0.8,
        personMask: personMask,
      );

      // Canto superior esquerdo (fora da pessoa) → mask e displacement 0.
      expect(field.mask[0], equals(0));
      expect(field.displacement[0], equals(0));
      expect(field.displacement[1], equals(0));

      // Centro da grade (pessoa) → mask > 0.
      final centerIdx = 4 * 9 + 4;
      expect(field.mask[centerIdx], greaterThan(0.2));
    });

    test('missing matte still warps with conservative intensity', () {
      const imageSize = Size(80, 80);
      final withMatte = const WarpFieldBuilder(
        gridWidth: 9,
        gridHeight: 9,
        maskFeatherPx: 40,
      ).build(
        controlPoints: const [
          ControlPoint(source: Offset(20, 40), target: Offset(30, 40)),
          ControlPoint(source: Offset(60, 40), target: Offset(50, 40)),
          ControlPoint(source: Offset(40, 20), target: Offset(40, 20)),
          ControlPoint(source: Offset(40, 60), target: Offset(40, 60)),
        ],
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: 0.8,
        personMask: PersonMask(
          bytes: Uint8List.fromList(List.filled(64, 255)),
          width: 8,
          height: 8,
        ),
      );

      final withoutMatte = const WarpFieldBuilder(
        gridWidth: 9,
        gridHeight: 9,
        maskFeatherPx: 40,
      ).build(
        controlPoints: const [
          ControlPoint(source: Offset(20, 40), target: Offset(30, 40)),
          ControlPoint(source: Offset(60, 40), target: Offset(50, 40)),
          ControlPoint(source: Offset(40, 20), target: Offset(40, 20)),
          ControlPoint(source: Offset(40, 60), target: Offset(40, 60)),
        ],
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: 0.8,
      );

      expect(withoutMatte.isIdentity, isFalse);
      final centerIdx = 4 * 9 + 4;
      expect(
        withoutMatte.mask[centerIdx],
        lessThan(withMatte.mask[centerIdx]),
      );
    });
  });

  group('BodyFilterPipeline person mask', () {
    test('compose accepts personMask without error', () {
      final pose = _fakeFullBodyPose();
      const imageSize = Size(400, 800);
      final mesh = const BodyMeshBuilder().build(pose, imageSize);
      final bytes = Uint8List(40 * 80);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = 255;
      }
      final field = const BodyFilterPipeline().compose(
        mesh: mesh,
        pose: pose,
        imageSize: imageSize,
        parameters: const {'body_slim': 0.7},
        personMask: PersonMask(bytes: bytes, width: 40, height: 80),
      );
      expect(field.isIdentity, isFalse);
    });
  });

  group('BodyWarpUtils silhouette', () {
    test('findSilhouetteEdgeX finds left/right borders', () {
      // Pessoa = colunas 10–30 em 40x20.
      final bytes = Uint8List(40 * 20);
      for (var y = 0; y < 20; y++) {
        for (var x = 10; x <= 30; x++) {
          bytes[y * 40 + x] = 255;
        }
      }
      final mask = PersonMask(bytes: bytes, width: 40, height: 20);
      const imageSize = Size(40, 20);

      final left = BodyWarpUtils.findSilhouetteEdgeX(
        mask: mask,
        imageSize: imageSize,
        midX: 20,
        y: 10,
        findLeft: true,
      );
      final right = BodyWarpUtils.findSilhouetteEdgeX(
        mask: mask,
        imageSize: imageSize,
        midX: 20,
        y: 10,
        findLeft: false,
      );
      expect(left, isNotNull);
      expect(right, isNotNull);
      expect(left!, closeTo(10, 1.5));
      expect(right!, closeTo(30, 1.5));
    });

    test('intensityWithMatteGuard reduces when mask is absent', () {
      expect(
        BodyWarpUtils.intensityWithMatteGuard(1),
        BodyWarpUtils.missingMatteIntensityScale,
      );
      expect(
        BodyWarpUtils.intensityWithMatteGuard(
          1,
          personMask: PersonMask(
            bytes: Uint8List.fromList([255]),
            width: 1,
            height: 1,
          ),
        ),
        1,
      );
    });
  });

  group('MattePreprocessor', () {
    test('builds sdf contour bounds and zero weight outside', () {
      final alpha = Uint8List(16 * 16);
      for (var y = 4; y <= 11; y++) {
        for (var x = 4; x <= 11; x++) {
          alpha[y * 16 + x] = 255;
        }
      }
      final matte = PersonMatte(
        alpha: alpha,
        width: 16,
        height: 16,
        providerId: 'test',
      );

      final processed = const MattePreprocessor().process(
        matte,
        imageSize: const Size(160, 160),
      );

      expect(processed.boundingRegion.left, greaterThan(0));
      expect(processed.boundingRegion.right, lessThan(1));
      expect(processed.contour.any((value) => value > 0), isTrue);
      expect(processed.sdf.sampleAtPixel(0, 0), greaterThan(0));
      expect(processed.sdf.sampleAtPixel(8, 8), lessThan(0));
      expect(processed.protection.sampleWarpWeight(0, 0), equals(0));
      expect(processed.protection.sampleWarpWeight(0.5, 0.5), greaterThan(0.5));
      expect(processed.protection.isOutside(0.01, 0.01), isTrue);
    });

    test('person mask bridge preserves dimensions', () {
      final mask = PersonMask(
        bytes: Uint8List.fromList(List.filled(12, 128)),
        width: 3,
        height: 4,
      );
      final matte = mask.toPersonMatte(providerId: 'bridge');
      expect(matte.width, 3);
      expect(matte.height, 4);
      expect(matte.toPersonMask().bytes, same(mask.bytes));
    });
  });
}

PoseResult _fakeFullBodyPose({double visibility = 0.9}) {
  final landmarks = List.generate(33, (index) {
    final isLeft = index.isOdd;
    return PoseLandmark(
      index: index,
      normalized: Offset(isLeft ? 0.35 : 0.65, 0.1 + (index % 11) * 0.07),
      visibility: visibility,
    );
  });
  return PoseResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTWH(0.1, 0.05, 0.8, 0.9),
    isPartial: false,
  );
}
