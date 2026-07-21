import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/performance/image_tile_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ImageTileGrid extract and write round-trip', () {
    final full = Uint8List(4 * 4 * 4);
    for (var i = 0; i < full.length; i++) {
      full[i] = i % 256;
    }

    final specs = ImageTileGrid.specsFor(fullWidth: 4, fullHeight: 4, tileSize: 2);
    expect(specs, hasLength(4));

    final output = Uint8List.fromList(full);
    for (final tile in specs) {
      final extracted = ImageTileGrid.extractTile(
        fullRgba: full,
        fullWidth: 4,
        fullHeight: 4,
        tile: tile,
      );
      extracted[0] = 255;
      ImageTileGrid.writeTile(
        fullRgba: output,
        fullWidth: 4,
        tile: tile,
        tileRgba: extracted,
      );
    }

    expect(output, isNot(equals(full)));
  });
}
