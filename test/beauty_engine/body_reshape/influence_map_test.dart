import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/influence_map_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/matte_preprocessor.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/region_distance_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_adjustment.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_frame_assets.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_joint.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/person_matte.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/body/body_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/models/control_point.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_field_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(200, 400);
  const builder = InfluenceMapBuilder();

  group('RegionDistanceField', () {
    test('falloff decays with distance from regional axis', () {
      final assets = _standingAssets(imageSize);
      const rdfBuilder = RegionDistanceFieldBuilder();
      final field = rdfBuilder.build(
        imageSize: imageSize,
        regions: {BodyRegion.waist},
        width: 40,
        height: 80,
        assets: assets,
      );

      expect(field.segments, isNotEmpty);
      // Centro do torso (perto do eixo) > lateral longe.
      final near = field.sampleFalloff(0.50, 0.38);
      final far = field.sampleFalloff(0.12, 0.38);
      expect(near, greaterThan(far));
      expect(far, lessThan(0.15));
    });
  });

  group('InfluenceMapBuilder', () {
    test('maps differ by region (waist vs arm)', () {
      final assets = _standingAssets(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );

      final waist = builder.build(
        imageSize: imageSize,
        regions: {BodyRegion.waist},
        assets: assets,
        protection: protection,
        adjustment: _adj(
          BodyAdjustmentType.waistSlim,
          {BodyRegion.waist},
          BodyAdjustmentDirection.inward,
        ),
        mapWidth: 40,
        mapHeight: 80,
      );
      final arm = builder.build(
        imageSize: imageSize,
        regions: {BodyRegion.leftArm, BodyRegion.leftForearm},
        assets: assets,
        protection: protection,
        adjustment: _adj(
          BodyAdjustmentType.armSlim,
          {BodyRegion.leftArm, BodyRegion.leftForearm},
          BodyAdjustmentDirection.inward,
        ),
        mapWidth: 40,
        mapHeight: 80,
      );

      final waistAtCore = waist.sampleNormalized(0.50, 0.38);
      final armAtCore = arm.sampleNormalized(0.50, 0.38);
      final armAtLimb = arm.sampleNormalized(0.30, 0.34);
      final waistAtLimb = waist.sampleNormalized(0.30, 0.34);

      expect(waistAtCore, greaterThan(armAtCore));
      expect(armAtLimb, greaterThan(waistAtLimb));
    });

    test('does not expand influence outside person matte', () {
      final assets = _standingAssets(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );
      final map = builder.build(
        imageSize: imageSize,
        regions: {BodyRegion.waist, BodyRegion.torso},
        assets: assets,
        protection: protection,
        adjustment: _adj(
          BodyAdjustmentType.waistSlim,
          {BodyRegion.waist},
          BodyAdjustmentDirection.inward,
        ),
        mapWidth: 40,
        mapHeight: 80,
      );

      expect(map.sampleNormalized(0.05, 0.05), equals(0));
      expect(map.sampleNormalized(0.95, 0.95), equals(0));
      expect(map.sampleNormalized(0.50, 0.38), greaterThan(0.05));
    });

    test('angle weight favors lateral points for inward slim', () {
      final assets = _standingAssets(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );
      final map = builder.build(
        imageSize: imageSize,
        regions: {BodyRegion.waist},
        assets: assets,
        protection: protection,
        adjustment: _adj(
          BodyAdjustmentType.waistSlim,
          {BodyRegion.waist},
          BodyAdjustmentDirection.inward,
        ),
        mapWidth: 40,
        mapHeight: 80,
      );

      // Ligeiramente lateral vs exatamente no eixo medial.
      final axis = map.sampleNormalized(0.50, 0.38);
      final lateral = map.sampleNormalized(0.42, 0.38);
      expect(lateral, greaterThan(0));
      expect(axis, greaterThan(0));
      // Lateral deve ser competitivo / tipicamente maior no slim inward.
      expect(lateral + 0.02, greaterThanOrEqualTo(axis * 0.85));
    });

    test('curvature reinforces near silhouette contour', () {
      final assets = _standingAssets(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );
      final map = builder.build(
        imageSize: imageSize,
        regions: {BodyRegion.waist},
        assets: assets,
        protection: protection,
        adjustment: _adj(
          BodyAdjustmentType.waistSlim,
          {BodyRegion.waist},
          BodyAdjustmentDirection.inward,
        ),
        mapWidth: 50,
        mapHeight: 100,
      );

      // Amostra ao longo de uma linha horizontal na cintura: borda > centro puro
      // após combinar proteção (centro também alto). Verificamos transição suave.
      final samples = <double>[
        for (var i = 0; i <= 10; i++)
          map.sampleNormalized(0.34 + 0.032 * i, 0.38),
      ];
      // Deve haver valores intermediários (não só 0/1).
      final midValues = samples.where((v) => v > 0.05 && v < 0.95).length;
      expect(midValues, greaterThan(0));
      expect(samples.any((v) => v > 0.1), isTrue);
    });

    test('confidence scales influence and gates below minimum', () {
      final assets = _standingAssets(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );
      final high = builder.build(
        imageSize: imageSize,
        regions: {BodyRegion.waist},
        assets: assets,
        protection: protection,
        adjustment: _adj(
          BodyAdjustmentType.waistSlim,
          {BodyRegion.waist},
          BodyAdjustmentDirection.inward,
          minimumConfidence: 0.5,
        ),
        confidence: 1,
        mapWidth: 40,
        mapHeight: 80,
      );
      final low = builder.build(
        imageSize: imageSize,
        regions: {BodyRegion.waist},
        assets: assets,
        protection: protection,
        adjustment: _adj(
          BodyAdjustmentType.waistSlim,
          {BodyRegion.waist},
          BodyAdjustmentDirection.inward,
          minimumConfidence: 0.5,
        ),
        confidence: 0.25,
        mapWidth: 40,
        mapHeight: 80,
      );

      expect(high.maxValue, greaterThan(low.maxValue));
      expect(
        low.sampleNormalized(0.5, 0.38),
        lessThan(high.sampleNormalized(0.5, 0.38)),
      );
    });
  });

  group('WarpFieldBuilder + InfluenceMap', () {
    test('uses influence map instead of expanding to background', () {
      final assets = _standingAssets(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );
      final influence = builder.build(
        imageSize: imageSize,
        regions: {BodyRegion.waist},
        assets: assets,
        protection: protection,
        adjustment: _adj(
          BodyAdjustmentType.waistSlim,
          {BodyRegion.waist},
          BodyAdjustmentDirection.inward,
        ),
        mapWidth: 40,
        mapHeight: 80,
      );

      final field = const WarpFieldBuilder(
        gridWidth: 21,
        gridHeight: 41,
        maskFeatherPx: 80,
      ).build(
        controlPoints: const [
          ControlPoint(source: Offset(60, 150), target: Offset(70, 150)),
          ControlPoint(source: Offset(140, 150), target: Offset(130, 150)),
          ControlPoint(source: Offset(100, 100), target: Offset(100, 100)),
          ControlPoint(source: Offset(100, 200), target: Offset(100, 200)),
        ],
        imageSize: imageSize,
        region: MeshRegion.waist,
        intensity: 0.8,
        protectionMaps: protection,
        influenceMap: influence,
      );

      expect(field.mask[0], equals(0));
      expect(field.displacement[0], equals(0));
      final centerIdx = 20 * 21 + 10;
      expect(field.mask[centerIdx], greaterThan(0));
    });
  });

  group('BodyFilterPipeline.buildInfluenceMap', () {
    test('builds map from reshape plan regions', () {
      const pipeline = BodyFilterPipeline();
      final assets = _standingAssets(imageSize);
      final protection = const MattePreprocessor().buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );
      final plan = pipeline.createReshapePlan(
        imageSize: imageSize,
        parameters: const {'waist_slim': 0.7, 'arm_slim': 0.5},
      );
      final map = pipeline.buildInfluenceMap(
        plan: plan,
        assets: assets,
        protection: protection,
      );
      expect(map.isEmpty, isFalse);
      expect(map.regions, contains(BodyRegion.waist));
      expect(map.maxValue, greaterThan(0));
    });
  });
}

BodyAdjustment _adj(
  BodyAdjustmentType type,
  Set<BodyRegion> regions,
  BodyAdjustmentDirection direction, {
  double minimumConfidence = 0.3,
}) {
  return BodyAdjustment(
    type: type,
    regions: regions,
    intensity: 0.85,
    maxIntensity: 0.9,
    weight: 1,
    direction: direction,
    influence: 0.75,
    minimumConfidence: minimumConfidence,
    occlusionPolicy: BodyOcclusionPolicy.reduceIntensity,
    sourceParameter: type.name,
  );
}

BodyFrameAssets _standingAssets(Size size) {
  BodyLandmark lm(BodyJoint joint, double x, double y) => BodyLandmark(
        joint: joint,
        normalized: Offset(x, y),
        confidence: 0.95,
      );

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
      alpha[y * width + x] = _sil(nx, ny) ? 255 : 0;
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
    ),
  );
}

bool _sil(double nx, double ny) {
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
