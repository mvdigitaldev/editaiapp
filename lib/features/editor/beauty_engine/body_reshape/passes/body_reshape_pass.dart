import 'dart:typed_data';
import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../models/warp_field.dart';
import '../../warp/models/control_point.dart';
import '../maps/influence_map.dart';
import '../maps/protection_maps.dart';
import '../mesh/adaptive_body_mesh.dart';
import '../mesh/mesh_optimizer.dart';
import '../models/body_frame_assets.dart';
import '../models/warp_plan.dart';
import 'pass_profiler.dart';

/// Contexto compartilhado entre passes do Body Reshape V2.
class BodyPassContext {
  BodyPassContext({
    required this.imageSize,
    required this.config,
    required this.profiler,
    this.field,
    this.sourceMesh,
    this.optimizedMesh,
    this.vertexDisplacements,
    this.controlPoints = const [],
    this.assets,
    this.plan,
    this.influenceMap,
    this.protectionMaps,
    this.region = MeshRegion.torso,
  });

  final Size imageSize;
  final BodyMultiPassConfig config;
  final PassProfiler profiler;
  WarpField? field;
  AdaptiveBodyMesh? sourceMesh;
  AdaptiveBodyMesh? optimizedMesh;
  VertexDisplacementField? vertexDisplacements;
  List<ControlPoint> controlPoints;
  BodyFrameAssets? assets;
  WarpPlan? plan;
  InfluenceMap? influenceMap;
  ProtectionMaps? protectionMaps;
  MeshRegion region;

  /// Buffers intermediários nomeados (telemetria / debug).
  final Map<String, Float32List> intermediateBuffers = {};

  WarpField get requireField {
    final current = field;
    if (current == null) {
      throw StateError('BodyPassContext.field is null');
    }
    return current;
  }
}

/// Contrato de um passe independente e testável.
abstract class BodyReshapePass {
  String get id;

  /// Se false, o passe é pulado e registrado no profiler.
  bool isEnabled(BodyMultiPassConfig config);

  WarpField run(BodyPassContext context);
}
