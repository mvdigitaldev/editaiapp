import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_frame_assets.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_joint.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_part_segmentation.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/occlusion/occlusion_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/occlusion/occlusion_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/occlusion/part_occlusion_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/instance_selection_policy.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/part_segmentation_model_provider.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PartOcclusionMap', () {
    test('turns hand, arm and hair labels into measurable occlusion', () {
      final labels = Uint8List.fromList([
        BodyPartLabel.torso.index,
        BodyPartLabel.leftHand.index,
        BodyPartLabel.leftForearm.index,
        BodyPartLabel.hair.index,
      ]);
      final field = PartOcclusionMap.fromSegmentation(
        BodyPartSegmentation(
          labels: labels,
          width: 2,
          height: 2,
          providerId: 'fixture',
          confidences: const {
            BodyPartLabel.leftHand: 0.9,
            BodyPartLabel.leftForearm: 0.9,
            BodyPartLabel.hair: 0.9,
          },
        ),
      );

      expect(field.presentKinds, contains(OccluderKind.leftHand));
      expect(field.presentKinds, contains(OccluderKind.leftArm));
      expect(field.presentKinds, contains(OccluderKind.hair));
      expect(field.sampleNormalized(0.9, 0.1), greaterThan(0.9));
      // Amostragem bilinear pode receber pequena contribuição do hand vizinho.
      expect(field.sampleNormalized(0.1, 0.1), lessThan(0.2));
    });

    test('OcclusionEngine exposes field derived from part segmentation', () {
      final assets = _asset(
        instanceId: 'selected',
        box: const Rect.fromLTWH(0.2, 0.1, 0.5, 0.8),
      ).copyWith(
        partSegmentation: BodyPartSegmentation(
          labels: Uint8List.fromList([
            BodyPartLabel.leftHand.index,
            BodyPartLabel.leftHand.index,
            BodyPartLabel.leftHand.index,
            BodyPartLabel.leftHand.index,
          ]),
          width: 2,
          height: 2,
          providerId: 'fixture',
        ),
      );

      final field = const OcclusionEngine().fieldForAssets(assets);
      expect(field, isNotNull);
      expect(field!.presentKinds, contains(OccluderKind.leftHand));
      expect(
          field.overlapRatioInNormalizedRect(const Rect.fromLTWH(0, 0, 1, 1)),
          greaterThan(0.9));
    });
  });

  group('InstanceSelectionPolicy', () {
    final small = _asset(
      instanceId: 'small',
      box: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
    );
    final large = _asset(
      instanceId: 'large',
      box: const Rect.fromLTWH(0.4, 0.1, 0.5, 0.7),
    );

    test('uses explicit id before area', () {
      const policy = InstanceSelectionPolicy(targetInstanceId: 'small');
      expect(policy.select([large, small])?.instanceId, 'small');
    });

    test('uses tapped person before largest area', () {
      const policy = InstanceSelectionPolicy(focusPoint: Offset(0.15, 0.15));
      expect(policy.select([large, small])?.instanceId, 'small');
    });

    test('uses largest person as deterministic fallback', () {
      const policy = InstanceSelectionPolicy();
      expect(policy.select([small, large])?.instanceId, 'large');
    });
  });

  test('model provider stays model-agnostic and validates output', () async {
    final provider = PartSegmentationModelProvider(
      detectParts: (_) async => BodyPartSegmentation(
        labels: Uint8List.fromList([BodyPartLabel.hair.index]),
        width: 1,
        height: 1,
        providerId: 'candidate_model',
      ),
    );

    final parts = await provider.detect(
      ImageSource(bytes: Uint8List(4), width: 1, height: 1),
    );
    expect(parts?.providerId, 'candidate_model');
    expect(provider.capabilities.bodyPartSegmentation, isTrue);
    expect(provider.capabilities.multiPerson, isTrue);
  });
}

BodyFrameAssets _asset({
  required String instanceId,
  required Rect box,
}) {
  return BodyFrameAssets(
    landmarks: const {
      BodyJoint.leftShoulder: BodyLandmark(
        joint: BodyJoint.leftShoulder,
        normalized: Offset(0.3, 0.2),
        confidence: 0.9,
      ),
    },
    boundingBox: box,
    providerId: 'fixture',
    instanceId: instanceId,
    capabilities: VisionCapabilities.mediapipePoseOnly,
  );
}
