import 'dart:typed_data';
import 'dart:ui';

import '../body_reshape/rendering/export_warp.dart';
import '../body_reshape/rendering/memory_budget.dart';
import '../body_reshape/rendering/method_channel_native_export_backend.dart';
import '../body_reshape/rendering/native_export_backend.dart';
import '../config/face_warp_v3_config.dart';
import '../controllers/beauty_engine_controller.dart';
import '../models/image_source.dart';
import '../models/image_source_rgba.dart';
import '../models/processing_pipeline.dart';
import '../models/warp_field.dart';
import '../performance/adaptive_preview_policy.dart';
import '../performance/beauty_profiler.dart';
import '../performance/image_tile_grid.dart';
import '../performance/thermal_degradation_policy.dart';
import '../performance/thermal_monitor.dart';
import '../rendering/export_encoder.dart';
import '../rendering/gpu_texture_store.dart';
import '../warp/face_mesh_export_warp.dart';
import '../warp/warp_field_builder.dart';

/// Export tiled para imagens > 8MP (Sprint 25 + Sprint 13 GPU/halo).
///
/// Remap via [ExportWarp] (FragmentProgram / Metal / GLES) — sem loop
/// pixel-a-pixel em Dart no caminho feliz. Halo global evita costuras.
class TiledExportEngine {
  TiledExportEngine({
    this.exportEncoder = const ExportEncoder(),
    ExportWarp? exportWarp,
    FaceMeshExportWarp? faceMeshExportWarp,
    NativeExportBackend? nativeBackend,
    this.allowCpuFallback = false,
    this.thermalMonitor,
  })  : exportWarp = exportWarp ??
            ExportWarp(
              nativeBackend:
                  nativeBackend ?? MethodChannelNativeExportBackend(),
            ),
        faceMeshExportWarp = faceMeshExportWarp ?? FaceMeshExportWarp();

  final ExportEncoder exportEncoder;
  final ExportWarp exportWarp;
  final FaceMeshExportWarp faceMeshExportWarp;

  /// Fallback CPU explícito (testes / dispositivos sem GPU).
  final bool allowCpuFallback;

  /// Monitor térmico para degradação de export (Sprint 6).
  final ThermalMonitor? thermalMonitor;

  ExportWarpBackendKind? lastWarpBackend;
  int? lastEstimatedPeakBytes;

  bool shouldUseTiledExport(ImageSource source) {
    return AdaptivePreviewPolicy.shouldUseTiledExport(source);
  }

  Future<Uint8List> exportJpeg({
    required BeautyEngineController controller,
    required ImageSource source,
    required ProcessingPipeline pipeline,
    int quality = 90,
    BeautyProfiler? profiler,
  }) async {
    final rgbaSource = ImageSourceRgba.ensureRgba(source);
    if (!shouldUseTiledExport(rgbaSource)) {
      return controller.exportJpeg(
        source: rgbaSource,
        pipeline: pipeline,
        quality: quality,
      );
    }

    profiler?.start('tiled_export_total');

    final profile = controller.deviceProfile;
    final thermal = await (thermalMonitor ?? PlatformThermalMonitor())
        .currentState();
    final degradation = profile != null
        ? ThermalDegradationPolicy.plan(
            profile: profile,
            thermal: thermal,
          )
        : ExportDegradationPlan(
            tileSizePx: AdaptivePreviewPolicy.tileSizePx,
            jpegQualityReduction: 0,
            skipParallelTiles: false,
            thermalState: thermal,
          );
    final effectiveQuality =
        (quality - degradation.jpegQualityReduction).clamp(60, 100);
    final tileSize = degradation.tileSizePx;

    final face = await controller.detectFace(rgbaSource);
    final pose = await controller.detectPose(rgbaSource);
    final personMask = controller.bodyFilterPipeline.hasActiveBodyWarp(
      pipeline.effectiveParameters,
    )
        ? await controller.detectPersonMask(rgbaSource)
        : null;
    final faceParts = face != null &&
            controller.skinFilterPipeline.hasActiveSkin(
              pipeline.effectiveParameters,
            )
        ? await controller.detectFaceParts(rgbaSource)
        : null;
    final faceParsing = face != null &&
            controller.skinFilterPipeline.hasActiveSkin(
              pipeline.effectiveParameters,
            )
        ? await controller.detectFaceParsing(
            rgbaSource,
            face: face,
            parts: faceParts,
          )
        : null;

    final params = pipeline.effectiveParameters;
    final imageSize = Size(
      rgbaSource.width.toDouble(),
      rgbaSource.height.toDouble(),
    );

    final bodyField = controller.composeBodyField(
      pose: pose,
      imageSize: imageSize,
      parameters: params,
      personMask: personMask,
    );
    final faceField = await controller.composeFaceFieldAsync(
      face: face,
      imageSize: imageSize,
      parameters: params,
      quality: WarpFieldQuality.export,
    );
    final faceGpuPayload = FaceWarpV3Config.enabled &&
            FaceWarpV3Config.useMeshWarpV3 &&
            FaceWarpV3Config.useGpuPiecewiseAffine
        ? controller.lastFaceMeshGpuPayload
        : null;

    final maxDisp = mathMaxDisplacement(bodyField, faceField);
    final requiredHaloPx = maxDisp.ceil() + 8;
    if (requiredHaloPx > MemoryBudget.maxTileHaloPx) {
      throw StateError(
        'export_tile_halo_insufficient: required=$requiredHaloPx '
        'max=${MemoryBudget.maxTileHaloPx}',
      );
    }
    final haloPx = ImageTileGrid.haloForFieldDisplacement(maxDisp);
    lastEstimatedPeakBytes = MemoryBudget.estimateTiledExportPeakBytes(
      fullWidth: rgbaSource.width,
      fullHeight: rgbaSource.height,
      tileSize: tileSize,
      haloPx: haloPx,
    );
    if (lastEstimatedPeakBytes! > MemoryBudget.exportPeakBytes) {
      throw StateError(
        'export_memory_budget_exceeded: '
        'estimated=$lastEstimatedPeakBytes '
        'limit=${MemoryBudget.exportPeakBytes}',
      );
    }

    // Um buffer de saída (+ source). Sem terceira cópia full-frame intermediária.
    final output = Uint8List.fromList(rgbaSource.bytes);
    final tiles = ImageTileGrid.specsFor(
      fullWidth: rgbaSource.width,
      fullHeight: rgbaSource.height,
      tileSize: tileSize,
      haloPx: haloPx,
    );

    if (bodyField != null && !bodyField.isIdentity) {
      profiler?.start('body_warp_tiles');
      await _warpTilesToOutput(
        sourceRgba: rgbaSource.bytes,
        output: output,
        fullWidth: rgbaSource.width,
        fullHeight: rgbaSource.height,
        tiles: tiles,
        field: bodyField,
      );
      profiler?.end('body_warp_tiles');
    }

    for (final tile in tiles) {
      profiler?.start('tile');
      var expanded = ImageTileGrid.extractExpandedTile(
        fullRgba: output,
        fullWidth: rgbaSource.width,
        fullHeight: rgbaSource.height,
        tile: tile,
      );

      if (faceField != null && !faceField.isIdentity) {
        Uint8List warpedExpanded;
        if (faceGpuPayload != null && !faceGpuPayload.isIdentity) {
          final meshResult = await faceMeshExportWarp.apply(
            FaceMeshExportRequest(
              rgba: expanded,
              width: tile.expandWidth,
              height: tile.expandHeight,
              payload: faceGpuPayload,
              field: faceField,
              parameters: params,
              tileOriginX: tile.expandLeft.toDouble(),
              tileOriginY: tile.expandTop.toDouble(),
              fullWidth: rgbaSource.width.toDouble(),
              fullHeight: rgbaSource.height.toDouble(),
              applyInpaint: FaceWarpV3Config.usePostWarpInpaint,
              forceCpuInpaint: allowCpuFallback,
            ),
          );
          if (meshResult != null) {
            lastWarpBackend = meshResult.backend;
            warpedExpanded = meshResult.rgba;
          } else {
            final warped = await exportWarp.apply(
              ExportWarpRequest(
                rgba: expanded,
                width: tile.expandWidth,
                height: tile.expandHeight,
                field: faceField,
                tileOriginX: tile.expandLeft.toDouble(),
                tileOriginY: tile.expandTop.toDouble(),
                fullWidth: rgbaSource.width.toDouble(),
                fullHeight: rgbaSource.height.toDouble(),
                fullSourceRgba: output,
                allowCpuFallback: allowCpuFallback,
              ),
            );
            lastWarpBackend = warped.backend;
            warpedExpanded = warped.rgba;
          }
        } else {
          final warped = await exportWarp.apply(
            ExportWarpRequest(
              rgba: expanded,
              width: tile.expandWidth,
              height: tile.expandHeight,
              field: faceField,
              tileOriginX: tile.expandLeft.toDouble(),
              tileOriginY: tile.expandTop.toDouble(),
              fullWidth: rgbaSource.width.toDouble(),
              fullHeight: rgbaSource.height.toDouble(),
              fullSourceRgba: output,
              allowCpuFallback: allowCpuFallback,
            ),
          );
          lastWarpBackend = warped.backend;
          warpedExpanded = warped.rgba;
        }
        expanded = warpedExpanded;
      }

      // Pós-warp só na região interior (evita costura de filtros locais).
      final interior = _cropInterior(expanded, tile);
      final processed = await controller.renderPostWarpRgba(
        rgba: interior,
        width: tile.width,
        height: tile.height,
        pipeline: pipeline,
        params: params,
        face: face,
        imageSize: imageSize,
        faceParts: faceParts,
        faceParsing: faceParsing,
        faceWarp: faceField != null && !faceField.isIdentity ? faceField : null,
        // As máscaras faciais são normalizadas na imagem completa; sem a
        // origem do tile a pele cairia no lugar errado em cada recorte.
        tileOrigin: Offset(tile.left.toDouble(), tile.top.toDouble()),
      );

      _writeInteriorBytes(
        fullRgba: output,
        fullWidth: rgbaSource.width,
        tile: tile,
        interiorRgba: processed,
      );
      profiler?.end('tile');
    }

    profiler?.end('tiled_export_total');

    final nativeJpeg = await exportWarp.encodeJpegNative(
      rgba: output,
      width: rgbaSource.width,
      height: rgbaSource.height,
      quality: effectiveQuality,
    );
    if (nativeJpeg != null && nativeJpeg.isNotEmpty) {
      return nativeJpeg;
    }

    return exportEncoder.encodeJpeg(
      TextureEntry(
        id: 0,
        width: rgbaSource.width,
        height: rgbaSource.height,
        rgba: output,
      ),
      quality: effectiveQuality,
    );
  }

  Future<void> _warpTilesToOutput({
    required Uint8List sourceRgba,
    required Uint8List output,
    required int fullWidth,
    required int fullHeight,
    required List<ImageTileSpec> tiles,
    required WarpField field,
  }) async {
    for (final tile in tiles) {
      final expanded = ImageTileGrid.extractExpandedTile(
        fullRgba: sourceRgba,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        tile: tile,
      );
      final warped = await exportWarp.apply(
        ExportWarpRequest(
          rgba: expanded,
          width: tile.expandWidth,
          height: tile.expandHeight,
          field: field,
          tileOriginX: tile.expandLeft.toDouble(),
          tileOriginY: tile.expandTop.toDouble(),
          fullWidth: fullWidth.toDouble(),
          fullHeight: fullHeight.toDouble(),
          fullSourceRgba: sourceRgba,
          allowCpuFallback: allowCpuFallback,
        ),
      );
      lastWarpBackend = warped.backend;
      ImageTileGrid.writeInteriorFromExpanded(
        fullRgba: output,
        fullWidth: fullWidth,
        tile: tile,
        expandedRgba: warped.rgba,
      );
    }
  }

  static double mathMaxDisplacement(WarpField? a, WarpField? b) {
    var m = 0.0;
    if (a != null && !a.isIdentity) {
      m = a.maxDisplacementMagnitude;
    }
    if (b != null && !b.isIdentity) {
      final bm = b.maxDisplacementMagnitude;
      if (bm > m) {
        m = bm;
      }
    }
    return m;
  }

  static Uint8List _cropInterior(Uint8List expanded, ImageTileSpec tile) {
    final out = Uint8List(tile.width * tile.height * 4);
    final ew = tile.expandWidth;
    var dst = 0;
    for (var y = 0; y < tile.height; y++) {
      final src = ((tile.padTop + y) * ew + tile.padLeft) * 4;
      out.setRange(dst, dst + tile.width * 4, expanded, src);
      dst += tile.width * 4;
    }
    return out;
  }

  static void _writeInteriorBytes({
    required Uint8List fullRgba,
    required int fullWidth,
    required ImageTileSpec tile,
    required Uint8List interiorRgba,
  }) {
    final expected = tile.width * tile.height * 4;
    if (interiorRgba.length != expected) {
      throw StateError('interior_rgba_size_mismatch');
    }
    var src = 0;
    for (var y = 0; y < tile.height; y++) {
      final dstRow = ((tile.top + y) * fullWidth + tile.left) * 4;
      fullRgba.setRange(dstRow, dstRow + tile.width * 4, interiorRgba, src);
      src += tile.width * 4;
    }
  }
}
