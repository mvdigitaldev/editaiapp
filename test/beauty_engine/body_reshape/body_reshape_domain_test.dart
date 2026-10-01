import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_frame_assets.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/warp_plan.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_joint.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_reshape_request.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/legacy_body_parameter_adapter.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_filter_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Body Reshape V2 domain', () {
    test('represents every independent body region', () {
      expect(
        BodyRegion.values.toSet(),
        containsAll(<BodyRegion>{
          BodyRegion.torso,
          BodyRegion.waist,
          BodyRegion.chest,
          BodyRegion.hip,
          BodyRegion.butt,
          BodyRegion.leftArm,
          BodyRegion.rightArm,
          BodyRegion.leftForearm,
          BodyRegion.rightForearm,
          BodyRegion.leftThigh,
          BodyRegion.rightThigh,
          BodyRegion.leftCalf,
          BodyRegion.rightCalf,
          BodyRegion.neck,
          BodyRegion.shoulders,
        }),
      );
    });

    test('body assets expose semantic joints and confidence', () {
      const leftShoulder = BodyLandmark(
        joint: BodyJoint.leftShoulder,
        normalized: Offset(0.3, 0.25),
        confidence: 0.8,
      );
      const rightShoulder = BodyLandmark(
        joint: BodyJoint.rightShoulder,
        normalized: Offset(0.7, 0.25),
        confidence: 0.6,
      );
      const assets = BodyFrameAssets(
        landmarks: {
          BodyJoint.leftShoulder: leftShoulder,
          BodyJoint.rightShoulder: rightShoulder,
        },
        boundingBox: Rect.fromLTWH(0.2, 0.1, 0.6, 0.8),
        providerId: 'fake',
        capabilities: VisionCapabilities.mediapipePoseOnly,
      );

      expect(
        assets.confidenceFor(
          const [BodyJoint.leftShoulder, BodyJoint.rightShoulder],
        ),
        closeTo(0.7, 1e-9),
      );
      expect(assets.confidenceFor(const [BodyJoint.leftHip]), 0);
    });
  });

  group('LegacyBodyParameterAdapter', () {
    const adapter = LegacyBodyParameterAdapter();

    test('reset body menu produces an identity plan', () {
      final plan = adapter.buildPlan(
        const BodyReshapeRequest(
          imageSize: Size(400, 800),
          parameters: {
            'waist_slim': 0.6,
            'chest_expand': 0.5,
            'height': 1,
          },
        ),
      );

      expect(plan.adjustments, isEmpty);
      expect(plan.isIdentity, isTrue);
      expect(LegacyBodyParameterAdapter.supportedParameterKeys, isEmpty);
      expect(LegacyBodyParameterAdapter.controlSpecs, isEmpty);
      expect(
        LegacyBodyParameterAdapter.requiresV2Mesh(
          const {'chest_expand': 0.1},
        ),
        isFalse,
      );
    });

    test('snake case takes precedence and values are clamped', () {
      expect(
        LegacyBodyParameterAdapter.readParameter(
          const {'waist_slim': 2, 'waistSlim': 0.2},
          'waist_slim',
        ),
        1,
      );
      expect(
        LegacyBodyParameterAdapter.readParameter(
          const {'waistSlim': -1},
          'waist_slim',
        ),
        0,
      );
    });

    test('quality profiles are explicit', () {
      expect(
        WarpQualityProfile.forQuality(WarpQuality.interactive),
        same(WarpQualityProfile.interactive),
      );
      expect(
        WarpQualityProfile.export.refinementIterations,
        greaterThan(WarpQualityProfile.preview.refinementIterations),
      );
    });
  });

  test('legacy pipeline can expose a V2 plan without changing execution', () {
    const pipeline = BodyFilterPipeline();
    final plan = pipeline.createReshapePlan(
      imageSize: const Size(400, 800),
      parameters: const {'shoulder_width': 0.5},
    );

    expect(plan.isIdentity, isTrue);
    expect(plan.qualityProfile, same(WarpQualityProfile.preview));
    expect(plan.adjustments, isEmpty);
    expect(
      pipeline.hasActiveBodyWarp(const {'shoulder_width': 0.5}),
      isFalse,
    );
  });
}
