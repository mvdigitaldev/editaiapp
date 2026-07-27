import 'dart:typed_data';
import 'dart:ui';

import '../controllers/beauty_engine_controller.dart';
import '../models/image_source.dart';
import '../models/image_source_rgba.dart';
import '../models/processing_pipeline.dart';
import '../performance/adaptive_preview_policy.dart';
import '../performance/beauty_profiler.dart';
import '../performance/image_tile_grid.dart';
import '../rendering/export_encoder.dart';
import '../rendering/gpu_texture_store.dart';
import '../warp/warp_cpu_remap.dart';

/// Export tiled para imagens > 8MP (Sprint 25).
class TiledExportEngine {
  TiledExportEngine({
    this.exportEncoder = const ExportEncoder(),
    this.warpRemap = const WarpCpuRemap(),
  });

  final ExportEncoder exportEncoder;
  final WarpCpuRemap warpRemap;

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

    final face = await controller.detectFace(rgbaSource);
    final pose = await controller.detectPose(rgbaSource);
    final personMask = controller.bodyFilterPipeline.hasActiveBodyWarp(
      pipeline.effectiveParameters,
    )
        ? await controller.detectPersonMask(rgbaSource)
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
    final faceField = controller.composeFaceField(
      face: face,
      imageSize: imageSize,
      parameters: params,
    );

    var warpBuffer = Uint8List.fromList(rgbaSource.bytes);
    final tiles = ImageTileGrid.specsFor(
      fullWidth: rgbaSource.width,
      fullHeight: rgbaSource.height,
    );

    if (bodyField != null && !bodyField.isIdentity) {
      profiler?.start('body_warp_tiles');
      for (final tile in tiles) {
        var tileRgba = ImageTileGrid.extractTile(
          fullRgba: rgbaSource.bytes,
          fullWidth: rgbaSource.width,
          fullHeight: rgbaSource.height,
          tile: tile,
        );
        tileRgba = warpRemap.applyGlobal(
          tileRgba: tileRgba,
          tileWidth: tile.width,
          tileHeight: tile.height,
          offsetX: tile.left,
          offsetY: tile.top,
          fullWidth: rgbaSource.width,
          fullHeight: rgbaSource.height,
          field: bodyField,
          fullRgba: rgbaSource.bytes,
        );
        ImageTileGrid.writeTile(
          fullRgba: warpBuffer,
          fullWidth: rgbaSource.width,
          tile: tile,
          tileRgba: tileRgba,
        );
      }
      profiler?.end('body_warp_tiles');
    }

    final output = Uint8List.fromList(warpBuffer);

    for (final tile in tiles) {
      profiler?.start('tile');
      var tileRgba = ImageTileGrid.extractTile(
        fullRgba: warpBuffer,
        fullWidth: rgbaSource.width,
        fullHeight: rgbaSource.height,
        tile: tile,
      );

      if (faceField != null && !faceField.isIdentity) {
        tileRgba = warpRemap.applyGlobal(
          tileRgba: tileRgba,
          tileWidth: tile.width,
          tileHeight: tile.height,
          offsetX: tile.left,
          offsetY: tile.top,
          fullWidth: rgbaSource.width,
          fullHeight: rgbaSource.height,
          field: faceField,
          fullRgba: warpBuffer,
        );
      }

      tileRgba = await controller.renderPostWarpRgba(
        rgba: tileRgba,
        width: tile.width,
        height: tile.height,
        pipeline: pipeline,
        params: params,
        face: face,
        imageSize: imageSize,
      );

      ImageTileGrid.writeTile(
        fullRgba: output,
        fullWidth: rgbaSource.width,
        tile: tile,
        tileRgba: tileRgba,
      );
      profiler?.end('tile');
    }

    profiler?.end('tiled_export_total');

    return exportEncoder.encodeJpeg(
      TextureEntry(
        id: 0,
        width: rgbaSource.width,
        height: rgbaSource.height,
        rgba: output,
      ),
      quality: quality,
    );
  }
}
