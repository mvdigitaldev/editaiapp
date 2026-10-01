import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/body_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(400, 800);

  test('body menu has no tools after the reset', () {
    expect(BodyFilterPipeline.bodyWarpParameterKeys, isEmpty);
    expect(BodyFilterPipeline.allFilters, isEmpty);
  });

  test('compose is identity with or without old parameter keys', () {
    final pipeline = const BodyFilterPipeline();
    final pose = _fakeFullBodyPose();
    final mesh = const BodyMeshBuilder().build(pose, imageSize);
    expect(
      pipeline
          .compose(
            mesh: mesh,
            pose: pose,
            imageSize: imageSize,
            parameters: const {},
          )
          .isIdentity,
      isTrue,
    );
    expect(
      pipeline
          .compose(
            mesh: mesh,
            pose: pose,
            imageSize: imageSize,
            parameters: const {'waist_slim': 0.8, 'hip': 0.5},
          )
          .isIdentity,
      isTrue,
    );
    expect(pipeline.hasActiveBodyWarp(const {'waist_slim': 1}), isFalse);
    expect(pipeline.canApply(pose, const {'waist_slim': 1}), isFalse);
  });
}

PoseResult _fakeFullBodyPose({double visibility = 0.9}) {
  final landmarks = List.generate(
    PoseResult.expectedLandmarkCount,
    (index) {
      final y = 0.1 + (index / PoseResult.expectedLandmarkCount) * 0.85;
      return PoseLandmark(
        index: index,
        normalized: Offset(0.35 + (index.isEven ? 0.2 : 0), y),
        visibility: visibility,
      );
    },
  );
  return PoseResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTWH(0.2, 0.05, 0.6, 0.9),
  );
}
