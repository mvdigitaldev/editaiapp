import 'dart:math' as math;
import 'dart:typed_data';

import 'adaptive_preview_policy.dart';
import '../body_reshape/rendering/memory_budget.dart';

/// Região retangular de um tile na imagem completa.
///
/// [left]/[top]/[width]/[height] descrevem a região **interior** (escrita).
/// Pads definem o halo expandido amostrado no remap (Sprint 13 — sem costuras).
class ImageTileSpec {
  const ImageTileSpec({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.padLeft = 0,
    this.padTop = 0,
    this.padRight = 0,
    this.padBottom = 0,
  });

  final int left;
  final int top;
  final int width;
  final int height;
  final int padLeft;
  final int padTop;
  final int padRight;
  final int padBottom;

  int get expandLeft => left - padLeft;
  int get expandTop => top - padTop;
  int get expandWidth => padLeft + width + padRight;
  int get expandHeight => padTop + height + padBottom;

  bool get hasHalo =>
      padLeft > 0 || padTop > 0 || padRight > 0 || padBottom > 0;
}

/// Divide RGBA em tiles de no máximo [AdaptivePreviewPolicy.tileSizePx].
abstract final class ImageTileGrid {
  static List<ImageTileSpec> specsFor({
    required int fullWidth,
    required int fullHeight,
    int tileSize = AdaptivePreviewPolicy.tileSizePx,
    int haloPx = 0,
  }) {
    final specs = <ImageTileSpec>[];
    for (var top = 0; top < fullHeight; top += tileSize) {
      for (var left = 0; left < fullWidth; left += tileSize) {
        final width =
            (left + tileSize > fullWidth) ? fullWidth - left : tileSize;
        final height =
            (top + tileSize > fullHeight) ? fullHeight - top : tileSize;
        final padLeft = math.min(haloPx, left);
        final padTop = math.min(haloPx, top);
        final padRight = math.min(haloPx, fullWidth - (left + width));
        final padBottom = math.min(haloPx, fullHeight - (top + height));
        specs.add(
          ImageTileSpec(
            left: left,
            top: top,
            width: width,
            height: height,
            padLeft: padLeft,
            padTop: padTop,
            padRight: padRight,
            padBottom: padBottom,
          ),
        );
      }
    }
    return specs;
  }

  /// Halo derivado do deslocamento máximo do campo (clamp em [MemoryBudget]).
  static int haloForFieldDisplacement(double maxDisplacementPx) =>
      MemoryBudget.haloForMaxDisplacement(maxDisplacementPx);

  static Uint8List extractTile({
    required Uint8List fullRgba,
    required int fullWidth,
    required int fullHeight,
    required ImageTileSpec tile,
  }) {
    return extractExpandedTile(
      fullRgba: fullRgba,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      tile: tile,
    );
  }

  /// Extrai a região expandida (interior + halo).
  static Uint8List extractExpandedTile({
    required Uint8List fullRgba,
    required int fullWidth,
    required int fullHeight,
    required ImageTileSpec tile,
  }) {
    final expected = fullWidth * fullHeight * 4;
    if (fullRgba.length != expected) {
      throw StateError('full_rgba_size_mismatch');
    }

    final ew = tile.expandWidth;
    final eh = tile.expandHeight;
    final el = tile.expandLeft;
    final et = tile.expandTop;
    final tileBytes = Uint8List(ew * eh * 4);
    var dst = 0;
    for (var y = 0; y < eh; y++) {
      final srcRow = ((et + y) * fullWidth + el) * 4;
      final rowBytes = fullRgba.sublist(srcRow, srcRow + ew * 4);
      tileBytes.setRange(dst, dst + rowBytes.length, rowBytes);
      dst += rowBytes.length;
    }
    return tileBytes;
  }

  /// Escreve apenas a região interior (descarta halo).
  static void writeTile({
    required Uint8List fullRgba,
    required int fullWidth,
    required ImageTileSpec tile,
    required Uint8List tileRgba,
  }) {
    writeInteriorFromExpanded(
      fullRgba: fullRgba,
      fullWidth: fullWidth,
      tile: tile,
      expandedRgba: tileRgba,
    );
  }

  static void writeInteriorFromExpanded({
    required Uint8List fullRgba,
    required int fullWidth,
    required ImageTileSpec tile,
    required Uint8List expandedRgba,
  }) {
    final expectedExpanded = tile.expandWidth * tile.expandHeight * 4;
    if (expandedRgba.length != expectedExpanded) {
      throw StateError('tile_rgba_size_mismatch');
    }

    final ew = tile.expandWidth;
    for (var y = 0; y < tile.height; y++) {
      final srcRow =
          ((tile.padTop + y) * ew + tile.padLeft) * 4;
      final dstRow = ((tile.top + y) * fullWidth + tile.left) * 4;
      fullRgba.setRange(
        dstRow,
        dstRow + tile.width * 4,
        expandedRgba,
        srcRow,
      );
    }
  }
}
