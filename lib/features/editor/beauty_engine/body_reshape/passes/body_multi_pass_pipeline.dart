import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../models/warp_field.dart';
import '../../warp/models/control_point.dart';
import '../maps/influence_map.dart';
import '../maps/protection_maps.dart';
import '../mesh/adaptive_body_mesh.dart';
import '../models/body_frame_assets.dart';
import '../models/warp_plan.dart';
import 'anti_folding_pass.dart';
import 'body_mesh_warp_pass.dart';
import 'body_reshape_pass.dart';
import 'edge_refinement_pass.dart';
import 'local_mls_pass.dart';
import 'pass_profiler.dart';

/// Entrada do pipeline multi-passe Body Reshape V2.
class BodyMultiPassInput {
  const BodyMultiPassInput({
    required this.imageSize,
    required this.config,
    this.sourceMesh,
    this.assets,
    this.plan,
    this.seedField,
    this.controlPoints = const [],
    this.influenceMap,
    this.protectionMaps,
    this.region = MeshRegion.torso,
  });

  final Size imageSize;
  final BodyMultiPassConfig config;
  final AdaptiveBodyMesh? sourceMesh;
  final BodyFrameAssets? assets;
  final WarpPlan? plan;
  final WarpField? seedField;
  final List<ControlPoint> controlPoints;
  final InfluenceMap? influenceMap;
  final ProtectionMaps? protectionMaps;
  final MeshRegion region;
}

/// Resultado do pipeline com telemetria.
class BodyMultiPassResult {
  const BodyMultiPassResult({
    required this.field,
    required this.profiler,
    required this.enabledPasses,
    required this.executedPasses,
  });

  final WarpField field;
  final PassProfiler profiler;
  final List<String> enabledPasses;
  final List<String> executedPasses;
}

/// Orquestra BodyMeshWarp → LocalMls → AntiFolding → EdgeRefinement.
///
/// Cada passe pode ser ligado/desligado via [BodyMultiPassConfig].
class BodyMultiPassPipeline {
  BodyMultiPassPipeline({
    BodyMeshWarpPass bodyMeshWarp = const BodyMeshWarpPass(),
    LocalMlsPass localMls = const LocalMlsPass(),
    AntiFoldingPass antiFolding = const AntiFoldingPass(),
    EdgeRefinementPass edgeRefinement = const EdgeRefinementPass(),
  })  : _bodyMeshWarp = bodyMeshWarp,
        _localMls = localMls,
        _antiFolding = antiFolding,
        _edgeRefinement = edgeRefinement;

  final BodyMeshWarpPass _bodyMeshWarp;
  final LocalMlsPass _localMls;
  final AntiFoldingPass _antiFolding;
  final EdgeRefinementPass _edgeRefinement;

  /// Ordem canônica dos passes (anti-fold antes do edge para não reintroduzir
  /// máscara em células ainda invertidas).
  List<BodyReshapePass> get passes => [
        _bodyMeshWarp,
        _localMls,
        _antiFolding,
        _edgeRefinement,
      ];

  BodyMultiPassResult run(BodyMultiPassInput input) {
    final profiler = PassProfiler(enabled: input.config.profilePasses);
    final context = BodyPassContext(
      imageSize: input.imageSize,
      config: input.config,
      profiler: profiler,
      field: input.seedField,
      sourceMesh: input.sourceMesh,
      controlPoints: List<ControlPoint>.from(input.controlPoints),
      assets: input.assets,
      plan: input.plan,
      influenceMap: input.influenceMap,
      protectionMaps: input.protectionMaps,
      region: input.region,
    );

    final enabled = <String>[];
    final executed = <String>[];

    for (final pass in passes) {
      if (!pass.isEnabled(input.config)) {
        profiler.recordSkipped(pass.id);
        continue;
      }
      enabled.add(pass.id);
      profiler.begin(pass.id);
      final field = pass.run(context);
      context.field = field;
      executed.add(pass.id);
      profiler.end(
        pass.id,
        metrics: {
          'active_cells': (field.activeCellCount ?? 0).toDouble(),
          'intensity': field.intensity,
          if (field.foldingCellsBefore > 0)
            'folding_before': field.foldingCellsBefore.toDouble(),
          if (pass.id == 'anti_folding')
            'folding_after': field.foldingCellsAfter.toDouble(),
        },
      );
    }

    final field = context.field ??
        WarpField.identity(imageSize: input.imageSize, region: input.region);

    return BodyMultiPassResult(
      field: field.copyWith(passProfiles: profiler.entries),
      profiler: profiler,
      enabledPasses: enabled,
      executedPasses: executed,
    );
  }
}
