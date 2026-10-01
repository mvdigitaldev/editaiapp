import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/deformation/body_mesh_deformer.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/adaptive_mesh_generator.dart';
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

  test('reset body menu has no deformation strategies', () {
    expect(BodyMeshDeformer.defaultStrategies, isEmpty);
    expect(BodyFilterPipeline.bodyWarpParameterKeys, isEmpty);
  });

  test('deformer stays identity after the body menu reset', () {
    final assets = _standingPersonAssets(imageSize);
    final mesh = generator.generate(
      assets: assets,
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

    final result = deformer.deform(mesh: mesh, assets: assets, plan: plan);
    expect(result.displacements.isIdentity, isTrue);
    expect(result.hasInvertedTriangles, isFalse);

    const pipeline = BodyFilterPipeline();
    final emptyPlan = pipeline.createReshapePlan(
      imageSize: imageSize,
      parameters: const {'waist_slim': 0.7, 'hip': 0.5},
    );
    expect(emptyPlan.isIdentity, isTrue);
    expect(
      pipeline
          .deformAdaptiveMesh(mesh: mesh, assets: assets, plan: emptyPlan)
          .displacements
          .isIdentity,
      isTrue,
    );
  });

  test('pins low-weight boundary vertices', () {
    final assets = _standingPersonAssets(imageSize);
    final mesh = generator.generate(
      assets: assets,
      imageSize: imageSize,
      qualityProfile: WarpQualityProfile.preview,
    );
    final raw = Float32List(mesh.vertexCount * 2);
    for (var i = 0; i < mesh.vertexCount; i++) {
      raw[i * 2] = 40;
      raw[i * 2 + 1] = -25;
    }
    final optimized = const MeshOptimizer().optimize(
      source: mesh,
      rawDeltas: raw,
    );

    const pinThreshold = 0.05;
    for (var i = 0; i < mesh.vertexCount; i++) {
      if (mesh.weights[i] > pinThreshold) {
        continue;
      }
      expect(optimized.displacements.magnitudeAt(i), lessThan(1e-6));
    }
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
