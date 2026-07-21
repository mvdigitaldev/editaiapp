import 'package:editaiapp/features/editor/beauty_engine/models/beauty_preset.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/bundled_preset_loader.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/bundled_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BundledPresetLoader', () {
    tearDown(BundledBeautyPresets.debugResetCache);

    test('loads 8 shipped presets from assets', () async {
      final presets = await const BundledPresetLoader().load();

      expect(presets, hasLength(8));
      expect(
        presets.map((preset) => preset.name),
        containsAll([
          'Natural',
          'Instagram',
          'Influenciador',
          'Beleza',
          'Casamento',
          'Estúdio',
          'Suave',
          'Cinema',
        ]),
      );
    });

    test('all bundled ids use bundled_ prefix', () async {
      final presets = await BundledBeautyPresets.loadAll();
      for (final preset in presets) {
        expect(BundledBeautyPresets.isBundled(preset.id), isTrue);
      }
    });

    test('findById returns preset after load', () async {
      await BundledBeautyPresets.loadAll();
      final preset = BundledBeautyPresets.findById('bundled_wedding');
      expect(preset, isNotNull);
      expect(preset!.name, 'Casamento');
    });
  });
}
