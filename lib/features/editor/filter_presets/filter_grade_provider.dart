import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'filter_grade_engine.dart';
import 'filter_preset.dart';
import 'filter_presets_provider.dart';

final filterGradeEngineProvider = Provider<FilterGradeEngine>(
  (ref) => FilterGradeEngine(),
);

/// Bundled + filtros do usuário com metadados para export fiel.
final manualEditorFilterPresetsProvider =
    FutureProvider<List<FilterPreset>>((ref) async {
  return ref.watch(filterPresetsProvider.future);
});
