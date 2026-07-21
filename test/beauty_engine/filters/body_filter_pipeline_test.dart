import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_warp_context.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_warp_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/leg_length.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/head_size.dart';
import 'package:editaiapp/features/editor/beauty_engine/mesh/body_mesh_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(400, 800);

  group('BodyFilterPipeline Sprint 18', () {
    late BodyFilterPipeline pipeline;
    late PoseResult pose;

    setUp(() {
      pipeline = const BodyFilterPipeline();
      pose = _fakeFullBodyPose();
    });

    test('intensity 0 returns identity field', () {
      final mesh = const BodyMeshBuilder().build(pose, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        pose: pose,
        imageSize: imageSize,
        parameters: const {},
      );
      expect(field.isIdentity, isTrue);
    });

    test('waist_slim produces non-identity field with full body', () {
      final mesh = const BodyMeshBuilder().build(pose, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        pose: pose,
        imageSize: imageSize,
        parameters: const {'waist_slim': 0.8},
      );
      expect(field.isIdentity, isFalse);
    });

    test('canApply returns false when pose confidence is low', () {
      final lowVis = _fakeFullBodyPose(visibility: 0.1);
      expect(
        pipeline.canApply(lowVis, const {'waist_slim': 0.5}),
        isFalse,
      );
    });

    test('hasActiveBodyWarp detects body parameters', () {
      expect(pipeline.hasActiveBodyWarp(const {}), isFalse);
      expect(
        pipeline.hasActiveBodyWarp(const {'hip': 0.3}),
        isTrue,
      );
    });

    test('torso filters combine without error', () {
      final mesh = const BodyMeshBuilder().build(pose, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        pose: pose,
        imageSize: imageSize,
        parameters: const {
          'waist_slim': 0.5,
          'hip': 0.4,
          'body_slim': 0.3,
        },
      );
      expect(field.isIdentity, isFalse);
    });
  });

  group('BodyFilterPipeline Sprint 19', () {
    late BodyFilterPipeline pipeline;

    setUp(() {
      pipeline = const BodyFilterPipeline();
    });

    test('leg filters disabled on partial pose', () {
      final partial = _fakeFullBodyPose(isPartial: true);
      expect(
        pipeline.canApply(partial, const {'leg_length': 0.5}),
        isFalse,
      );
      expect(
        pipeline.canApply(partial, const {'leg_slim': 0.5}),
        isFalse,
      );
    });

    test('leg_length clamps targets inside frame', () {
      final pose = _fakeFullBodyPose();
      final mesh = const BodyMeshBuilder().build(pose, imageSize);
      final filter = LegLengthFilter();
      final points = filter.buildControlPoints(
        BodyWarpContext(
          mesh: mesh,
          pose: pose,
          imageSize: imageSize,
          intensity: 1,
          confidenceFactor: 1,
        ),
      );

      for (final cp in points.where((p) => !p.isAnchor)) {
        expect(cp.target.dx, inInclusiveRange(8, imageSize.width - 8));
        expect(cp.target.dy, inInclusiveRange(8, imageSize.height - 8));
        expect(cp.target.dy, lessThanOrEqualTo(imageSize.height * 0.97));
      }
    });

    test('leg filters work on full body pose', () {
      final pose = _fakeFullBodyPose();
      final mesh = const BodyMeshBuilder().build(pose, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        pose: pose,
        imageSize: imageSize,
        parameters: const {
          'leg_length': 0.6,
          'leg_slim': 0.4,
        },
      );
      expect(field.isIdentity, isFalse);
    });
  });

  group('BodyFilterPipeline Sprint 20', () {
    late BodyFilterPipeline pipeline;
    late PoseResult pose;

    setUp(() {
      pipeline = const BodyFilterPipeline();
      pose = _fakeFullBodyPose();
    });

    test('arm neck shoulder filters combine without error', () {
      final mesh = const BodyMeshBuilder().build(pose, imageSize);
      final field = pipeline.compose(
        mesh: mesh,
        pose: pose,
        imageSize: imageSize,
        parameters: const {
          'arm_slim': 0.5,
          'neck_slim': 0.3,
          'shoulder_width': 0.4,
        },
      );
      expect(field.isIdentity, isFalse);
    });

    test('head_size is not in body pipeline', () {
      expect(BodyFilterPipeline.bodyWarpParameterKeys, isNot(contains('head_size')));
      expect(
        pipeline.hasActiveBodyWarp(const {'head_size': 0.8}),
        isFalse,
      );
    });

    test('HeadSizeFilter is a face warp filter only', () {
      expect(HeadSizeFilter().parameterKey, 'head_size');
      expect(BodyWarpUtils.anchorIndices, isNot(contains(1)));
    });
  });
}

PoseResult _fakeFullBodyPose({
  double visibility = 0.9,
  bool isPartial = false,
}) {
  final landmarks = List.generate(
    PoseResult.expectedLandmarkCount,
    (index) {
      final x = 0.45 + (index % 5) * 0.02;
      final y = 0.1 + (index / PoseResult.expectedLandmarkCount) * 0.85;
      return PoseLandmark(
        index: index,
        normalized: Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)),
        visibility: isPartial && index >= 25 ? 0.1 : visibility,
      );
    },
  );

  return PoseResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTWH(0.1, 0.05, 0.8, 0.9),
    isPartial: isPartial,
  );
}
