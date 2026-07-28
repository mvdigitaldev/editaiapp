import 'dart:typed_data';

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
  });

  final List<BodyRegionDeformationStrategy> strategies;
  final MeshConstraints constraints;

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
        ),
        deltas: deltas,
      );
    }

    return optimizer.optimize(source: mesh, rawDeltas: deltas);
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
