import 'package:pro_image_editor/pro_image_editor.dart';

import '../beauty_engine/models/beauty_preset.dart';
import '../beauty_engine/models/tune_params.dart';
import 'filter_grade_engine.dart';
import 'filter_preset.dart';

const editAiFilterPrefix = '__editai__';

/// Nome interno único para rastrear preset EditAI no editor manual.
String encodeEditAiFilterName(FilterPreset preset) =>
    '$editAiFilterPrefix${preset.id}__${preset.name}';

/// Extrai o id do preset a partir do nome codificado do filtro.
String? decodeEditAiFilterId(String? filterName) {
  if (filterName == null || !filterName.startsWith(editAiFilterPrefix)) {
    return null;
  }
  final rest = filterName.substring(editAiFilterPrefix.length);
  final separator = rest.indexOf('__');
  if (separator <= 0) {
    return rest.isEmpty ? null : rest;
  }
  return rest.substring(0, separator);
}

/// Rótulo amigável para filtros EditAI na lista do editor manual.
String filterPresetDisplayLabel(String filterModelName) {
  if (!filterModelName.startsWith(editAiFilterPrefix)) {
    return filterModelName;
  }
  final rest = filterModelName.substring(editAiFilterPrefix.length);
  final separator = rest.indexOf('__');
  if (separator < 0 || separator + 2 >= rest.length) {
    return rest;
  }
  return rest.substring(separator + 2);
}

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

FilterTuneParams tuneParamsToFilterTune(TuneParams tune) => _tuneToFilterTune(tune);

FilterTuneParams _tuneToFilterTune(TuneParams tune) {
  return FilterTuneParams(
    brightness: tune.brightness,
    contrast: tune.contrast,
    saturation: tune.saturation,
    exposure: tune.exposure,
    temperature: tune.temperature,
    tint: tune.tint,
    vibrance: tune.vibrance,
    hue: tune.hue,
    highlights: tune.highlights,
    shadows: tune.shadows,
    whites: tune.whites,
    blacks: tune.blacks,
    fade: tune.fade,
    sharpness: tune.sharpness,
    luminance: tune.luminance,
    vignette: tune.vignette,
    gamma: tune.gamma,
  );
}

TuneParams filterTuneToTuneParams(FilterTuneParams tune) {
  return TuneParams(
    brightness: tune.brightness,
    contrast: tune.contrast,
    saturation: tune.saturation,
    exposure: tune.exposure,
    temperature: tune.temperature,
    tint: tune.tint,
    vibrance: tune.vibrance,
    hue: tune.hue,
    highlights: tune.highlights,
    shadows: tune.shadows,
    whites: tune.whites,
    blacks: tune.blacks,
    fade: tune.fade,
    sharpness: tune.sharpness,
    luminance: tune.luminance,
    vignette: tune.vignette,
    gamma: tune.gamma,
  );
}

/// Preview com matrices aproximadas; LUT completa no export.
FilterModel filterPresetToFilterModel(FilterPreset preset) {
  final matrices = filterTuneToColorMatrices(preset.tune);
  return FilterModel(
    name: encodeEditAiFilterName(preset),
    filters: matrices.isEmpty
        ? [ColorFilterAddons.brightness(0)]
        : matrices,
  );
}

/// Lista de [FilterModel] para injetar no editor manual.
List<FilterModel> filterPresetsToFilterModels(List<FilterPreset> presets) {
  return presets
      .where((preset) => preset.hasColorAdjustments)
      .map(filterPresetToFilterModel)
      .toList();
}

/// Resolve preset selecionado pelo [FilterModel] ativo.
FilterPreset? findFilterPresetByFilterModel(
  List<FilterPreset> presets,
  FilterModel? filter,
) {
  if (filter == null) {
    return null;
  }

  final encodedId = decodeEditAiFilterId(filter.name);
  if (encodedId != null) {
    for (final preset in presets) {
      if (preset.id == encodedId) {
        return preset;
      }
    }
  }

  return findFilterPresetByModelName(presets, filter.name);
}

/// Resolve preset pelo nome legível (fallback).
FilterPreset? findFilterPresetByModelName(
  List<FilterPreset> presets,
  String? filterName,
) {
  if (filterName == null || filterName.isEmpty) {
    return null;
  }

  final encodedId = decodeEditAiFilterId(filterName);
  if (encodedId != null) {
    for (final preset in presets) {
      if (preset.id == encodedId) {
        return preset;
      }
    }
  }

  final displayName = filterPresetDisplayLabel(filterName);
  FilterPreset? match;
  for (final preset in presets) {
    if (preset.name == displayName || preset.name == filterName) {
      match = preset;
    }
  }
  return match;
}

/// Label amigável para exibição na lista de filtros do editor manual.
String filterPresetDisplayName(FilterPreset preset) => preset.name;
