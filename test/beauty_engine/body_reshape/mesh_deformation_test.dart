import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/deformation/body_mesh_deformer.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/adaptive_body_mesh.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/adaptive_mesh_generator.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/mesh_constraints.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/mesh_optimizer.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_adjustment.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_frame_assets.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_joint.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_reshape_request.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/person_matte.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/warp_plan.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_filter_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(320, 640);
  const generator = AdaptiveMeshGenerator();
  const deformer = BodyMeshDeformer();

  AdaptiveBodyMesh _mesh() {
    final assets = _standingPersonAssets(imageSize);
    return generator.generate(
      assets: assets,
      imageSize: imageSize,
      qualityProfile: WarpQualityProfile.preview,
    );
  }

  group('BodyMeshDeformer', () {
    test('produces vertex displacements without control points', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = _mesh();
      final plan = WarpPlan(
        imageSize: imageSize,
        adjustments: [
          const BodyAdjustment(
            type: BodyAdjustmentType.waistSlim,
            regions: {BodyRegion.waist},
            intensity: 0.8,
            maxIntensity: 0.85,
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

      final result = deformer.deform(mesh: mesh, assets: assets, plan: plan);

      expect(result.displacements.isIdentity, isFalse);
      expect(result.displacements.vertexCount, mesh.vertexCount);
      expect(result.mesh.vertexCount, mesh.vertexCount);
      expect(result.hasInvertedTriangles, isFalse);
    });

    test('waist slim moves left side rightward and right side leftward', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = _mesh();
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
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'waist_slim',
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
      var leftDx = 0.0;
      var leftCount = 0;
      var rightDx = 0.0;
      var rightCount = 0;

      for (var i = 0; i < mesh.vertexCount; i++) {
        if (mesh.regionAtVertex(i) != BodyRegion.waist) {
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
      expect(leftDx / leftCount, greaterThan(0)); // para dentro
      expect(rightDx / rightCount, lessThan(0));
    });

    test('hip expand moves sides outward', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = _mesh();
      final plan = WarpPlan(
        imageSize: imageSize,
        adjustments: [
          const BodyAdjustment(
            type: BodyAdjustmentType.hipExpand,
            regions: {BodyRegion.hip},
            intensity: 1,
            maxIntensity: 1,
            weight: 1,
            direction: BodyAdjustmentDirection.outward,
            influence: 0.7,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'hip',
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
      var leftDx = 0.0;
      var leftCount = 0;
      var rightDx = 0.0;
      var rightCount = 0;

      for (var i = 0; i < mesh.vertexCount; i++) {
        if (mesh.regionAtVertex(i) != BodyRegion.hip) {
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
      expect(leftDx / leftCount, lessThan(0)); // para fora
      expect(rightDx / rightCount, greaterThan(0));
    });

    test('chest expand and belly reduce produce non-identity fields', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = _mesh();
      final plan = WarpPlan(
        imageSize: imageSize,
        adjustments: [
          const BodyAdjustment(
            type: BodyAdjustmentType.chestExpand,
            regions: {BodyRegion.chest},
            intensity: 0.9,
            maxIntensity: 0.9,
            weight: 1,
            direction: BodyAdjustmentDirection.outward,
            influence: 0.65,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.preserveOccluder,
            sourceParameter: 'chest_expand',
          ),
          const BodyAdjustment(
            type: BodyAdjustmentType.bellyReduce,
            regions: {BodyRegion.waist, BodyRegion.torso},
            intensity: 0.8,
            maxIntensity: 0.8,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 0.7,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.preserveOccluder,
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

      expect(field.isIdentity, isFalse);
    });

    test('limb slim produces non-zero arm displacements', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = _mesh();
      final plan = WarpPlan(
        imageSize: imageSize,
        adjustments: [
          const BodyAdjustment(
            type: BodyAdjustmentType.armSlim,
            regions: {
              BodyRegion.leftArm,
              BodyRegion.rightArm,
              BodyRegion.leftForearm,
              BodyRegion.rightForearm,
            },
            intensity: 0.9,
            maxIntensity: 0.9,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 0.55,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'arm_slim',
          ),
        ],
        qualityProfile: WarpQualityProfile.preview,
      );

      final field = deformer.computeDisplacements(
        mesh: mesh,
        assets: assets,
        plan: plan,
      );

      var limbMoved = 0;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final region = mesh.regionAtVertex(i);
        if (region != BodyRegion.leftArm &&
            region != BodyRegion.rightArm &&
            region != BodyRegion.leftForearm &&
            region != BodyRegion.rightForearm) {
          continue;
        }
        if (field.magnitudeAt(i) > 1e-3) {
          limbMoved++;
        }
      }
      expect(limbMoved, greaterThan(0));
    });

    test('max intensity fixtures do not invert triangles', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = _mesh();
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
            influence: 1,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'waist_slim',
          ),
          const BodyAdjustment(
            type: BodyAdjustmentType.hipExpand,
            regions: {BodyRegion.hip},
            intensity: 1,
            maxIntensity: 1,
            weight: 1,
            direction: BodyAdjustmentDirection.outward,
            influence: 1,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'hip',
          ),
          const BodyAdjustment(
            type: BodyAdjustmentType.armSlim,
            regions: {
              BodyRegion.leftArm,
              BodyRegion.rightArm,
              BodyRegion.leftForearm,
              BodyRegion.rightForearm,
            },
            intensity: 1,
            maxIntensity: 1,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 1,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'arm_slim',
          ),
          const BodyAdjustment(
            type: BodyAdjustmentType.legSlim,
            regions: {
              BodyRegion.leftThigh,
              BodyRegion.rightThigh,
              BodyRegion.leftCalf,
              BodyRegion.rightCalf,
            },
            intensity: 1,
            maxIntensity: 1,
            weight: 1,
            direction: BodyAdjustmentDirection.inward,
            influence: 1,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'leg_slim',
          ),
        ],
        qualityProfile: WarpQualityProfile.preview,
      );

      final result = deformer.deform(mesh: mesh, assets: assets, plan: plan);
      expect(result.hasInvertedTriangles, isFalse);
      expect(result.mesh.hasDegenerateTriangles(), isFalse);
    });

    test('respects per-region displacement limits', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = _mesh();
      const constraints = MeshConstraints();
      final local = BodyMeshDeformer(constraints: constraints);
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
            influence: 1,
            minimumConfidence: 0.5,
            occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
            sourceParameter: 'waist_slim',
          ),
        ],
        qualityProfile: WarpQualityProfile.preview,
      );

      final field = local.computeDisplacements(
        mesh: mesh,
        assets: assets,
        plan: plan,
      );

      final maxAllowed =
          constraints.maxDisplacementPx(BodyRegion.waist, imageSize);
      for (var i = 0; i < mesh.vertexCount; i++) {
        if (mesh.regionAtVertex(i) != BodyRegion.waist) {
          continue;
        }
        expect(field.magnitudeAt(i), lessThanOrEqualTo(maxAllowed + 1e-4));
      }
    });

    test('pins low-weight boundary vertices', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = _mesh();
      // Força um delta bruto absurdo e confia no optimizer.
      final raw = Float32List(mesh.vertexCount * 2);
      for (var i = 0; i < mesh.vertexCount; i++) {
        raw[i * 2] = 40;
        raw[i * 2 + 1] = -25;
      }
      final optimized = const MeshOptimizer().optimize(
        source: mesh,
        rawDeltas: raw,
      );

      for (var i = 0; i < mesh.vertexCount; i++) {
        if (mesh.weights[i] > 0.08) {
          continue;
        }
        expect(optimized.displacements.magnitudeAt(i), lessThan(1e-6));
      }
    });
  });

  group('BodyFilterPipeline V2 deform', () {
    test('deformAdaptiveMesh uses reshape plan without control points', () {
      const pipeline = BodyFilterPipeline();
      final assets = _standingPersonAssets(imageSize);
      final mesh = _mesh();
      final plan = pipeline.createReshapePlan(
        imageSize: imageSize,
        parameters: const {'waist_slim': 0.7, 'hip': 0.5},
      );

      final result = pipeline.deformAdaptiveMesh(
        mesh: mesh,
        assets: assets,
        plan: plan,
      );

      expect(plan.adjustments, isNotEmpty);
      expect(result.displacements.isIdentity, isFalse);
      expect(result.hasInvertedTriangles, isFalse);
    });
  });
}

BodyFrameAssets _standingPersonAssets(Size size, {bool withMatte = true}) {
  BodyLandmark lm(BodyJoint joint, double x, double y) {
    return BodyLandmark(
      joint: joint,
      normalized: Offset(x, y),
      confidence: 0.95,
    );
  }

  final landmarks = <BodyJoint, BodyLandmark>{
    BodyJoint.leftShoulder: lm(BodyJoint.leftShoulder, 0.38, 0.22),
    BodyJoint.rightShoulder: lm(BodyJoint.rightShoulder, 0.62, 0.22),
    BodyJoint.leftElbow: lm(BodyJoint.leftElbow, 0.30, 0.36),
    BodyJoint.rightElbow: lm(BodyJoint.rightElbow, 0.70, 0.36),
    BodyJoint.leftWrist: lm(BodyJoint.leftWrist, 0.28, 0.48),
    BodyJoint.rightWrist: lm(BodyJoint.rightWrist, 0.72, 0.48),
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
        final inside = _silhouetteContains(nx, ny);
        alpha[y * width + x] = inside ? 255 : 0;
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
