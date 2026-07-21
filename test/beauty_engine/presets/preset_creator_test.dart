import 'dart:io';
import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/models/beauty_preset.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/preset_thumbnail_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PresetThumbnailService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('preset_thumb_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveFromJpeg returns null for empty bytes', () async {
      final service = PresetThumbnailService(resolveDirectory: () async => tempDir);
      final path = await service.saveFromJpeg(
        presetId: 'user_test',
        jpegBytes: Uint8List(0),
      );
      expect(path, isNull);
    });

    test('saveFromJpeg writes thumbnail file', () async {
      final service = PresetThumbnailService(resolveDirectory: () async => tempDir);
      final image = img.Image(width: 64, height: 64);
      img.fill(image, color: img.ColorRgb8(200, 120, 80));
      final jpeg = Uint8List.fromList(img.encodeJpg(image));

      final path = await service.saveFromJpeg(
        presetId: 'user_thumb_test',
        jpegBytes: jpeg,
      );

      expect(path, isNotNull);
      expect(path!, contains('user_thumb_test.jpg'));

      await service.deleteForPreset('user_thumb_test');
    });
  });

  group('BeautyPreset copyWith', () {
    test('updates name and clears lut path', () {
      const original = BeautyPreset(
        id: 'user_1',
        name: 'Old',
        lutAssetPath: 'assets/filters/lut/natural.png',
      );

      final updated = original.copyWith(
        name: 'New',
        clearLutAssetPath: true,
      );

      expect(updated.name, 'New');
      expect(updated.lutAssetPath, isNull);
      expect(updated.id, 'user_1');
    });
  });
}
