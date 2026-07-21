import 'package:editaiapp/features/editor/beauty_engine/models/beauty_preset.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/body_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/skin_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tune_params.dart';
import 'package:editaiapp/features/editor/filter_presets/filter_preset_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

void main() {
  group('beautyPresetToFilterPreset', () {
    test('ignora warp e pele legados', () {
      final preset = BeautyPreset(
        id: 'user_test',
        name: 'Teste',
        lutAssetPath: 'assets/filters/lut/natural.png',
        lutIntensity: 0.8,
        tune: const TuneParams(brightness: 0.1, contrast: 0.05),
        face: const FaceParams(faceSlim: 0.9, noseSlim: 0.5),
        body: const BodyParams(waistSlim: 0.7),
        skin: const SkinParams(smooth: 0.4),
      );

      final filter = beautyPresetToFilterPreset(preset);

      expect(filter.id, 'user_test');
      expect(filter.name, 'Teste');
      expect(filter.lutAssetPath, preset.lutAssetPath);
      expect(filter.tune.brightness, 0.1);
      expect(filter.tune.contrast, 0.05);
      expect(filter.hasColorAdjustments, isTrue);
    });
  });

  group('filterPresetToFilterModel', () {
    test('gera matrices de tune para o pro_image_editor', () {
      final filter = beautyPresetToFilterPreset(
        const BeautyPreset(
          id: 'bundled_natural',
          name: 'Natural',
          tune: TuneParams(
            brightness: 0.05,
            contrast: 0.08,
            temperature: 0.06,
          ),
        ),
      );

      final model = filterPresetToFilterModel(filter);

      expect(model, isA<FilterModel>());
      expect(model.name, 'Natural');
      expect(model.filters.length, 3);
    });

    test('preset sem LUT nem tune não entra na lista convertida', () {
      final empty = beautyPresetToFilterPreset(
        const BeautyPreset(id: 'empty', name: 'Vazio'),
      );
      expect(empty.hasColorAdjustments, isFalse);

      final models = filterPresetsToFilterModels([empty]);
      expect(models, isEmpty);
    });
  });
}
