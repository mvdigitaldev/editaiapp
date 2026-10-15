import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/color/display_p3.dart';
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

    test('JPEG sem perfil fica como a descodificação de hoje', () {
      final image = img.Image(width: 2, height: 2);
      image.setPixelRgb(0, 0, 200, 80, 40);
      final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 100));
      final rgba = ImageSourceRgba.ensureRgba(
        ImageSource(bytes: jpeg, width: 2, height: 2),
      );
      final plain = img.decodeImage(jpeg)!;
      expect(rgba.bytes[0], plain.getPixel(0, 0).r.toInt());
      expect(rgba.bytes[1], plain.getPixel(0, 0).g.toInt());
      expect(rgba.bytes[2], plain.getPixel(0, 0).b.toInt());
    });

    test('JPEG Display P3 muda os pixels para sRGB', () {
      final image = img.Image(width: 2, height: 2);
      image.setPixelRgb(0, 0, 200, 80, 40);
      image.iccProfile = displayP3ProfileStub();
      final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 100));
      final rgba = ImageSourceRgba.ensureRgba(
        ImageSource(bytes: jpeg, width: 2, height: 2),
      );
      final converted = DisplayP3.toSrgb(200 / 255, 80 / 255, 40 / 255);
      expect(rgba.bytes[0],
          inInclusiveRange(converted.$1.round() - 8, converted.$1.round() + 8));
      expect((rgba.bytes[0] - 200).abs() > 4, isTrue);
    });

    test('perfil sRGB não converte', () {
      final image = img.Image(width: 1, height: 1);
      image.setPixelRgb(0, 0, 200, 80, 40);
      image.iccProfile = img.IccProfile(
        'ICC_PROFILE',
        img.IccProfileCompression.none,
        Uint8List.fromList('sRGB IEC61966-2.1'.codeUnits),
      );
      expect(DisplayP3.applyToSrgb(image), isFalse);
      expect(image.getPixel(0, 0).r.toInt(), 200);
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
