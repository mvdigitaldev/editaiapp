import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/profile/data/datasources/app_settings_datasource.dart';

const moduleManualEditEnabledKey = 'module_manual_edit_enabled';
const moduleAiEditEnabledKey = 'module_ai_edit_enabled';
const moduleTextToImageEnabledKey = 'module_text_to_image_enabled';
const moduleMultiImageEnabledKey = 'module_multi_image_enabled';
const moduleRemoveBackgroundEnabledKey =
    'module_remove_background_enabled';
const moduleFaceLabEnabledKey = 'module_face_lab_enabled';

final appSettingsDataSourceProvider = Provider<AppSettingsDataSource>((ref) {
  return AppSettingsDataSourceImpl(Supabase.instance.client);
});

final homeModuleConfigProvider = FutureProvider<HomeModuleConfig>((ref) async {
  final dataSource = ref.watch(appSettingsDataSourceProvider);
  try {
    final values = await dataSource.getValues(const [
      moduleManualEditEnabledKey,
      moduleAiEditEnabledKey,
      moduleTextToImageEnabledKey,
      moduleMultiImageEnabledKey,
      moduleRemoveBackgroundEnabledKey,
      moduleFaceLabEnabledKey,
    ]);
    return HomeModuleConfig.fromSettings(values);
  } catch (_) {
    // Falha de rede não deve deixar uma versão já publicada sem menu.
    return const HomeModuleConfig.allEnabled();
  }
});

class HomeModuleConfig {
  const HomeModuleConfig({
    required this.manualEdit,
    required this.aiEdit,
    required this.textToImage,
    required this.multiImage,
    required this.removeBackground,
    required this.faceLab,
  });

  const HomeModuleConfig.allEnabled()
      : manualEdit = true,
        aiEdit = true,
        textToImage = true,
        multiImage = true,
        removeBackground = true,
        faceLab = true;

  factory HomeModuleConfig.fromSettings(Map<String, String> settings) {
    return HomeModuleConfig(
      manualEdit: _parseEnabled(settings[moduleManualEditEnabledKey]),
      aiEdit: _parseEnabled(settings[moduleAiEditEnabledKey]),
      textToImage: _parseEnabled(settings[moduleTextToImageEnabledKey]),
      multiImage: _parseEnabled(settings[moduleMultiImageEnabledKey]),
      removeBackground:
          _parseEnabled(settings[moduleRemoveBackgroundEnabledKey]),
      faceLab: _parseEnabled(settings[moduleFaceLabEnabledKey]),
    );
  }

  final bool manualEdit;
  final bool aiEdit;
  final bool textToImage;
  final bool multiImage;
  final bool removeBackground;

  /// Laboratório facial (toggles V3 / debug) no hub de retoque.
  final bool faceLab;

  static bool _parseEnabled(String? value) {
    if (value == null || value.trim().isEmpty) return true;
    return switch (value.trim().toLowerCase()) {
      'false' || 'disable' || 'disabled' || '0' || 'off' || 'no' => false,
      _ => true,
    };
  }
}
