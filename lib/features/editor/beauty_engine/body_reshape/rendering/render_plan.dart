import 'dart:ui';

import '../../models/warp_field.dart';
import '../maps/influence_map.dart';
import '../models/body_reshape_request.dart';
import '../protection/rigidity_map.dart';
import 'render_capabilities.dart';
import 'warp_texture.dart';

/// Plano de execução do preview/export de warp (orquestração, não deformação).
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

  /// Faixa local (px) usada para codificar displacement RGBA8.
  final Offset displacementScalePx;

  /// Origem do tile na imagem completa (export tiled — Sprint 13).
  final double tileOriginX;
  final double tileOriginY;

  /// Dimensão da imagem completa (pode diferir do buffer do tile).
  final double fullWidth;
  final double fullHeight;

  RenderPlan({
    required this.imageSize,
    required this.field,
    this.influenceMap,
    this.protectionMap,
    this.qualityProfile = WarpQualityProfile.preview,
    this.capabilities = const RenderCapabilities(),
    this.shaderAsset = BodyReshapeShaders.remap,
    Offset? displacementScalePx,
    this.tileOriginX = 0,
    this.tileOriginY = 0,
    double? fullWidth,
    double? fullHeight,
  })  : displacementScalePx =
            displacementScalePx ?? WarpTexture.displacementScaleFor(field),
        fullWidth = fullWidth ?? imageSize.width,
        fullHeight = fullHeight ?? imageSize.height;

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

  /// Export V2 (full-frame ou tile com origem global).
  factory RenderPlan.exportBodyReshape({
    required WarpField field,
    InfluenceMap? influenceMap,
    RigidityMap? protectionMap,
    RenderCapabilities capabilities = const RenderCapabilities(),
    double tileOriginX = 0,
    double tileOriginY = 0,
    double? fullWidth,
    double? fullHeight,
  }) {
    final fw = fullWidth ?? field.imageSize.width;
    final fh = fullHeight ?? field.imageSize.height;
    return RenderPlan(
      imageSize: field.imageSize,
      field: field,
      influenceMap: influenceMap,
      protectionMap: protectionMap ?? field.rigidityMap,
      qualityProfile: WarpQualityProfile.export,
      capabilities: capabilities,
      shaderAsset: BodyReshapeShaders.remap,
      tileOriginX: tileOriginX,
      tileOriginY: tileOriginY,
      fullWidth: fw,
      fullHeight: fh,
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

  bool get isTiledDraw =>
      tileOriginX != 0 ||
      tileOriginY != 0 ||
      fullWidth != imageSize.width ||
      fullHeight != imageSize.height;

  RenderPlan copyWith({
    Size? imageSize,
    WarpField? field,
    InfluenceMap? influenceMap,
    RigidityMap? protectionMap,
    WarpQualityProfile? qualityProfile,
    RenderCapabilities? capabilities,
    String? shaderAsset,
    Offset? displacementScalePx,
    double? tileOriginX,
    double? tileOriginY,
    double? fullWidth,
    double? fullHeight,
    bool clearInfluence = false,
    bool clearProtection = false,
  }) {
    return RenderPlan(
      imageSize: imageSize ?? this.imageSize,
      field: field ?? this.field,
      influenceMap: clearInfluence ? null : (influenceMap ?? this.influenceMap),
      protectionMap:
          clearProtection ? null : (protectionMap ?? this.protectionMap),
      qualityProfile: qualityProfile ?? this.qualityProfile,
      capabilities: capabilities ?? this.capabilities,
      shaderAsset: shaderAsset ?? this.shaderAsset,
      displacementScalePx: displacementScalePx ?? this.displacementScalePx,
      tileOriginX: tileOriginX ?? this.tileOriginX,
      tileOriginY: tileOriginY ?? this.tileOriginY,
      fullWidth: fullWidth ?? this.fullWidth,
      fullHeight: fullHeight ?? this.fullHeight,
    );
  }
}

/// Asset keys dos shaders Body Reshape registrados no pubspec.
abstract class BodyReshapeShaders {
  static const remap =
      'lib/features/editor/beauty_engine/shaders/body_reshape_remap.frag';
}
