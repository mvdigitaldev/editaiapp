import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/rendering/pass_warp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('warpChangedPixels detects meaningful diff', () {
    final a = Uint8List(256)..fillRange(0, 256, 10);
    final b = Uint8List.fromList(a);
    b[0] = 100;
    b[1] = 100;
    b[2] = 100;
    expect(PassWarp.warpChangedPixels(a, b, minAccumDiff: 50), isTrue);
  });

  test('warpChangedPixels rejects identical buffers', () {
    final a = Uint8List.fromList(List.filled(400, 128));
    expect(PassWarp.warpChangedPixels(a, a), isFalse);
  });
}
