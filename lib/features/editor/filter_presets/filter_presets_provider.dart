import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../beauty_engine/di/beauty_engine_providers.dart';
import 'filter_preset.dart';
import 'filter_preset_mapper.dart';

/// Bundled + filtros do usuário (instalados ou criados) para o editor manual.
final filterPresetsProvider = FutureProvider<List<FilterPreset>>((ref) async {
  final bundled = await ref.watch(bundledBeautyPresetsProvider.future);
  final user = await ref.watch(userBeautyPresetsProvider.future);

  final seen = <String>{};
  final result = <FilterPreset>[];

  for (final preset in [...bundled, ...user]) {
    if (seen.add(preset.id)) {
      result.add(beautyPresetToFilterPreset(preset));
    }
  }

  return result;
});

/// [FilterModel]s prontos para o pro_image_editor.
final manualEditorCustomFiltersProvider =
    FutureProvider<List<FilterModel>>((ref) async {
  final presets = await ref.watch(filterPresetsProvider.future);
  return filterPresetsToFilterModels(presets);
});
