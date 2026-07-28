import 'dart:typed_data';

import '../../models/warp_field.dart';
import '../../warp/warp_cpu_remap.dart';
import '../maps/influence_map.dart';
import '../protection/rigidity_map.dart';
import 'fragment_program_warp_backend.dart';
import 'native_export_backend.dart';
import 'render_capabilities.dart';
import 'render_plan.dart';

/// Orquestra remap de export sem loop pixel-a-pixel em Dart (Sprint 13).
///
/// Ordem: native Metal/Vulkan/GLES → FragmentProgram → CPU explícito (opt-in).
class ExportWarp {
  ExportWarp({
    FragmentProgramWarpBackend? fragmentBackend,
    NativeExportBackend? nativeBackend,
    WarpCpuRemap cpuRemap = const WarpCpuRemap(),
  })  : _fragmentBackend = fragmentBackend ?? FragmentProgramWarpBackend.shared,
        _nativeBackend = nativeBackend,
        _cpuRemap = cpuRemap;

  final FragmentProgramWarpBackend _fragmentBackend;
  final NativeExportBackend? _nativeBackend;
  final WarpCpuRemap _cpuRemap;

  ExportWarpBackendKind? lastBackend;
  bool lastUsedCpuFallback = false;

  Future<ExportWarpCapabilities> probe() async {
    await _fragmentBackend.initialize();
    final native = _nativeBackend == null
        ? ExportWarpCapabilities.unavailable
        : await _nativeBackend!.probe();
    return ExportWarpCapabilities(
      fragmentProgram: _fragmentBackend.isAvailable,
      metal: native.metal,
      vulkan: native.vulkan,
      openGlEs: native.openGlEs,
      nativeJpegEncode: native.nativeJpegEncode,
      forceCpuFallback: _fragmentBackend.capabilities.forceCpuFallback &&
          !native.hasNativeGpu,
    );
  }

  /// Aplica remap. Lança [StateError] se GPU falhar e CPU não for permitido.
  Future<ExportWarpResult> apply(ExportWarpRequest request) async {
    if (request.field.isIdentity) {
      lastBackend = ExportWarpBackendKind.fragmentProgram;
      lastUsedCpuFallback = false;
      return ExportWarpResult(
        rgba: Uint8List.fromList(request.rgba),
        width: request.width,
        height: request.height,
        backend: ExportWarpBackendKind.fragmentProgram,
      );
    }

    final plan = request.plan ??
        RenderPlan.exportBodyReshape(
          field: request.field,
          influenceMap: request.influenceMap,
          protectionMap: request.protectionMap,
          capabilities: RenderCapabilities.gpuPreview,
          tileOriginX: request.tileOriginX,
          tileOriginY: request.tileOriginY,
          fullWidth: request.resolvedFullWidth,
          fullHeight: request.resolvedFullHeight,
        );

    final native = _nativeBackend;
    if (native != null) {
      final caps = await native.probe();
      if (caps.hasNativeGpu) {
        final warped = await native.warpExport(
          ExportWarpRequest(
            rgba: request.rgba,
            width: request.width,
            height: request.height,
            field: request.field,
            influenceMap: request.influenceMap,
            protectionMap: request.protectionMap,
            plan: plan,
            tileOriginX: request.tileOriginX,
            tileOriginY: request.tileOriginY,
            fullWidth: request.fullWidth,
            fullHeight: request.fullHeight,
            fullSourceRgba: request.fullSourceRgba,
            allowCpuFallback: false,
          ),
        );
        if (warped != null && warped.length == request.rgba.length) {
          final kind = caps.metal
              ? ExportWarpBackendKind.metal
              : (caps.vulkan
                  ? ExportWarpBackendKind.vulkanOrGles
                  : ExportWarpBackendKind.vulkanOrGles);
          lastBackend = kind;
          lastUsedCpuFallback = false;
          return ExportWarpResult(
            rgba: warped,
            width: request.width,
            height: request.height,
            backend: kind,
          );
        }
      }
    }

    await _fragmentBackend.initialize();
    if (_fragmentBackend.isAvailable) {
      final warped = await _fragmentBackend.applyPlan(
        rgba: request.rgba,
        width: request.width,
        height: request.height,
        plan: plan,
      );
      if (warped != null && warped.length == request.rgba.length) {
        lastBackend = ExportWarpBackendKind.fragmentProgram;
        lastUsedCpuFallback = false;
        return ExportWarpResult(
          rgba: warped,
          width: request.width,
          height: request.height,
          backend: ExportWarpBackendKind.fragmentProgram,
        );
      }
    }

    if (!request.allowCpuFallback) {
      throw StateError(
        'export_warp_gpu_unavailable: '
        'FragmentProgram/native failed and allowCpuFallback=false',
      );
    }

    final cpu = request.isFullFrame
        ? _cpuRemap.apply(
            rgba: request.rgba,
            width: request.width,
            height: request.height,
            field: request.field,
          )
        : _applyCpuTile(request);
    lastBackend = ExportWarpBackendKind.cpuExplicit;
    lastUsedCpuFallback = true;
    return ExportWarpResult(
      rgba: cpu,
      width: request.width,
      height: request.height,
      backend: ExportWarpBackendKind.cpuExplicit,
      usedCpuFallback: true,
    );
  }

  Uint8List _applyCpuTile(ExportWarpRequest request) {
    final full = request.fullSourceRgba;
    final fullWidth = request.resolvedFullWidth.round();
    final fullHeight = request.resolvedFullHeight.round();
    if (full == null || full.length != fullWidth * fullHeight * 4) {
      throw StateError(
        'export_warp_cpu_tile_requires_full_source: '
        'tiled CPU remap must sample global source coordinates',
      );
    }
    return _cpuRemap.applyGlobal(
      tileRgba: request.rgba,
      tileWidth: request.width,
      tileHeight: request.height,
      offsetX: request.tileOriginX.round(),
      offsetY: request.tileOriginY.round(),
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      field: request.field,
      fullRgba: full,
    );
  }

  /// Atalho full-frame.
  Future<ExportWarpResult> applyField({
    required Uint8List rgba,
    required int width,
    required int height,
    required WarpField field,
    InfluenceMap? influenceMap,
    RigidityMap? protectionMap,
    bool allowCpuFallback = false,
  }) {
    return apply(
      ExportWarpRequest(
        rgba: rgba,
        width: width,
        height: height,
        field: field,
        influenceMap: influenceMap,
        protectionMap: protectionMap,
        allowCpuFallback: allowCpuFallback,
      ),
    );
  }

  Future<Uint8List?> encodeJpegNative({
    required Uint8List rgba,
    required int width,
    required int height,
    int quality = 90,
  }) async {
    return _nativeBackend?.encodeJpeg(
      rgba: rgba,
      width: width,
      height: height,
      quality: quality,
    );
  }

  void dispose() {
    _nativeBackend?.dispose();
  }
}
