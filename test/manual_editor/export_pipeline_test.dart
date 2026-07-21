import 'dart:typed_data';

import 'package:editaiapp/features/editor/manual_editor/data/export_pipeline.dart';
import 'package:editaiapp/features/editor/manual_editor/data/filter_presets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('manualEditorFilterPresets', () {
    test('exposes at least 15 filter presets', () {
      expect(manualEditorFilterPresets.length, greaterThanOrEqualTo(15));
    });
  });

  group('ExportPipeline', () {
    test('processEditedJpeg returns jpeg with valid dimensions', () async {
      final source = img.Image(width: 32, height: 24);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(x, y, 120, 80, 40);
        }
      }
      final input = Uint8List.fromList(img.encodeJpg(source));

      final pipeline = ExportPipeline();
      final result = await pipeline.processEditedJpeg(input);

      expect(result.width, 32);
      expect(result.height, 24);
      expect(result.mimeType, 'image/jpeg');
      expect(result.bytes.length, greaterThan(100));
      expect(result.bytes[0], 0xFF);
      expect(result.bytes[1], 0xD8);
    });
  });
}
