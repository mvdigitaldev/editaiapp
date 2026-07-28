import 'dart:ui';

import '../../body_reshape/maps/influence_map.dart';
import '../../body_reshape/maps/protection_maps.dart';
import '../../body_reshape/models/body_adjustment.dart';
import '../../body_reshape/models/body_frame_assets.dart';
import '../../models/pose_result.dart';
import '../../models/tri_mesh.dart';
import '../../segment/person_mask.dart';

/// Contexto para filtros warp corporais (Sprint 18–20).
///
/// Campos V2 ([protectionMaps], [influenceMap], [frameAssets], [adjustment])
/// alimentam o Influence Map adaptativo sem alterar o caminho MLS legado.
class BodyWarpContext {
  const BodyWarpContext({
    required this.mesh,
    required this.pose,
    required this.imageSize,
    required this.intensity,
    required this.confidenceFactor,
    this.personMask,
    this.protectionMaps,
    this.influenceMap,
    this.frameAssets,
    this.adjustment,
  });

  final TriMesh mesh;
  final PoseResult pose;
  final Size imageSize;
  final double intensity;
  final double confidenceFactor;
  final PersonMask? personMask;
  final ProtectionMaps? protectionMaps;
  final InfluenceMap? influenceMap;
  final BodyFrameAssets? frameAssets;
  final BodyAdjustment? adjustment;

  double get effectiveIntensity =>
      (intensity * confidenceFactor).clamp(0.0, 1.0);

  double get centerX => imageSize.width * 0.5;

  BodyWarpContext copyWith({
    TriMesh? mesh,
    PoseResult? pose,
    Size? imageSize,
    double? intensity,
    double? confidenceFactor,
    PersonMask? personMask,
    ProtectionMaps? protectionMaps,
    InfluenceMap? influenceMap,
    BodyFrameAssets? frameAssets,
    BodyAdjustment? adjustment,
  }) {
    return BodyWarpContext(
      mesh: mesh ?? this.mesh,
      pose: pose ?? this.pose,
      imageSize: imageSize ?? this.imageSize,
      intensity: intensity ?? this.intensity,
      confidenceFactor: confidenceFactor ?? this.confidenceFactor,
      personMask: personMask ?? this.personMask,
      protectionMaps: protectionMaps ?? this.protectionMaps,
      influenceMap: influenceMap ?? this.influenceMap,
      frameAssets: frameAssets ?? this.frameAssets,
      adjustment: adjustment ?? this.adjustment,
    );
  }
}
