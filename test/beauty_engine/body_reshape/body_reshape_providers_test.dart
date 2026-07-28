import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_adjustment.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_frame_assets.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_joint.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/person_matte.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/warp_plan.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/body_vision_coordinator.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/fake_vision_providers.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/mediapipe_body_joint_mapper.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/mediapipe_body_mesh_provider.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/mediapipe_person_matte_provider.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/unavailable_vision_providers.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capability_gate.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_landmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/pose_result.dart';
import 'package:editaiapp/features/editor/beauty_engine/pose/pose_detector.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaPipeBodyJointMapper', () {
    const mapper = MediaPipeBodyJointMapper();

    test('maps PoseResult indices to semantic BodyJoints', () {
      final assets = mapper.fromPoseResult(_fakePoseResult());

      expect(assets, isNotNull);
      expect(assets!.landmarks.length, 33);
      expect(
        assets.landmark(BodyJoint.leftShoulder)?.confidence,
        greaterThanOrEqualTo(0.5),
      );
      expect(assets.providerId, MediaPipeBodyJointMapper.providerId);
      expect(assets.capabilities.poseLandmarks, isTrue);
    });

    test('returns null when primary joints are invisible', () {
      expect(
        mapper.fromPoseResult(_fakePoseResult(visibility: 0.1)),
        isNull,
      );
    });
  });

  group('MediaPipe adapters', () {
    test('BodyMeshProvider adapts PoseDetector without SDK coupling', () async {
      final provider = MediaPipeBodyMeshProvider(
        poseDetector: _FakePoseDetector(_fakePoseResult()),
      );

      final assets = await provider.detect(
        ImageSource(bytes: Uint8List(4), width: 1, height: 1),
      );

      expect(assets, isNotNull);
      expect(assets!.capabilities.poseLandmarks, isTrue);
      expect(assets.landmark(BodyJoint.rightHip), isNotNull);
    });

    test('PersonMatteProvider adapts PersonMaskDetector', () async {
      final bytes = Uint8List.fromList(List.filled(16, 255));
      final provider = MediaPipePersonMatteProvider(
        detector: _FakePersonMaskDetector(
          PersonMask(bytes: bytes, width: 4, height: 4),
        ),
      );

      final matte = await provider.detect(
        ImageSource(bytes: Uint8List(4), width: 1, height: 1),
      );

      expect(matte, isNotNull);
      expect(matte!.width, 4);
      expect(matte.sampleNormalized(0.5, 0.5), 1);
      expect(provider.capabilities.personMatte, isTrue);
    });
  });

  group('BodyVisionCoordinator', () {
    test('fake providers feed BodyFrameAssets for the engine', () async {
      final matte = PersonMatte(
        alpha: Uint8List.fromList(List.filled(9, 200)),
        width: 3,
        height: 3,
        providerId: 'fake_matte',
      );
      final assets = BodyFrameAssets(
        landmarks: {
          BodyJoint.leftShoulder: const BodyLandmark(
            joint: BodyJoint.leftShoulder,
            normalized: Offset(0.3, 0.2),
            confidence: 0.9,
          ),
          BodyJoint.rightShoulder: const BodyLandmark(
            joint: BodyJoint.rightShoulder,
            normalized: Offset(0.7, 0.2),
            confidence: 0.9,
          ),
          BodyJoint.leftHip: const BodyLandmark(
            joint: BodyJoint.leftHip,
            normalized: Offset(0.35, 0.55),
            confidence: 0.9,
          ),
          BodyJoint.rightHip: const BodyLandmark(
            joint: BodyJoint.rightHip,
            normalized: Offset(0.65, 0.55),
            confidence: 0.9,
          ),
        },
        boundingBox: const Rect.fromLTWH(0.2, 0.1, 0.6, 0.8),
        providerId: 'fake',
        capabilities: VisionCapabilities.mediapipePoseOnly,
      );

      final coordinator = BodyVisionCoordinator(
        bodyMeshProvider: FakeBodyMeshProvider(assets: assets),
        personMatteProvider: FakePersonMatteProvider(matte: matte),
        bodyPartSegmentationProvider:
            const UnavailableBodyPartSegmentationProvider(),
        occlusionProvider: const UnavailableOcclusionProvider(),
        backgroundAnalysisProvider:
            const UnavailableBackgroundAnalysisProvider(),
      );

      final loaded = await coordinator.load(
        ImageSource(bytes: Uint8List(4), width: 1, height: 1),
      );

      expect(loaded, isNotNull);
      expect(loaded!.personMatte, isNotNull);
      expect(loaded.capabilities.poseLandmarks, isTrue);
      expect(loaded.capabilities.personMatte, isTrue);
      expect(loaded.capabilities.bodyPartSegmentation, isFalse);
      expect(loaded.capabilities.occlusionMap, isFalse);
    });
  });

  group('VisionCapabilityGate', () {
    const gate = VisionCapabilityGate(missingOcclusionScale: 0.55);
    const pipeline = BodyFilterPipeline();

    test('rejects rejectAdjustment when occlusion/parts are missing', () {
      final plan = pipeline.createReshapePlan(
        imageSize: const Size(400, 800),
        parameters: const {'leg_length': 0.8},
        capabilities: VisionCapabilities.mediapipePoseAndMatte,
      );

      expect(plan.adjustmentOfType(BodyAdjustmentType.legLength), isNull);
      expect(plan.ignoredParameters, contains('leg_length'));
      expect(
        plan.capabilityDecisions.any(
          (decision) =>
              decision.parameter == 'leg_length' &&
              decision.action == CapabilityGateAction.rejected,
        ),
        isTrue,
      );
    });

    test('reduces preserveOccluder adjustments without silent fallback', () {
      final raw = pipeline.createReshapePlan(
        imageSize: const Size(400, 800),
        parameters: const {'waist_slim': 0.8},
      );
      final gated = gate.apply(
        plan: raw,
        capabilities: VisionCapabilities.mediapipePoseAndMatte,
      );

      final waist = gated.adjustmentOfType(BodyAdjustmentType.waistSlim);
      expect(waist, isNotNull);
      expect(waist!.weight, closeTo(0.55, 1e-9));
      expect(
        gated.capabilityDecisions.any(
          (decision) =>
              decision.parameter == 'waist_slim' &&
              decision.action == CapabilityGateAction.reduced &&
              decision.reason == 'occlusion_or_parts_unavailable',
        ),
        isTrue,
      );
    });

    test('allows adjustments when occlusion capability is present', () {
      final plan = pipeline.createReshapePlan(
        imageSize: const Size(400, 800),
        parameters: const {'leg_length': 0.8, 'waist_slim': 0.5},
        capabilities: const VisionCapabilities(
          poseLandmarks: true,
          personMatte: true,
          occlusionMap: true,
        ),
      );

      expect(plan.adjustmentOfType(BodyAdjustmentType.legLength), isNotNull);
      expect(plan.adjustmentOfType(BodyAdjustmentType.waistSlim)?.weight, 1);
      expect(
        plan.capabilityDecisions.every(
          (decision) => decision.action == CapabilityGateAction.allowed,
        ),
        isTrue,
      );
    });

    test('rejects entire plan when pose landmarks are unavailable', () {
      final plan = pipeline.createReshapePlan(
        imageSize: const Size(400, 800),
        parameters: const {'waist_slim': 0.5},
        capabilities: VisionCapabilities.none,
      );

      expect(plan.isIdentity, isTrue);
      expect(plan.ignoredParameters, contains('waist_slim'));
    });
  });
}

PoseResult _fakePoseResult({double visibility = 0.9}) {
  final landmarks = List.generate(
    PoseResult.expectedLandmarkCount,
    (index) => PoseLandmark(
      index: index,
      normalized: Offset(0.3 + (index % 5) * 0.05, 0.1 + index * 0.02),
      visibility: visibility,
    ),
  );
  return PoseResult(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTWH(0.1, 0.05, 0.8, 0.9),
    isPartial: false,
  );
}

class _FakePoseDetector implements PoseDetector {
  _FakePoseDetector(this.result);

  final PoseResult? result;

  @override
  Future<PoseResult?> detect(ImageSource source) async => result;
}

class _FakePersonMaskDetector implements PersonMaskDetector {
  _FakePersonMaskDetector(this.mask);

  final PersonMask? mask;

  @override
  Future<PersonMask?> detect(ImageSource source) async => mask;
}
