import 'package:editaiapp/features/editor/beauty_engine/models/beauty_preset.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/body_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/face_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/skin_params.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tune_params.dart';
import 'package:editaiapp/features/editor/filter_presets/filter_grade_engine.dart';
import 'package:editaiapp/features/editor/filter_presets/filter_preset.dart';
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
        tune: const TuneParams(
          brightness: 0.1,
          contrast: 0.05,
          vibrance: 0.12,
        ),
        face: const FaceParams(faceSlim: 0.9, noseSlim: 0.5),
        body: const BodyParams(waistSlim: 0.7),
        skin: const SkinParams(smooth: 0.4),
      );

      final filter = beautyPresetToFilterPreset(preset);

      expect(filter.id, 'user_test');
      expect(filter.tune.vibrance, 0.12);
      expect(filter.hasColorAdjustments, isTrue);
    });
  });

  group('filterPresetToFilterModel', () {
    test('usa nome codificado e matrices de preview', () {
      final filter = beautyPresetToFilterPreset(
        const BeautyPreset(
          id: 'user_abc',
          name: 'Meu filtro',
          lutAssetPath: 'assets/filters/lut/natural.png',
          tune: TuneParams(brightness: 0.05, contrast: 0.08),
        ),
      );

      final model = filterPresetToFilterModel(filter);

      expect(model.name, encodeEditAiFilterName(filter));
      expect(filterPresetDisplayLabel(model.name), 'Meu filtro');
      expect(model.filters.length, 2);
    });

    test('preset sem LUT nem tune não entra na lista convertida', () {
      final empty = beautyPresetToFilterPreset(
        const BeautyPreset(id: 'empty', name: 'Vazio'),
      );
      expect(empty.hasColorAdjustments, isFalse);
      expect(filterPresetsToFilterModels([empty]), isEmpty);
    });
  });

  group('findFilterPresetByFilterModel', () {
    test('resolve preset pelo id codificado', () {
      const presets = [
        FilterPreset(id: 'user_abc', name: 'Meu filtro'),
        FilterPreset(id: 'bundled_natural', name: 'Natural'),
      ];
      final model = filterPresetToFilterModel(presets.first);

      expect(
        findFilterPresetByFilterModel(presets, model)?.id,
        'user_abc',
      );
    });
  });

  group('filterTuneToColorMatrices', () {
    test('inclui parâmetros expandidos', () {
      const tune = FilterTuneParams(exposure: 0.1, fade: 0.2, sharpness: 0.05);
      expect(filterTuneToColorMatrices(tune).length, 3);
    });
  });

  group('tuneForManualEditorExport', () {
    test('zera tune já aplicado via matrix no preview', () {
      const preset = FilterPreset(
        id: 'user_1',
        name: 'Teste',
        tune: FilterTuneParams(
          brightness: 0.1,
          contrast: 0.2,
          vignette: 0.3,
          fade: 0.1,
        ),
      );

      final exportTune = preset.tuneForManualEditorExport();

      expect(exportTune.brightness, 0);
      expect(exportTune.contrast, 0);
      expect(exportTune.vignette, 0.3);
      expect(exportTune.fade, 0.1);
    });
  });
}
