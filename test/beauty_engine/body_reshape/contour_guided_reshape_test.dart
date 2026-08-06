import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/deformation/belly_strategy.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/deformation/body_mesh_deformer.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/deformation/body_region_deformation_strategy.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/person_mask_bridge.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/torso_contour_extractor.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/adaptive_mesh_generator.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_adjustment.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_frame_assets.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_joint.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_reshape_request.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/person_matte.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/warp_plan.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/segment/person_mask.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(160, 320);
  const extractor = TorsoContourExtractor(bandCount: 20);
  const generator = AdaptiveMeshGenerator();
  const deformer = BodyMeshDeformer();

  group('PersonMask → PersonMatte bridge', () {
    test('toPersonMatte preserves dimensions and alpha', () {
      final bytes = Uint8List.fromList(List<int>.filled(16, 200));
      final mask = PersonMask(bytes: bytes, width: 4, height: 4);
      final matte = mask.toPersonMatte(confidence: 0.9);

      expect(matte.width, 4);
      expect(matte.height, 4);
      expect(matte.confidence, 0.9);
      expect(matte.alpha, bytes);
      expect(matte.isEmpty, isFalse);
    });
  });

  group('TorsoContourExtractor', () {
    test('extracts dense shoulder→hip silhouette bands', () {
      final assets = _standingAssets(imageSize);
      final profile = extractor.extract(assets: assets, imageSize: imageSize);

      expect(profile, isNotNull);
      expect(profile!.usableBands.length, greaterThanOrEqualTo(8));
      expect(profile.meanConfidence, greaterThan(0.4));
      expect(profile.hasArmContamination, isFalse);

      final mid = profile.sampleAt(0.55);
      expect(mid, isNotNull);
      expect(mid!.halfWidth, greaterThan(imageSize.width * 0.08));
      expect(mid.leftX, lessThan(mid.rightX));
    });

    test('marks arm contamination when wrists cross abdomen', () {
      final assets = _standingAssets(
        imageSize,
        crossedArms: true,
      );
      final profile = extractor.extract(assets: assets, imageSize: imageSize);

      expect(profile, isNotNull);
      expect(profile!.hasArmContamination, isTrue);
    });
  });

  group('Belly/waist contour alignment', () {
    test('waist region covers belly peak band (~0.50–0.62)', () {
      final assets = _standingAssets(imageSize);
      final mesh = generator.generate(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.preview,
      );

      final shoulderY = imageSize.height * 0.24;
      final hipY = imageSize.height * 0.48;
      final span = hipY - shoulderY;

      var waistHits = 0;
      var samples = 0;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final y = mesh.vertices[i * 2 + 1];
        final t = ((y - shoulderY) / span).clamp(0.0, 1.0);
        if (t < 0.50 || t > 0.62) {
          continue;
        }
        samples++;
        if (mesh.regionAtVertex(i) == BodyRegion.waist) {
          waistHits++;
        }
      }
      expect(samples, greaterThan(0));
      expect(waistHits / samples, greaterThan(0.6));
    });

    test('belly reduce peaking near t≈0.56 moves silhouette edges inward', () {
      final assets = _standingAssets(imageSize);
      final mesh = generator.generate(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.preview,
      );
      final plan = WarpPlan(
        imageSize: imageSize,
        adjustments: const [
          BodyAdjustment(
            type: BodyAdjustmentType.bellyReduce,
            regions: {BodyRegion.waist, BodyRegion.torso},
            intensity: 1,
            maxIntensity: 1,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 0.7,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'belly_reduce',
          ),
        ],
        qualityProfile: WarpQualityProfile.preview,
      );

      final field = deformer.computeDisplacements(
        mesh: mesh,
        assets: assets,
        plan: plan,
      );

      final midline = imageSize.width * 0.5;
      final shoulderY = imageSize.height * 0.24;
      final hipY = imageSize.height * 0.48;
      final span = hipY - shoulderY;
      var leftDx = 0.0;
      var leftCount = 0;
      var rightDx = 0.0;
      var rightCount = 0;

      for (var i = 0; i < mesh.vertexCount; i++) {
        final y = mesh.vertices[i * 2 + 1];
        final t = ((y - shoulderY) / span).clamp(0.0, 1.0);
        if (t < 0.48 || t > 0.66) {
          continue;
        }
        final x = mesh.vertices[i * 2];
        final dx = field.deltas[i * 2];
        if (dx.abs() < 1e-4) {
          continue;
        }
        if (x < midline) {
          leftDx += dx;
          leftCount++;
        } else {
          rightDx += dx;
          rightCount++;
        }
      }

      expect(leftCount, greaterThan(0));
      expect(rightCount, greaterThan(0));
      expect(leftDx / leftCount, greaterThan(0));
      expect(rightDx / rightCount, lessThan(0));
    });

    test('shift magnitude scales with local silhouette half-width', () {
      final assets = _standingAssets(imageSize);
      final contour = extractor.extract(assets: assets, imageSize: imageSize)!;
      final band = contour.sampleAt(0.55)!;

      const strategy = BellyStrategy(maxShiftFraction: 0.05);
      final mesh = generator.generate(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.interactive,
      );
      final deltas = Float32List(mesh.vertexCount * 2);
      strategy.apply(
        context: RegionDeformationContext(
          mesh: mesh,
          assets: assets,
          adjustment: const BodyAdjustment(
            type: BodyAdjustmentType.bellyReduce,
            regions: {BodyRegion.waist},
            intensity: 1,
            maxIntensity: 1,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 0.7,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'belly_reduce',
          ),
          imageSize: imageSize,
          torsoContour: contour,
          safetyScale: 1,
        ),
        deltas: deltas,
      );

      var maxMag = 0.0;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final mag = Offset(deltas[i * 2], deltas[i * 2 + 1]).distance;
        if (mag > maxMag) {
          maxMag = mag;
        }
      }

      final expectedCap = band.halfWidth * 0.05 + 1.0;
      expect(maxMag, greaterThan(0.05));
      expect(maxMag, lessThan(expectedCap));
    });
  });

  group('Safety gates', () {
    test('missing matte reduces deformation intensity', () {
      final withMatte = _standingAssets(imageSize);
      final withoutMatte = _standingAssets(imageSize, withMatte: false);
      final mesh = generator.generate(
        assets: withMatte,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.preview,
      );
      final plan = WarpPlan(
        imageSize: imageSize,
        adjustments: const [
          BodyAdjustment(
            type: BodyAdjustmentType.waistSlim,
            regions: {BodyRegion.waist},
            intensity: 1,
            maxIntensity: 1,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 0.7,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'waist_slim',
          ),
        ],
        qualityProfile: WarpQualityProfile.preview,
      );

      double maxMag(BodyFrameAssets assets) {
        final field = deformer.computeDisplacements(
          mesh: mesh,
          assets: assets,
          plan: plan,
        );
        var max = 0.0;
        for (var i = 0; i < mesh.vertexCount; i++) {
          final mag = field.magnitudeAt(i);
          if (mag > max) {
            max = mag;
          }
        }
        return max;
      }

      expect(maxMag(withoutMatte), lessThan(maxMag(withMatte)));
    });

    test('background samples far outside matte stay nearly still', () {
      final assets = _standingAssets(imageSize);
      final mesh = generator.generate(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.preview,
      );
      final plan = WarpPlan(
        imageSize: imageSize,
        adjustments: const [
          BodyAdjustment(
            type: BodyAdjustmentType.bellyReduce,
            regions: {BodyRegion.waist, BodyRegion.torso},
            intensity: 1,
            maxIntensity: 1,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 0.7,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'belly_reduce',
          ),
        ],
        qualityProfile: WarpQualityProfile.preview,
      );
      final field = deformer.computeDisplacements(
        mesh: mesh,
        assets: assets,
        plan: plan,
      );
      final matte = assets.personMatte!;

      var outsideMax = 0.0;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final nx = mesh.uvs[i * 2];
        final ny = mesh.uvs[i * 2 + 1];
        if (matte.sampleNormalized(nx, ny) > 0.15) {
          continue;
        }
        if (mesh.weights[i] > 0.05) {
          continue;
        }
        final mag = field.magnitudeAt(i);
        if (mag > outsideMax) {
          outsideMax = mag;
        }
      }
      expect(outsideMax, lessThan(0.35));
    });
  });
}

BodyFrameAssets _standingAssets(
  Size size, {
  bool withMatte = true,
  bool crossedArms = false,
}) {
  BodyLandmark lm(BodyJoint joint, double x, double y) {
    return BodyLandmark(
      joint: joint,
      normalized: Offset(x, y),
      confidence: 0.95,
    );
  }

  final landmarks = <BodyJoint, BodyLandmark>{
    BodyJoint.nose: lm(BodyJoint.nose, 0.5, 0.12),
    BodyJoint.leftShoulder: lm(BodyJoint.leftShoulder, 0.38, 0.24),
    BodyJoint.rightShoulder: lm(BodyJoint.rightShoulder, 0.62, 0.24),
    BodyJoint.leftElbow: lm(
      BodyJoint.leftElbow,
      crossedArms ? 0.48 : 0.28,
      crossedArms ? 0.40 : 0.36,
    ),
    BodyJoint.rightElbow: lm(
      BodyJoint.rightElbow,
      crossedArms ? 0.52 : 0.72,
      crossedArms ? 0.40 : 0.36,
    ),
    BodyJoint.leftWrist: lm(
      BodyJoint.leftWrist,
      crossedArms ? 0.55 : 0.24,
      crossedArms ? 0.44 : 0.48,
    ),
    BodyJoint.rightWrist: lm(
      BodyJoint.rightWrist,
      crossedArms ? 0.45 : 0.76,
      crossedArms ? 0.44 : 0.48,
    ),
    BodyJoint.leftHip: lm(BodyJoint.leftHip, 0.42, 0.48),
    BodyJoint.rightHip: lm(BodyJoint.rightHip, 0.58, 0.48),
    BodyJoint.leftKnee: lm(BodyJoint.leftKnee, 0.43, 0.68),
    BodyJoint.rightKnee: lm(BodyJoint.rightKnee, 0.57, 0.68),
    BodyJoint.leftAnkle: lm(BodyJoint.leftAnkle, 0.44, 0.88),
    BodyJoint.rightAnkle: lm(BodyJoint.rightAnkle, 0.56, 0.88),
  };

  PersonMatte? matte;
  if (withMatte) {
    final width = size.width.round();
    final height = size.height.round();
    final alpha = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final nx = x / math.max(width - 1, 1);
        final ny = y / math.max(height - 1, 1);
        alpha[y * width + x] = _silhouetteContains(nx, ny) ? 255 : 0;
      }
    }
    matte = PersonMatte(
      alpha: alpha,
      width: width,
      height: height,
      providerId: 'test_matte',
      boundingRegion: const Rect.fromLTRB(0.24, 0.14, 0.76, 0.92),
    );
  }

  return BodyFrameAssets(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTRB(0.24, 0.14, 0.76, 0.92),
    providerId: 'test',
    capabilities: withMatte
        ? VisionCapabilities.mediapipePoseAndMatte
        : VisionCapabilities.mediapipePoseOnly,
    personMatte: matte,
  );
}

bool _silhouetteContains(double nx, double ny) {
  final torso = nx >= 0.34 && nx <= 0.66 && ny >= 0.20 && ny <= 0.52;
  final hips = nx >= 0.36 && nx <= 0.64 && ny >= 0.48 && ny <= 0.60;
  final leftArm = (nx - 0.34).abs() < 0.08 && ny >= 0.22 && ny <= 0.50;
  final rightArm = (nx - 0.66).abs() < 0.08 && ny >= 0.22 && ny <= 0.50;
  final leftLeg = (nx - 0.43).abs() < 0.07 && ny >= 0.52 && ny <= 0.90;
  final rightLeg = (nx - 0.57).abs() < 0.07 && ny >= 0.52 && ny <= 0.90;
  final head =
      math.pow(nx - 0.5, 2) / 0.045 + math.pow(ny - 0.14, 2) / 0.03 <= 1;
  return torso || hips || leftArm || rightArm || leftLeg || rightLeg || head;
}
