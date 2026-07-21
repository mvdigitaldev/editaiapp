import 'dart:typed_data';

import 'adaptive_preview_policy.dart';

/// Região retangular de um tile na imagem completa.
class ImageTileSpec {
  const ImageTileSpec({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

/// Divide RGBA em tiles de no máximo [AdaptivePreviewPolicy.tileSizePx].
abstract final class ImageTileGrid {
  static List<ImageTileSpec> specsFor({
    required int fullWidth,
    required int fullHeight,
    int tileSize = AdaptivePreviewPolicy.tileSizePx,
  }) {
    final specs = <ImageTileSpec>[];
    for (var top = 0; top < fullHeight; top += tileSize) {
      for (var left = 0; left < fullWidth; left += tileSize) {
        final width = (left + tileSize > fullWidth) ? fullWidth - left : tileSize;
        final height = (top + tileSize > fullHeight) ? fullHeight - top : tileSize;
        specs.add(
          ImageTileSpec(left: left, top: top, width: width, height: height),
        );
      }
    }
    return specs;
  }

  static Uint8List extractTile({
    required Uint8List fullRgba,
    required int fullWidth,
    required int fullHeight,
    required ImageTileSpec tile,
  }) {
    final expected = fullWidth * fullHeight * 4;
    if (fullRgba.length != expected) {
      throw StateError('full_rgba_size_mismatch');
    }

    final tileBytes = Uint8List(tile.width * tile.height * 4);
    var dst = 0;
    for (var y = 0; y < tile.height; y++) {
      final srcRow = ((tile.top + y) * fullWidth + tile.left) * 4;
      final rowBytes = fullRgba.sublist(srcRow, srcRow + tile.width * 4);
      tileBytes.setRange(dst, dst + rowBytes.length, rowBytes);
      dst += rowBytes.length;
    }
    return tileBytes;
  }

  static void writeTile({
    required Uint8List fullRgba,
    required int fullWidth,
    required ImageTileSpec tile,
    required Uint8List tileRgba,
  }) {
    final expectedTile = tile.width * tile.height * 4;
    if (tileRgba.length != expectedTile) {
      throw StateError('tile_rgba_size_mismatch');
    }

    var src = 0;
    for (var y = 0; y < tile.height; y++) {
      final dstRow = ((tile.top + y) * fullWidth + tile.left) * 4;
      fullRgba.setRange(dstRow, dstRow + tile.width * 4, tileRgba, src);
      src += tile.width * 4;
    }
  }
}
