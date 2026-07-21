import 'dart:convert';
import 'dart:io';

import 'package:editaiapp/features/editor/beauty_engine/models/beauty_preset.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/skin_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/beauty_preset_local_store.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/beauty_preset_repository_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/bundled_presets.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/preset_thumbnail_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BundledBeautyPresets', () {
    setUp(() async {
      BundledBeautyPresets.debugResetCache();
      await BundledBeautyPresets.loadAll();
    });

    tearDown(BundledBeautyPresets.debugResetCache);

    test('includes 8 shipped presets', () {
      expect(BundledBeautyPresets.all, hasLength(8));
      expect(
        BundledBeautyPresets.all.map((preset) => preset.name),
        containsAll([
          'Natural',
          'Instagram',
          'Influencer',
          'Beauty',
          'Wedding',
          'Studio',
          'Soft',
          'Cinema',
        ]),
      );
    });

    test('round-trip JSON for bundled presets', () {
      for (final preset in BundledBeautyPresets.all) {
        final decoded = BeautyPreset.fromJson(preset.toJson());
        expect(decoded.id, preset.id);
        expect(decoded.name, preset.name);
        expect(decoded.version, preset.version);
      }
    });
  });

  group('BeautyPresetRepositoryImpl', () {
    late Directory tempDir;
    late Directory tempThumbDir;
    late BeautyPresetRepositoryImpl repository;

    setUp(() async {
      BundledBeautyPresets.debugResetCache();
      tempDir = await Directory.systemTemp.createTemp('beauty_presets_test_');
      tempThumbDir = await Directory.systemTemp.createTemp('beauty_thumbs_test_');
      repository = BeautyPresetRepositoryImpl(
        store: BeautyPresetLocalStore(
          resolveDirectory: () async => tempDir,
        ),
        thumbnailService: PresetThumbnailService(
          resolveDirectory: () async => tempThumbDir,
        ),
      );
      await repository.listBundledPresets();
    });

    tearDown(() async {
      BundledBeautyPresets.debugResetCache();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      if (await tempThumbDir.exists()) {
        await tempThumbDir.delete(recursive: true);
      }
    });

    test('listPresets returns bundled presets by default', () async {
      final presets = await repository.listPresets();
      expect(presets.length, greaterThanOrEqualTo(8));
      expect(
        presets.map((preset) => preset.id),
        containsAll(BundledBeautyPresets.ids),
      );
    });

    test('savePreset persists user preset to JSON file', () async {
      const custom = BeautyPreset(
        id: 'user_soft_glow',
        name: 'Soft Glow',
        face: FaceParams(faceSlim: 0.1),
        skin: SkinParams(smooth: 0.4),
      );

      await repository.savePreset(custom);

      final reloaded = BeautyPresetRepositoryImpl(
        store: BeautyPresetLocalStore(
          resolveDirectory: () async => tempDir,
        ),
      );

      final userPresets = await reloaded.listUserPresets();
      expect(userPresets, hasLength(1));
      expect(userPresets.first.id, custom.id);
      expect(userPresets.first.face.faceSlim, 0.1);
    });

    test('deletePreset removes user preset but keeps bundled', () async {
      const custom = BeautyPreset(
        id: 'user_to_delete',
        name: 'Delete Me',
      );

      await repository.savePreset(custom);
      await repository.deletePreset(custom.id);

      expect(await repository.findById(custom.id), isNull);
      expect(await repository.findById('bundled_natural'), isNotNull);
    });

    test('cannot save or delete bundled preset', () async {
      final bundledBeauty = BundledBeautyPresets.findById('bundled_beauty')!;
      final bundledCinema = BundledBeautyPresets.findById('bundled_cinema')!;

      await expectLater(
        repository.savePreset(bundledBeauty),
        throwsArgumentError,
      );
      await expectLater(
        repository.deletePreset(bundledCinema.id),
        throwsArgumentError,
      );
    });

    test('export and import preset JSON round-trip', () async {
      const custom = BeautyPreset(
        id: 'user_export',
        name: 'Export Me',
        skin: SkinParams(smooth: 0.55),
      );

      await repository.savePreset(custom);

      final exported = await repository.exportPresetJson(custom.id);
      final decoded = jsonDecode(exported) as Map<String, dynamic>;

      final imported = await repository.importPresetJson({
        ...decoded,
        'id': 'user_imported_copy',
        'name': 'Imported Copy',
      });

      expect(imported.id, 'user_imported_copy');
      expect(imported.skin.smooth, 0.55);
      expect(await repository.findById('user_imported_copy'), isNotNull);
    });
  });

  group('BeautyPresetLocalStore', () {
    test('in-memory store round-trip', () async {
      const preset = BeautyPreset(
        id: 'memory_preset',
        name: 'Memory',
      );

      final store = BeautyPresetLocalStore(seed: const []);
      await store.writeAll(const [preset]);

      final loaded = await store.readAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, preset.id);
    });
  });
}
