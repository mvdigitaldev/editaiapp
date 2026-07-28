import 'dart:typed_data';

import '../../models/warp_field.dart';
import '../maps/influence_map.dart';
import '../protection/rigidity_map.dart';
import 'render_capabilities.dart';
import 'render_plan.dart';
import 'warp_texture.dart';

/// Backend usado no último remap de export (explícito — nunca silencioso).
enum ExportWarpBackendKind {
  /// FragmentProgram / Impeller (sem loop Dart).
  fragmentProgram,

  /// Metal compute/render (iOS).
  metal,

  /// Vulkan compute ou fallback OpenGL ES/FBO (Android).
  vulkanOrGles,

  /// CPU Dart — somente com [ExportWarpRequest.allowCpuFallback] = true.
  cpuExplicit,
}

/// Capacidades do caminho de export nativo / GPU.
class ExportWarpCapabilities {
  final bool fragmentProgram;
  final bool metal;
  final bool vulkan;
  final bool openGlEs;
  final bool nativeJpegEncode;
  final bool forceCpuFallback;

  const ExportWarpCapabilities({
    this.fragmentProgram = false,
    this.metal = false,
    this.vulkan = false,
    this.openGlEs = false,
    this.nativeJpegEncode = false,
    this.forceCpuFallback = false,
  });

  static const unavailable = ExportWarpCapabilities();

  bool get hasGpuExport =>
      !forceCpuFallback && (fragmentProgram || metal || vulkan || openGlEs);

  bool get hasNativeGpu => metal || vulkan || openGlEs;

  String get preferredBackendLabel {
    if (forceCpuFallback) {
      return 'cpu_explicit';
    }
    if (metal) {
      return 'metal';
    }
    if (vulkan) {
      return 'vulkan';
    }
    if (openGlEs) {
      return 'gles';
    }
    if (fragmentProgram) {
      return 'fragment_program';
    }
    return 'none';
  }
}

/// Handle opaco de recurso GPU no lado nativo (pool).
class OpaqueExportResource {
  final String id;
  final int width;
  final int height;
  final ExportWarpBackendKind backend;

  const OpaqueExportResource({
    required this.id,
    required this.width,
    required this.height,
    required this.backend,
  });
}

/// Pedido de remap de export (full-frame ou tile com origem global).
class ExportWarpRequest {
  final Uint8List rgba;
  final int width;
  final int height;
  final WarpField field;
  final InfluenceMap? influenceMap;
  final RigidityMap? protectionMap;
  final RenderPlan? plan;

  /// Origem do tile na imagem completa (0,0 = full-frame).
  final double tileOriginX;
  final double tileOriginY;

  /// Tamanho da imagem completa (default = width/height do buffer).
  final double? fullWidth;
  final double? fullHeight;

  /// Fonte completa para o fallback CPU de um tile.
  ///
  /// GPU recebe apenas o tile expandido; CPU precisa da imagem integral para
  /// amostrar as coordenadas globais sem transformar cada tile em uma imagem
  /// independente.
  final Uint8List? fullSourceRgba;

  /// Se true, permite [WarpCpuRemap] como último recurso (explícito).
  final bool allowCpuFallback;

  const ExportWarpRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.field,
    this.influenceMap,
    this.protectionMap,
    this.plan,
    this.tileOriginX = 0,
    this.tileOriginY = 0,
    this.fullWidth,
    this.fullHeight,
    this.fullSourceRgba,
    this.allowCpuFallback = false,
  });

  double get resolvedFullWidth => fullWidth ?? width.toDouble();
  double get resolvedFullHeight => fullHeight ?? height.toDouble();

  bool get isFullFrame =>
      tileOriginX == 0 &&
      tileOriginY == 0 &&
      resolvedFullWidth == width &&
      resolvedFullHeight == height;
}

/// Resultado do remap de export.
class ExportWarpResult {
  final Uint8List rgba;
  final int width;
  final int height;
  final ExportWarpBackendKind backend;
  final bool usedCpuFallback;

  const ExportWarpResult({
    required this.rgba,
    required this.width,
    required this.height,
    required this.backend,
    this.usedCpuFallback = false,
  });
}

/// Contrato de backend de export nativo (Metal / Vulkan / GLES).
///
/// Não realiza remap pixel-a-pixel em Dart. Recebe RGBA + mapas empacotados
/// e devolve RGBA (ou handle opaco liberável).
abstract class NativeExportBackend {
  Future<ExportWarpCapabilities> probe();

  /// Remap GPU nativo. Retorna null se indisponível / falha (caller decide fallback).
  Future<Uint8List?> warpExport(ExportWarpRequest request);

  /// Encode JPEG nativo quando disponível.
  Future<Uint8List?> encodeJpeg({
    required Uint8List rgba,
    required int width,
    required int height,
    int quality = 90,
  });

  /// Libera recurso opaco (no-op se o backend só usa bytes).
  Future<void> release(OpaqueExportResource resource);

  void dispose();
}

/// Empacota [WarpField] para o canal nativo (mesmo encoding do preview).
class NativeWarpPayload {
  final Uint8List displacementRgba;
  final int displacementWidth;
  final int displacementHeight;
  final double displacementScaleX;
  final double displacementScaleY;
  final Uint8List maskRgba;
  final int maskWidth;
  final int maskHeight;
  final Uint8List? influenceRgba;
  final int? influenceWidth;
  final int? influenceHeight;
  final Uint8List? protectionRgba;
  final int? protectionWidth;
  final int? protectionHeight;

  const NativeWarpPayload({
    required this.displacementRgba,
    required this.displacementWidth,
    required this.displacementHeight,
    required this.displacementScaleX,
    required this.displacementScaleY,
    required this.maskRgba,
    required this.maskWidth,
    required this.maskHeight,
    this.influenceRgba,
    this.influenceWidth,
    this.influenceHeight,
    this.protectionRgba,
    this.protectionWidth,
    this.protectionHeight,
  });

  factory NativeWarpPayload.fromPlan(RenderPlan plan) {
    final displacement = WarpTexture.fromDisplacement(
      plan.field,
      scalePx: plan.displacementScalePx,
    );
    final mask = WarpTexture.fromMask(plan.field);
    final influence = plan.hasInfluence
        ? WarpTexture.fromInfluenceMap(plan.influenceMap!)
        : null;
    final protection = plan.hasProtection
        ? WarpTexture.fromRigidityMap(plan.protectionMap!)
        : null;
    return NativeWarpPayload(
      displacementRgba: displacement.rgba,
      displacementWidth: displacement.width,
      displacementHeight: displacement.height,
      displacementScaleX: displacement.displacementScalePx.dx,
      displacementScaleY: displacement.displacementScalePx.dy,
      maskRgba: mask.rgba,
      maskWidth: mask.width,
      maskHeight: mask.height,
      influenceRgba: influence?.rgba,
      influenceWidth: influence?.width,
      influenceHeight: influence?.height,
      protectionRgba: protection?.rgba,
      protectionWidth: protection?.width,
      protectionHeight: protection?.height,
    );
  }

  Map<String, Object> toChannelArgs() => {
        'displacement': displacementRgba,
        'displacementWidth': displacementWidth,
        'displacementHeight': displacementHeight,
        'displacementScaleX': displacementScaleX,
        'displacementScaleY': displacementScaleY,
        'mask': maskRgba,
        'maskWidth': maskWidth,
        'maskHeight': maskHeight,
        if (influenceRgba != null) 'influence': influenceRgba!,
        if (influenceWidth != null) 'influenceWidth': influenceWidth!,
        if (influenceHeight != null) 'influenceHeight': influenceHeight!,
        if (protectionRgba != null) 'protection': protectionRgba!,
        if (protectionWidth != null) 'protectionWidth': protectionWidth!,
        if (protectionHeight != null) 'protectionHeight': protectionHeight!,
      };
}

/// Extensão de capacidades de render para export (Sprint 13).
extension RenderCapabilitiesExport on RenderCapabilities {
  RenderCapabilities withExport({
    bool nativeExport = false,
    bool tiledHalo = true,
  }) {
    return copyWith(
      fragmentProgramWarp: fragmentProgramWarp || nativeExport,
    );
  }
}
