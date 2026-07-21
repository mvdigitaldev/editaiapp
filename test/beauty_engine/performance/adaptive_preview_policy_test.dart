import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/performance/adaptive_preview_policy.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdaptivePreviewPolicy', () {
    test('selfie uses 720p max edge', () {
      final source = ImageSource(
        bytes: Uint8List(640 * 480 * 4),
        width: 640,
        height: 480,
      );

      expect(AdaptivePreviewPolicy.maxEdgeForSource(source), 720);
    });

    test('4MP photo uses 1080p max edge', () {
      final source = ImageSource(
        bytes: Uint8List(2000 * 2000 * 4),
        width: 2000,
        height: 2000,
      );

      expect(AdaptivePreviewPolicy.maxEdgeForSource(source), 1080);
    });

    test('12MP triggers tiled export', () {
      final source = ImageSource(
        bytes: Uint8List(4000 * 3000 * 4),
        width: 4000,
        height: 3000,
      );

      expect(AdaptivePreviewPolicy.shouldUseTiledExport(source), isTrue);
    });
  });
}
