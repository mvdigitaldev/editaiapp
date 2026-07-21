import 'package:pro_image_editor/pro_image_editor.dart';

import '../beauty_engine/models/beauty_preset.dart';
import '../beauty_engine/models/tune_params.dart';
import 'filter_preset.dart';

/// Converte [BeautyPreset] em [FilterPreset] ignorando warp/pele legados.
FilterPreset beautyPresetToFilterPreset(BeautyPreset preset) {
  return FilterPreset(
    id: preset.id,
    name: preset.name,
    lutAssetPath: preset.lutAssetPath,
    lutIntensity: preset.lutIntensity,
    tune: _tuneToFilterTune(preset.tune),
    isBundled: preset.id.startsWith('bundled_'),
  );
}

FilterTuneParams _tuneToFilterTune(TuneParams tune) {
  return FilterTuneParams(
    brightness: tune.brightness,
    contrast: tune.contrast,
    saturation: tune.saturation,
    exposure: tune.exposure,
    temperature: tune.temperature,
  );
}

/// Converte [FilterPreset] em [FilterModel] do pro_image_editor (ajustes de cor).
FilterModel filterPresetToFilterModel(FilterPreset preset) {
  final matrices = <List<double>>[];

  final tune = preset.tune;
  if (tune.brightness != 0) {
    matrices.add(ColorFilterAddons.brightness(tune.brightness));
  }
  if (tune.contrast != 0) {
    matrices.add(ColorFilterAddons.contrast(tune.contrast));
  }
  if (tune.saturation != 0) {
    matrices.add(ColorFilterAddons.saturation(tune.saturation));
  }
  if (tune.exposure != 0) {
    matrices.add(ColorFilterAddons.exposure(tune.exposure));
  }
  if (tune.temperature != 0) {
    final warm = tune.temperature > 0 ? 1.0 : 1.0 + tune.temperature;
    final cool = tune.temperature < 0 ? 1.0 : 1.0 - tune.temperature;
    matrices.add(ColorFilterAddons.rgbScale(warm, 1, cool));
  }

  // LUT custom não é aplicável nativamente no pro_image_editor;
  // o nome do preset indica a origem; tune matrices aproximam o look.
  return FilterModel(
    name: preset.name,
    filters: matrices,
  );
}

/// Lista de [FilterModel] para injetar no editor manual.
List<FilterModel> filterPresetsToFilterModels(List<FilterPreset> presets) {
  return presets
      .where((preset) => preset.hasColorAdjustments)
      .map(filterPresetToFilterModel)
      .toList();
}
