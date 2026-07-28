import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_adjustment.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_frame_assets.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_joint.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_part_segmentation.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_reshape_request.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/occlusion_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/warp_plan.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/occlusion/conservative_occlusion_provider.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/occlusion/occlusion_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/occlusion/occlusion_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/occlusion/occlusion_policy.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_filter_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = OcclusionEngine();
  const imageSize = Size(200, 400);

  group('ConservativeOcclusionProvider', () {
    test('infers hand-over-torso occlusion from wrist landmarks', () {
      const provider = ConservativeOcclusionProvider();
      final assets = _assetsWithHandOverWaist();
      final field = provider.inferFromAssets(assets, imageSize: imageSize);

      expect(field, isNotNull);
      expect(field!.presentKinds, contains(OccluderKind.leftHand));
      expect(
        field.overlapRatioInNormalizedRect(
          const Rect.fromLTRB(0.30, 0.34, 0.70, 0.52),
        ),
        greaterThan(0.05),
      );
    });

    test('infers hair occlusion above shoulders', () {
      const provider = ConservativeOcclusionProvider();
      final assets = _assetsWithHair();
      final field = provider.inferFromAssets(assets, imageSize: imageSize);

      expect(field, isNotNull);
      expect(field!.presentKinds, contains(OccluderKind.hair));
    });
  });

  group('OcclusionEngine', () {
    test('hand covering waist reduces or rejects waist_slim with reason', () {
      final occlusion = _handOverWaistField();
      final assets = _baseAssets().copyWith(
        occlusionMap: occlusion.map,
        capabilities: const VisionCapabilities(
          poseLandmarks: true,
          occlusionMap: true,
        ),
      );
      final plan = WarpPlan(
        imageSize: imageSize,
        adjustments: [
          const BodyAdjustment(
            type: BodyAdjustmentType.waistSlim,
            regions: {BodyRegion.waist},
            intensity: 0.9,
            maxIntensity: 0.9,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 0.7,
            minimumConfidence: 0.4,
            occlusionPolicy: BodyOcclusionPolicy.preserveOccluder,
            sourceParameter: 'waist_slim',
          ),
        ],
        qualityProfile: WarpQualityProfile.preview,
      );

      final result = engine.evaluate(
        plan: plan,
        assets: assets,
        occlusionField: occlusion,
      );

      expect(result.hasReductions, isTrue);
      expect(result.decisions, isNotEmpty);
      final decision = result.decisions.first;
      expect(decision.wasReduced || decision.wasRejected, isTrue);
      expect(decision.reason, contains('occluder'));
      expect(decision.occluders, contains(OccluderKind.leftHand));
      if (decision.wasReduced) {
        expect(
          result.plan.adjustmentOfType(BodyAdjustmentType.waistSlim)!
              .occlusionReason,
          isNotNull,
        );
      } else {
        expect(
          result.plan.ignoredParameters,
          contains('waist_slim'),
        );
      }
    });

    test('hair covering shoulders reduces neck/shoulder adjustments', () {
      final occlusion = _hairField();
      final assets = _baseAssets().copyWith(
        occlusionMap: occlusion.map,
        capabilities: const VisionCapabilities(
          poseLandmarks: true,
          occlusionMap: true,
        ),
      );
      final plan = WarpPlan(
        imageSize: imageSize,
        adjustments: [
          const BodyAdjustment(
            type: BodyAdjustmentType.neckSlim,
            regions: {BodyRegion.neck},
            intensity: 0.8,
            maxIntensity: 0.8,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 0.5,
            minimumConfidence: 0.4,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'neck_slim',
          ),
        ],
        qualityProfile: WarpQualityProfile.preview,
      );

      final result = engine.evaluate(
        plan: plan,
        assets: assets,
        occlusionField: occlusion,
      );

      expect(result.decisions.first.wasReduced, isTrue);
      expect(result.decisions.first.reason, contains('hair'));
      expect(
        result.plan.adjustmentOfType(BodyAdjustmentType.neckSlim)!.weight,
        lessThan(1),
      );
    });

    test('declares insufficient evidence reason without silent fallback', () {
      final assets = _baseAssets(); // sem oclusão/partes
      final plan = const BodyFilterPipeline().createReshapePlan(
        imageSize: imageSize,
        parameters: const {'waist_slim': 0.6, 'leg_length': 0.7},
      );

      final result = engine.evaluate(plan: plan, assets: assets);

      expect(result.usedInsufficientEvidenceFallback, isTrue);
      expect(
        result.decisions.every(
          (d) => d.reason == 'occlusion_evidence_insufficient',
        ),
        isTrue,
      );
      expect(result.plan.ignoredParameters, contains('leg_length'));
      expect(
        result.plan.adjustmentOfType(BodyAdjustmentType.waistSlim)?.weight,
        lessThan(1),
      );
    });

    test('part segmentation hand label covers waist ROI', () {
      final parts = _handPartSegmentation();
      final assets = _baseAssets().copyWith(
        partSegmentation: parts,
        capabilities: const VisionCapabilities(
          poseLandmarks: true,
          bodyPartSegmentation: true,
        ),
      );
      final plan = WarpPlan(
        imageSize: imageSize,
        adjustments: [
          const BodyAdjustment(
            type: BodyAdjustmentType.waistSlim,
            regions: {BodyRegion.waist},
            intensity: 1,
            maxIntensity: 1,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 0.7,
            minimumConfidence: 0.3,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'waist_slim',
          ),
        ],
        qualityProfile: WarpQualityProfile.preview,
      );

      final result = engine.evaluate(plan: plan, assets: assets);
      expect(result.hasReductions, isTrue);
      expect(
        result.decisions.first.occluders,
        contains(OccluderKind.leftHand),
      );
    });
  });
}

BodyFrameAssets _baseAssets() {
  BodyLandmark lm(BodyJoint j, double x, double y) => BodyLandmark(
        joint: j,
        normalized: Offset(x, y),
        confidence: 0.95,
      );
  return BodyFrameAssets(
    landmarks: {
      BodyJoint.leftShoulder: lm(BodyJoint.leftShoulder, 0.38, 0.22),
      BodyJoint.rightShoulder: lm(BodyJoint.rightShoulder, 0.62, 0.22),
      BodyJoint.leftHip: lm(BodyJoint.leftHip, 0.42, 0.50),
      BodyJoint.rightHip: lm(BodyJoint.rightHip, 0.58, 0.50),
      BodyJoint.nose: lm(BodyJoint.nose, 0.50, 0.12),
    },
    boundingBox: const Rect.fromLTRB(0.2, 0.1, 0.8, 0.9),
    providerId: 'test',
    capabilities: VisionCapabilities.mediapipePoseOnly,
  );
}

BodyFrameAssets _assetsWithHandOverWaist() {
  BodyLandmark lm(BodyJoint j, double x, double y) => BodyLandmark(
        joint: j,
        normalized: Offset(x, y),
        confidence: 0.95,
      );
  return _baseAssets().copyWith(
    landmarks: {
      ..._baseAssets().landmarks,
      BodyJoint.leftElbow: lm(BodyJoint.leftElbow, 0.40, 0.36),
      BodyJoint.leftWrist: lm(BodyJoint.leftWrist, 0.48, 0.44),
    },
  );
}

BodyFrameAssets _assetsWithHair() {
  BodyLandmark lm(BodyJoint j, double x, double y) => BodyLandmark(
        joint: j,
        normalized: Offset(x, y),
        confidence: 0.95,
      );
  return _baseAssets().copyWith(
    landmarks: {
      ..._baseAssets().landmarks,
      BodyJoint.leftEar: lm(BodyJoint.leftEar, 0.44, 0.11),
      BodyJoint.rightEar: lm(BodyJoint.rightEar, 0.56, 0.11),
    },
  );
}

OcclusionField _handOverWaistField() {
  const w = 40;
  const h = 80;
  final weights = Uint8List(w * h);
  final kinds = Uint8List(w * h);
  final code = OcclusionField.codeFor(OccluderKind.leftHand);
  for (var y = (0.38 * (h - 1)).round(); y <= (0.50 * (h - 1)).round(); y++) {
    for (var x = (0.40 * (w - 1)).round(); x <= (0.58 * (w - 1)).round(); x++) {
      weights[y * w + x] = 230;
      kinds[y * w + x] = code;
    }
  }
  return OcclusionField.fromMap(
    OcclusionMap(
      weights: weights,
      width: w,
      height: h,
      providerId: 'fixture',
      confidence: 0.9,
    ),
    kindCodes: kinds,
    presentKinds: {OccluderKind.leftHand},
  );
}

OcclusionField _hairField() {
  const w = 40;
  const h = 80;
  final weights = Uint8List(w * h);
  final kinds = Uint8List(w * h);
  final code = OcclusionField.codeFor(OccluderKind.hair);
  for (var y = (0.05 * (h - 1)).round(); y <= (0.20 * (h - 1)).round(); y++) {
    for (var x = (0.35 * (w - 1)).round(); x <= (0.65 * (w - 1)).round(); x++) {
      weights[y * w + x] = 210;
      kinds[y * w + x] = code;
    }
  }
  return OcclusionField.fromMap(
    OcclusionMap(
      weights: weights,
      width: w,
      height: h,
      providerId: 'fixture',
      confidence: 0.85,
    ),
    kindCodes: kinds,
    presentKinds: {OccluderKind.hair},
  );
}

BodyPartSegmentation _handPartSegmentation() {
  const w = 40;
  const h = 80;
  final labels = Uint8List(w * h);
  final hand = BodyPartLabel.leftHand.index;
  for (var y = (0.38 * (h - 1)).round(); y <= (0.50 * (h - 1)).round(); y++) {
    for (var x = (0.40 * (w - 1)).round(); x <= (0.58 * (w - 1)).round(); x++) {
      labels[y * w + x] = hand;
    }
  }
  return BodyPartSegmentation(
    labels: labels,
    width: w,
    height: h,
    providerId: 'fixture_parts',
    confidences: const {BodyPartLabel.leftHand: 0.9},
  );
}
