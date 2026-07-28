import 'dart:ui';

import '../../models/warp_field.dart';
import '../maps/influence_map.dart';
import '../models/body_reshape_request.dart';
import '../protection/rigidity_map.dart';
import 'render_capabilities.dart';

/// Plano de execução do preview de warp (orquestração, não deformação).
///
/// Empacota o [WarpField] e mapas auxiliares para o backend FragmentProgram.
/// O remap em si ocorre na GPU; este objeto só descreve o que enviar.
class RenderPlan {
  final Size imageSize;
  final WarpField field;
  final InfluenceMap? influenceMap;
  final RigidityMap? protectionMap;
  final WarpQualityProfile qualityProfile;
  final RenderCapabilities capabilities;
  final String shaderAsset;

  const RenderPlan({
    required this.imageSize,
    required this.field,
    this.influenceMap,
    this.protectionMap,
    this.qualityProfile = WarpQualityProfile.preview,
    this.capabilities = const RenderCapabilities(),
    this.shaderAsset = BodyReshapeShaders.remap,
  });

  /// Preview V2: displacement + máscara do campo, influência e proteção opcionais.
  factory RenderPlan.previewBodyReshape({
    required WarpField field,
    InfluenceMap? influenceMap,
    RigidityMap? protectionMap,
    RenderCapabilities capabilities = const RenderCapabilities(),
  }) {
    return RenderPlan(
      imageSize: field.imageSize,
      field: field,
      influenceMap: influenceMap,
      protectionMap: protectionMap ?? field.rigidityMap,
      qualityProfile: WarpQualityProfile.preview,
      capabilities: capabilities,
      shaderAsset: BodyReshapeShaders.remap,
    );
  }

  bool get isIdentity => field.isIdentity;

  bool get shouldUseGpu => capabilities.usesGpuPreview && !isIdentity;

  bool get hasInfluence =>
      capabilities.influenceMaps &&
      influenceMap != null &&
      !influenceMap!.isIdentity;

  bool get hasProtection =>
      capabilities.protectionMaps &&
      protectionMap != null &&
      !protectionMap!.isEmpty &&
      protectionMap!.maxValue > 1e-6;

  RenderPlan copyWith({
    Size? imageSize,
    WarpField? field,
    InfluenceMap? influenceMap,
    RigidityMap? protectionMap,
    WarpQualityProfile? qualityProfile,
    RenderCapabilities? capabilities,
    String? shaderAsset,
    bool clearInfluence = false,
    bool clearProtection = false,
  }) {
    return RenderPlan(
      imageSize: imageSize ?? this.imageSize,
      field: field ?? this.field,
      influenceMap:
          clearInfluence ? null : (influenceMap ?? this.influenceMap),
      protectionMap:
          clearProtection ? null : (protectionMap ?? this.protectionMap),
      qualityProfile: qualityProfile ?? this.qualityProfile,
      capabilities: capabilities ?? this.capabilities,
      shaderAsset: shaderAsset ?? this.shaderAsset,
    );
  }
}

/// Asset keys dos shaders Body Reshape registrados no pubspec.
abstract class BodyReshapeShaders {
  static const remap =
      'lib/features/editor/beauty_engine/shaders/body_reshape_remap.frag';
}
