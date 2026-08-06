import 'dart:math' as math;
import 'dart:typed_data';

import '../maps/torso_contour_extractor.dart';
import '../maps/torso_contour_profile.dart';
import '../mesh/adaptive_body_mesh.dart';
import '../mesh/mesh_constraints.dart';
import '../mesh/mesh_optimizer.dart';
import '../models/body_adjustment.dart';
import '../models/body_frame_assets.dart';
import '../models/warp_plan.dart';
import 'belly_strategy.dart';
import 'body_region_deformation_strategy.dart';
import 'butt_strategy.dart';
import 'chest_strategy.dart';
import 'height_strategy.dart';
import 'hip_strategy.dart';
import 'limb_slim_strategy.dart';
import 'neck_strategy.dart';
import 'shoulder_strategy.dart';
import 'waist_strategy.dart';

/// Orquestra estratégias regionais + MeshOptimizer a partir de um [WarpPlan].
///
/// Produz deslocamentos de vértice sem control points do pipeline MLS legado.
class BodyMeshDeformer {
  const BodyMeshDeformer({
    this.strategies = defaultStrategies,
    this.constraints = const MeshConstraints(),
    this.contourExtractor = const TorsoContourExtractor(),
  });

  final List<BodyRegionDeformationStrategy> strategies;
  final MeshConstraints constraints;
  final TorsoContourExtractor contourExtractor;

  static const defaultStrategies = <BodyRegionDeformationStrategy>[
    WaistStrategy(),
    BellyStrategy(),
    HipStrategy(),
    ButtStrategy(),
    ChestStrategy(),
    ShoulderStrategy(),
    HeightStrategy(),
    LimbSlimStrategy(),
    NeckStrategy(),
  ];

  /// Aplica o plano V2 e devolve malha otimizada + campo de deslocamento.
  OptimizedMeshResult deform({
    required AdaptiveBodyMesh mesh,
    required BodyFrameAssets assets,
    required WarpPlan plan,
  }) {
    final optimizer = MeshOptimizer(constraints: constraints);
    final deltas = Float32List(mesh.vertexCount * 2);
    if (plan.isIdentity || mesh.vertexCount == 0) {
      return optimizer.optimize(source: mesh, rawDeltas: deltas);
    }

    final contour = contourExtractor.extract(
      assets: assets,
      imageSize: plan.imageSize,
    );
    final safetyScale = _safetyScale(assets: assets, contour: contour);

    for (final adjustment in plan.adjustments) {
      if (!adjustment.isActive) {
        continue;
      }
      final strategy = _strategyFor(adjustment.type);
      if (strategy == null) {
        continue;
      }
      strategy.apply(
        context: RegionDeformationContext(
          mesh: mesh,
          assets: assets,
          adjustment: adjustment,
          imageSize: plan.imageSize,
          torsoContour: contour,
          safetyScale: safetyScale,
        ),
        deltas: deltas,
      );
    }

    return optimizer.optimize(source: mesh, rawDeltas: deltas);
  }

  double _safetyScale({
    required BodyFrameAssets assets,
    required TorsoContourProfile? contour,
  }) {
    var scale = 1.0;
    if (assets.isPartial) {
      scale *= 0.65;
    }
    final matte = assets.personMatte;
    if (matte == null || matte.isEmpty) {
      scale *= 0.55;
    } else if (matte.confidence < 0.55) {
      scale *= 0.7;
    }
    if (contour == null || contour.isEmpty) {
      scale *= 0.75;
    } else {
      if (contour.meanConfidence < 0.5) {
        scale *= 0.7;
      }
      if (contour.hasArmContamination) {
        scale *= 0.55;
      }
    }
    if (!assets.capabilities.personMatte) {
      scale *= 0.7;
    }
    final occlusion = assets.occlusionMap;
    if (occlusion != null && !occlusion.isEmpty) {
      var sum = 0;
      final step = math.max(1, occlusion.weights.length ~/ 256);
      var samples = 0;
      for (var i = 0; i < occlusion.weights.length; i += step) {
        sum += occlusion.weights[i];
        samples++;
      }
      if (samples > 0) {
        final mean = sum / (samples * 255.0);
        if (mean > 0.12) {
          scale *= (1.0 - mean * 0.65).clamp(0.35, 1.0);
        }
      }
    }
    return scale.clamp(0.2, 1.0);
  }

  /// Apenas o campo de deslocamento (útil para passes futuros / GPU).
  VertexDisplacementField computeDisplacements({
    required AdaptiveBodyMesh mesh,
    required BodyFrameAssets assets,
    required WarpPlan plan,
  }) {
    return deform(mesh: mesh, assets: assets, plan: plan).displacements;
  }

  BodyRegionDeformationStrategy? _strategyFor(BodyAdjustmentType type) {
    for (final strategy in strategies) {
      if (strategy.supportedTypes.contains(type)) {
        return strategy;
      }
    }
    return null;
  }
}
