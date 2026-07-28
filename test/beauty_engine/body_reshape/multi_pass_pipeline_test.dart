import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/adaptive_mesh_generator.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_adjustment.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_frame_assets.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_joint.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_reshape_request.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/person_matte.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/warp_plan.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/anti_folding_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/body_mesh_warp_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/body_multi_pass_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/body_reshape_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/edge_refinement_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/local_mls_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/pass_profiler.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/mls_warp_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/models/control_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(160, 320);
  const generator = AdaptiveMeshGenerator();

  group('BodyMultiPassConfig toggles', () {
    test('each pass can be enabled independently', () {
      expect(const BodyMultiPassConfig(bodyMeshWarp: true).enabledPassCount, 1);
      expect(const BodyMultiPassConfig(localMls: true).enabledPassCount, 1);
      expect(
        const BodyMultiPassConfig(edgeRefinement: true).enabledPassCount,
        1,
      );
      expect(const BodyMultiPassConfig(antiFolding: true).enabledPassCount, 1);
      expect(BodyMultiPassConfig.previewV2.enabledPassCount, 4);
      expect(BodyMultiPassConfig.legacy.isV2Enabled, isFalse);
    });
  });

  group('BodyMeshWarpPass', () {
    test('rasterizes vertex displacements into a non-identity WarpField', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = generator.generate(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.preview,
      );
      final plan = _waistPlan(imageSize);
      final context = BodyPassContext(
        imageSize: imageSize,
        config: const BodyMultiPassConfig(bodyMeshWarp: true),
        profiler: PassProfiler(),
        sourceMesh: mesh,
        assets: assets,
        plan: plan,
      );

      final field =
          const BodyMeshWarpPass(gridWidth: 32, gridHeight: 32).run(context);

      expect(field.isIdentity, isFalse);
      expect(field.passId, 'body_mesh_warp');
      expect(field.activeCellCount, greaterThan(0));
      expect(context.controlPoints, isNotEmpty);
      expect(context.vertexDisplacements, isNotNull);
    });
  });

  group('LocalMlsPass spatial index', () {
    test('does not query all control points per cell on average', () {
      final points = <ControlPoint>[];
      for (var i = 0; i < 80; i++) {
        final x = 20.0 + (i % 10) * 12.0;
        final y = 40.0 + (i ~/ 10) * 20.0;
        points.add(
          ControlPoint(
            source: Offset(x, y),
            target: Offset(x + (i.isEven ? 3 : -3), y),
          ),
        );
      }

      const pass = LocalMlsPass(gridWidth: 24, gridHeight: 24);
      final result = pass.buildField(
        controlPoints: points,
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: 0.8,
      );

      expect(result.totalControlPoints, 80);
      expect(result.averageNeighborsQueried, lessThan(60));
      expect(result.usedLocalNeighborhood, isTrue);
      expect(result.field.isIdentity, isFalse);
    });

    test('ControlPointSpatialIndex returns local subset', () {
      final points = List<ControlPoint>.generate(40, (i) {
        return ControlPoint(
          source: Offset(10.0 + i * 3.5, 80),
          target: Offset(10.0 + i * 3.5 + 2, 80),
        );
      });
      final index = ControlPointSpatialIndex(
        points: points,
        imageSize: imageSize,
        cellSize: 16,
      );
      final nearby = index.queryNearby(
        const Offset(40, 80),
        radius: 24,
        minCount: 3,
      );
      expect(nearby.length, lessThan(points.length));
      expect(nearby.length, greaterThanOrEqualTo(3));
    });
  });

  group('AntiFoldingPass', () {
    test('eliminates inverted jacobian cells in regression fixture', () {
      final field = _foldedField(imageSize);
      const pass = AntiFoldingPass(maxIterations: 10, scaleFactor: 0.65);
      final before = pass.countInversions(
        displacement: field.displacement,
        mask: field.mask,
        gridWidth: field.gridWidth,
        gridHeight: field.gridHeight,
        imageSize: field.imageSize,
      );
      expect(before, greaterThan(0));

      final result = pass.resolve(field);
      expect(result.invertedBefore, before);
      expect(result.invertedAfter, 0);
      expect(result.eliminatedInversions, isTrue);
      expect(result.field.foldingCellsAfter, 0);
    });
  });

  group('EdgeRefinementPass', () {
    test('kills displacement outside matte', () {
      final matte = _centerMatte(imageSize);
      final field = _uniformShiftField(imageSize, dx: 5);
      final refined = const EdgeRefinementPass().refine(
        field: field,
        matte: matte,
      );

      expect(refined.mask[0], 0);
      expect(refined.displacement[0], 0);
      final mid = (refined.gridHeight ~/ 2) * refined.gridWidth +
          refined.gridWidth ~/ 2;
      expect(refined.mask[mid], greaterThan(0));
    });
  });

  group('BodyMultiPassPipeline', () {
    test('respects toggles and records profiler entries', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = generator.generate(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.interactive,
      );
      final pipeline = BodyMultiPassPipeline(
        bodyMeshWarp: const BodyMeshWarpPass(gridWidth: 24, gridHeight: 24),
        localMls: const LocalMlsPass(gridWidth: 24, gridHeight: 24),
      );

      final onlyMesh = pipeline.run(
        BodyMultiPassInput(
          imageSize: imageSize,
          config: const BodyMultiPassConfig(bodyMeshWarp: true),
          sourceMesh: mesh,
          assets: assets,
          plan: _waistPlan(imageSize),
        ),
      );
      expect(onlyMesh.executedPasses, ['body_mesh_warp']);
      expect(onlyMesh.field.isIdentity, isFalse);

      final meshAndFold = pipeline.run(
        BodyMultiPassInput(
          imageSize: imageSize,
          config: const BodyMultiPassConfig(
            bodyMeshWarp: true,
            antiFolding: true,
          ),
          sourceMesh: mesh,
          assets: assets,
          plan: _waistPlan(imageSize),
        ),
      );
      expect(meshAndFold.executedPasses, ['body_mesh_warp', 'anti_folding']);
      expect(meshAndFold.profiler.entries.length, greaterThanOrEqualTo(2));
    });

    test('MlsWarpEngine.composeBodyMultiPass wires pipeline', () {
      final assets = _standingPersonAssets(imageSize);
      final mesh = generator.generate(
        assets: assets,
        imageSize: imageSize,
        qualityProfile: WarpQualityProfile.interactive,
      );
      final engine = MlsWarpEngine();
      final result = engine.composeBodyMultiPass(
        BodyMultiPassInput(
          imageSize: imageSize,
          config: const BodyMultiPassConfig(
            bodyMeshWarp: true,
            antiFolding: true,
          ),
          sourceMesh: mesh,
          assets: assets,
          plan: _waistPlan(imageSize),
        ),
      );
      expect(result, isNotNull);
      expect(result!.field.isIdentity, isFalse);
      expect(result.executedPasses, contains('body_mesh_warp'));
    });
  });
}

WarpPlan _waistPlan(Size imageSize) {
  return WarpPlan(
    imageSize: imageSize,
    adjustments: [
      const BodyAdjustment(
        type: BodyAdjustmentType.waistSlim,
        regions: {BodyRegion.waist},
        intensity: 0.85,
        maxIntensity: 0.9,
        weight: 1,
        direction: BodyAdjustmentDirection.inward,
        influence: 0.7,
        minimumConfidence: 0.4,
        occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
        sourceParameter: 'waist_slim',
      ),
    ],
    qualityProfile: WarpQualityProfile.preview,
  );
}

WarpField _foldedField(Size imageSize) {
  const gw = 8;
  const gh = 8;
  final disp = Float32List(gw * gh * 2);
  final mask = Float32List(gw * gh);
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      final idx = gy * gw + gx;
      mask[idx] = 1;
      if (gx == 3) {
        disp[idx * 2] = 40;
      } else if (gx == 4) {
        disp[idx * 2] = -40;
      }
    }
  }
  return WarpField(
    gridWidth: gw,
    gridHeight: gh,
    displacement: disp,
    mask: mask,
    imageSize: imageSize,
    region: MeshRegion.torso,
    controlPoints: const [
      ControlPoint(source: Offset(0.5, 0.5), target: Offset(0.6, 0.5)),
    ],
    intensity: 1,
  );
}

WarpField _uniformShiftField(Size imageSize, {required double dx}) {
  const gw = 16;
  const gh = 16;
  final disp = Float32List(gw * gh * 2);
  final mask = Float32List(gw * gh);
  for (var i = 0; i < gw * gh; i++) {
    disp[i * 2] = dx;
    mask[i] = 1;
  }
  return WarpField(
    gridWidth: gw,
    gridHeight: gh,
    displacement: disp,
    mask: mask,
    imageSize: imageSize,
    region: MeshRegion.torso,
    controlPoints: const [
      ControlPoint(source: Offset(0.5, 0.5), target: Offset(0.55, 0.5)),
    ],
    intensity: 1,
  );
}

PersonMatte _centerMatte(Size size) {
  final width = size.width.round();
  final height = size.height.round();
  final alpha = Uint8List(width * height);
  final cx0 = (width * 0.3).round();
  final cx1 = (width * 0.7).round();
  final cy0 = (height * 0.2).round();
  final cy1 = (height * 0.8).round();
  for (var y = cy0; y < cy1; y++) {
    for (var x = cx0; x < cx1; x++) {
      alpha[y * width + x] = 255;
    }
  }
  return PersonMatte(
    alpha: alpha,
    width: width,
    height: height,
    providerId: 'test_matte',
    boundingRegion: const Rect.fromLTRB(0.3, 0.2, 0.7, 0.8),
  );
}

BodyFrameAssets _standingPersonAssets(Size size) {
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

  final width = size.width.round();
  final height = size.height.round();
  final alpha = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final nx = x / math.max(width - 1, 1);
      final ny = y / math.max(height - 1, 1);
      final inside = nx >= 0.34 && nx <= 0.66 && ny >= 0.20 && ny <= 0.90;
      alpha[y * width + x] = inside ? 255 : 0;
    }
  }

  return BodyFrameAssets(
    landmarks: landmarks,
    boundingBox: const Rect.fromLTRB(0.24, 0.14, 0.76, 0.92),
    providerId: 'test',
    capabilities: VisionCapabilities.mediapipePoseAndMatte,
    personMatte: PersonMatte(
      alpha: alpha,
      width: width,
      height: height,
      providerId: 'test_matte',
      boundingRegion: const Rect.fromLTRB(0.24, 0.14, 0.76, 0.92),
    ),
  );
}
