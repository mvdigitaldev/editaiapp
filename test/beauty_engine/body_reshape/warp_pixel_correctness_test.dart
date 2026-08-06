import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/brush/brush_warp_field_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/deformation/body_mesh_deformer.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/maps/matte_preprocessor.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/mesh/adaptive_mesh_generator.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_adjustment.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_frame_assets.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_joint.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/body_reshape_request.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/person_matte.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/warp_plan.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/passes/body_mesh_warp_pass.dart';
import 'package:editaiapp/features/editor/beauty_engine/body_reshape/providers/vision_capabilities.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_cpu_remap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageSize = Size(240, 400);
  const generator = AdaptiveMeshGenerator();
  const deformer = BodyMeshDeformer();
  const preprocessor = MattePreprocessor();

  group('ProtectionMaps outer band', () {
    test('weight decays outside silhouette and is zero far away', () {
      final assets = _standingAssets(imageSize);
      final protection = preprocessor.buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );

      expect(protection.outerBandPx, greaterThan(0));
      expect(protection.sampleWarpWeight(0.5, 0.36), greaterThan(0.5));
      // Canto da imagem: fundo rígido.
      expect(protection.sampleWarpWeight(0.02, 0.02), equals(0));
      expect(protection.isFarBackground(0.02, 0.02), isTrue);
    });
  });

  group('Inverse mesh warp (pixel)', () {
    test('belly reduce narrows silhouette width in remapped bitmap', () {
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

      final optimized =
          deformer.deform(mesh: mesh, assets: assets, plan: plan);
      final protection = preprocessor.buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );
      final field = BodyMeshWarpPass.rasterize(
        source: mesh,
        deformed: optimized.mesh,
        displacements: optimized.displacements,
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: 1,
        gridWidth: 48,
        gridHeight: 48,
        protectionMaps: protection,
      );

      expect(field.isIdentity, isFalse);

      final rgba = _syntheticPersonOnStripes(imageSize);
      final widthBefore = _measureSilhouetteWidth(
        rgba,
        imageSize.width.round(),
        imageSize.height.round(),
        sampleY: 0.40,
      );

      const remapper = WarpCpuRemap();
      final out = remapper.apply(
        rgba: rgba,
        width: imageSize.width.round(),
        height: imageSize.height.round(),
        field: field,
      );
      final widthAfter = _measureSilhouetteWidth(
        out,
        imageSize.width.round(),
        imageSize.height.round(),
        sampleY: 0.40,
      );

      // Correção do sinal: afinar DEVE reduzir a largura.
      expect(widthAfter, lessThan(widthBefore),
          reason: 'before=$widthBefore after=$widthAfter '
              'maxDisp=${field.maxDisplacementMagnitude}');
      expect(widthBefore - widthAfter, greaterThanOrEqualTo(0.5));
    });

    test('far background stripes stay byte-identical', () {
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
      final optimized =
          deformer.deform(mesh: mesh, assets: assets, plan: plan);
      final protection = preprocessor.buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );
      final field = BodyMeshWarpPass.rasterize(
        source: mesh,
        deformed: optimized.mesh,
        displacements: optimized.displacements,
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: 1,
        gridWidth: 40,
        gridHeight: 40,
        protectionMaps: protection,
      );

      final rgba = _syntheticPersonOnStripes(imageSize);
      final out = const WarpCpuRemap().apply(
        rgba: rgba,
        width: imageSize.width.round(),
        height: imageSize.height.round(),
        field: field,
      );

      // Cantos: fora da banda — bytes idênticos.
      final w = imageSize.width.round();
      final h = imageSize.height.round();
      for (final (x, y) in [
        (2, 2),
        (w - 3, 2),
        (2, h - 3),
        (w - 3, h - 3),
      ]) {
        final i = (y * w + x) * 4;
        expect(out[i], rgba[i]);
        expect(out[i + 1], rgba[i + 1]);
        expect(out[i + 2], rgba[i + 2]);
      }
    });

    test('no double silhouette edge after slim', () {
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
            regions: {BodyRegion.waist},
            intensity: 0.9,
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
      final optimized =
          deformer.deform(mesh: mesh, assets: assets, plan: plan);
      final protection = preprocessor.buildProtectionMaps(
        assets.personMatte!,
        imageSize: imageSize,
      );
      final field = BodyMeshWarpPass.rasterize(
        source: mesh,
        deformed: optimized.mesh,
        displacements: optimized.displacements,
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: 1,
        gridWidth: 48,
        gridHeight: 48,
        protectionMaps: protection,
      );

      final rgba = _syntheticPersonOnStripes(imageSize);
      final out = const WarpCpuRemap().apply(
        rgba: rgba,
        width: imageSize.width.round(),
        height: imageSize.height.round(),
        field: field,
      );

      final transitions = _countLeftEdgeTransitions(
        out,
        imageSize.width.round(),
        imageSize.height.round(),
        sampleY: 0.40,
      );
      // Sem campo invertido: muitas transições (fantasma). Aceita até 3.
      expect(transitions, lessThanOrEqualTo(3));
    });
  });

  group('Brush warp', () {
    test('push stroke produces non-identity inverse field', () {
      const builder = BrushWarpFieldBuilder(gridWidth: 32, gridHeight: 32);
      final field = builder.build(
        strokes: [
          const WarpStroke(
            points: [Offset(0.4, 0.4), Offset(0.55, 0.4)],
            radiusNormalized: 0.1,
            strength: 0.8,
            mode: WarpBrushMode.push,
          ),
        ],
        imageSize: imageSize,
      );
      expect(field.isIdentity, isFalse);
      expect(field.maxDisplacementMagnitude, greaterThan(0.5));
    });

    test('undo restores empty history field', () {
      final history = BrushStrokeHistory();
      history.add(
        const WarpStroke(
          points: [Offset(0.3, 0.4), Offset(0.5, 0.4)],
          radiusNormalized: 0.08,
          strength: 0.7,
        ),
      );
      expect(history.canUndo, isTrue);
      history.undo();
      expect(history.strokes, isEmpty);
      final field = history.buildField(imageSize: imageSize);
      expect(field.isIdentity, isTrue);
    });

    test('pinch stroke locally narrows silhouette', () {
      const builder = BrushWarpFieldBuilder(gridWidth: 40, gridHeight: 40);
      final field = builder.build(
        strokes: [
          const WarpStroke(
            points: [Offset(0.5, 0.38), Offset(0.5, 0.38)],
            radiusNormalized: 0.12,
            strength: 1,
            mode: WarpBrushMode.pinch,
          ),
        ],
        imageSize: imageSize,
      );
      final rgba = _syntheticPersonOnStripes(imageSize);
      final before = _measureSilhouetteWidth(
        rgba,
        imageSize.width.round(),
        imageSize.height.round(),
        sampleY: 0.38,
      );
      final out = const WarpCpuRemap().apply(
        rgba: rgba,
        width: imageSize.width.round(),
        height: imageSize.height.round(),
        field: field,
      );
      final after = _measureSilhouetteWidth(
        out,
        imageSize.width.round(),
        imageSize.height.round(),
        sampleY: 0.38,
      );
      expect(after, lessThanOrEqualTo(before));
    });
  });
}

BodyFrameAssets _standingAssets(Size size) {
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
    BodyJoint.leftElbow: lm(BodyJoint.leftElbow, 0.28, 0.36),
    BodyJoint.rightElbow: lm(BodyJoint.rightElbow, 0.72, 0.36),
    BodyJoint.leftWrist: lm(BodyJoint.leftWrist, 0.24, 0.48),
    BodyJoint.rightWrist: lm(BodyJoint.rightWrist, 0.76, 0.48),
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
      alpha[y * width + x] = _silhouetteContains(nx, ny) ? 255 : 0;
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

bool _silhouetteContains(double nx, double ny) {
  final torso = nx >= 0.34 && nx <= 0.66 && ny >= 0.20 && ny <= 0.52;
  final hips = nx >= 0.36 && nx <= 0.64 && ny >= 0.48 && ny <= 0.60;
  final leftLeg = (nx - 0.43).abs() < 0.07 && ny >= 0.52 && ny <= 0.90;
  final rightLeg = (nx - 0.57).abs() < 0.07 && ny >= 0.52 && ny <= 0.90;
  final head =
      math.pow(nx - 0.5, 2) / 0.045 + math.pow(ny - 0.14, 2) / 0.03 <= 1;
  return torso || hips || leftLeg || rightLeg || head;
}

Uint8List _syntheticPersonOnStripes(Size size) {
  final w = size.width.round();
  final h = size.height.round();
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final nx = x / math.max(w - 1, 1);
      final ny = y / math.max(h - 1, 1);
      final i = (y * w + x) * 4;
      if (_silhouetteContains(nx, ny)) {
        rgba[i] = 220;
        rgba[i + 1] = 160;
        rgba[i + 2] = 140;
        rgba[i + 3] = 255;
      } else {
        // Listras verticais no fundo.
        final stripe = (x ~/ 8).isEven;
        rgba[i] = stripe ? 40 : 200;
        rgba[i + 1] = stripe ? 40 : 200;
        rgba[i + 2] = stripe ? 40 : 200;
        rgba[i + 3] = 255;
      }
    }
  }
  return rgba;
}

bool _isPersonPixel(Uint8List rgba, int i) {
  // Silhueta sintética: R=220 G=160 B=140. Listras: 40 ou 200 neutros.
  return rgba[i] > 200 &&
      rgba[i + 1] > 140 &&
      rgba[i + 1] < 180 &&
      rgba[i + 2] > 120 &&
      rgba[i + 2] < 160;
}

double _measureSilhouetteWidth(
  Uint8List rgba,
  int width,
  int height, {
  required double sampleY,
}) {
  final y = (sampleY * (height - 1)).round().clamp(0, height - 1);
  var left = -1;
  var right = -1;
  for (var x = 0; x < width; x++) {
    final i = (y * width + x) * 4;
    if (_isPersonPixel(rgba, i)) {
      if (left < 0) {
        left = x;
      }
      right = x;
    }
  }
  if (left < 0) {
    return 0;
  }
  return (right - left).toDouble();
}

int _countLeftEdgeTransitions(
  Uint8List rgba,
  int width,
  int height, {
  required double sampleY,
}) {
  final y = (sampleY * (height - 1)).round().clamp(0, height - 1);
  var transitions = 0;
  var prevPerson = false;
  for (var x = 0; x < width; x++) {
    final i = (y * width + x) * 4;
    final isPerson = _isPersonPixel(rgba, i);
    if (isPerson && !prevPerson) {
      transitions++;
    }
    prevPerson = isPerson;
  }
  return transitions;
}
