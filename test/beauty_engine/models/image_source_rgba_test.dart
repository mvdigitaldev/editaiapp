import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/models/image_source.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/image_source_rgba.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('ImageSourceRgba', () {
    test('returns same source when bytes already match RGBA size', () {
      final rgba = Uint8List(16);
      final source = ImageSource(bytes: rgba, width: 2, height: 2);

      final result = ImageSourceRgba.ensureRgba(source);

      expect(identical(result, source), isTrue);
    });

    test('decodes JPEG bytes to RGBA buffer', () {
      final image = img.Image(width: 4, height: 3);
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          image.setPixelRgba(x, y, 120, 80, 40, 255);
        }
      }
      final jpeg = Uint8List.fromList(img.encodeJpg(image));

      final source = ImageSource(bytes: jpeg, width: 4, height: 3);
      final rgba = ImageSourceRgba.ensureRgba(source);

      expect(rgba.bytes.length, 4 * 3 * 4);
      expect(rgba.width, 4);
      expect(rgba.height, 3);
      expect(rgba.bytes[0], inInclusiveRange(115, 125));
    });

    test('downscaleForPreview limits long edge to 1080', () {
      final rgba = Uint8List(2160 * 3840 * 4);
      final source = ImageSource(bytes: rgba, width: 2160, height: 3840);

      final preview = ImageSourceRgba.downscaleForPreview(source);

      expect(preview.width, lessThanOrEqualTo(1080));
      expect(preview.height, lessThanOrEqualTo(1080));
      expect(
        preview.width > preview.height ? preview.width : preview.height,
        1080,
      );
    });
  });
}
