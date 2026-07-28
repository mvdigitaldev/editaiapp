import 'dart:typed_data';
import 'dart:ui';

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
    test('zeros mask outside person silhouette', () {
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

      // Canto superior esquerdo (fora da pessoa) → mask ~0.
      expect(field.mask[0], lessThan(0.05));

      // Centro da grade (pessoa) → mask > 0.
      final centerIdx = 4 * 9 + 4;
      expect(field.mask[centerIdx], greaterThan(0.2));
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
