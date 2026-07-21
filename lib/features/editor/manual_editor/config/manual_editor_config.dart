import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../../../../core/theme/app_colors.dart';
import '../data/filter_presets.dart';

/// Traduções PT-BR do editor manual.
const manualEditorI18n = I18n(
  various: I18nVarious(
    loadingDialogMsg: 'Processando...',
    closeEditorWarningTitle: 'Fechar editor?',
    closeEditorWarningMessage:
        'Suas alterações não serão salvas. Deseja sair mesmo assim?',
    closeEditorWarningConfirmBtn: 'Sair',
    closeEditorWarningCancelBtn: 'Cancelar',
  ),
  tuneEditor: I18nTuneEditor(
    bottomNavigationBarText: 'Ajustes',
    back: 'Voltar',
    done: 'Concluir',
    brightness: 'Brilho',
    contrast: 'Contraste',
    saturation: 'Saturação',
    exposure: 'Exposição',
    hue: 'Matiz',
    temperature: 'Temperatura',
    sharpness: 'Nitidez',
    fade: 'Desbotar',
    luminance: 'Luminância',
    undo: 'Desfazer',
    redo: 'Refazer',
  ),
  cropRotateEditor: I18nCropRotateEditor(
    bottomNavigationBarText: 'Recortar',
    rotate: 'Girar',
    ratio: 'Proporção',
    back: 'Voltar',
    done: 'Concluir',
  ),
  filterEditor: I18nFilterEditor(
    bottomNavigationBarText: 'Filtros',
    back: 'Voltar',
    done: 'Concluir',
    filters: I18nFilters(
      none: 'Original',
      addictiveBlue: 'Azul',
      addictiveRed: 'Vermelho',
      aden: 'Aden',
      amaro: 'Amaro',
      ashby: 'Ashby',
      brannan: 'Brannan',
      brooklyn: 'Brooklyn',
      charmes: 'Charmes',
      clarendon: 'Clarendon',
      crema: 'Crema',
      dogpatch: 'Dogpatch',
      earlybird: 'Earlybird',
      f1977: '1977',
      gingham: 'Gingham',
      ginza: 'Ginza',
      hefe: 'Hefe',
      helena: 'Helena',
      hudson: 'Hudson',
      inkwell: 'P&B',
      juno: 'Juno',
      kelvin: 'Kelvin',
      lark: 'Lark',
      loFi: 'Lo-Fi',
      ludwig: 'Ludwig',
      maven: 'Maven',
      mayfair: 'Mayfair',
      moon: 'Moon',
      nashville: 'Nashville',
      perpetua: 'Perpetua',
      reyes: 'Reyes',
      rise: 'Rise',
      sierra: 'Sierra',
      skyline: 'Skyline',
      slumber: 'Slumber',
      stinson: 'Stinson',
      sutro: 'Sutro',
      toaster: 'Toaster',
      valencia: 'Valencia',
      vesper: 'Vesper',
      walden: 'Walden',
      willow: 'Willow',
      xProII: 'Pro II',
    ),
  ),
);

/// Configuração do pro_image_editor — tune, crop e filtros apenas.
ProImageEditorConfigs buildManualEditorConfigs({
  List<FilterModel> extraFilters = const [],
}) {
  final filterList = [
    ...manualEditorFilterPresets,
    ...extraFilters,
  ];

  return ProImageEditorConfigs(
    designMode: ImageEditorDesignMode.material,
    i18n: manualEditorI18n,
    helperLines: const HelperLineConfigs(
      showVerticalLine: true,
      showHorizontalLine: true,
      showRotateLine: true,
    ),
    mainEditor: const MainEditorConfigs(
      style: MainEditorStyle(
        background: AppColors.backgroundDark,
        appBarBackground: AppColors.backgroundDarkSecondary,
        appBarColor: AppColors.textLight,
        bottomBarBackground: AppColors.backgroundDarkSecondary,
      ),
      icons: MainEditorIcons(
        closeEditor: Icons.close,
        doneIcon: Icons.check,
        applyChanges: Icons.check_circle_outline,
        backButton: Icons.arrow_back,
        undoAction: Icons.undo,
        redoAction: Icons.redo,
      ),
    ),
    paintEditor: const PaintEditorConfigs(enabled: false),
    textEditor: const TextEditorConfigs(enabled: false),
    stickerEditor: const StickerEditorConfigs(enabled: false),
    blurEditor: const BlurEditorConfigs(enabled: false),
    emojiEditor: const EmojiEditorConfigs(enabled: false),
    tuneEditor: TuneEditorConfigs(
      enabled: true,
      style: const TuneEditorStyle(
        appBarBackground: AppColors.backgroundDarkSecondary,
        appBarColor: AppColors.textLight,
        background: AppColors.backgroundDark,
        bottomBarBackground: AppColors.backgroundDarkSecondary,
        bottomBarActiveItemColor: AppColors.primary,
      ),
      icons: const TuneEditorIcons(
        bottomNavBar: Icons.tune,
      ),
      tuneAdjustmentOptions: [
        TuneAdjustmentItem(
          id: 'brightness',
          icon: Icons.brightness_6_outlined,
          label: 'Brilho',
          min: -1,
          max: 1,
          divisions: 200,
          toMatrix: ColorFilterAddons.brightness,
        ),
        TuneAdjustmentItem(
          id: 'contrast',
          icon: Icons.contrast_outlined,
          label: 'Contraste',
          min: -1,
          max: 1,
          divisions: 200,
          toMatrix: ColorFilterAddons.contrast,
        ),
        TuneAdjustmentItem(
          id: 'saturation',
          icon: Icons.gradient_outlined,
          label: 'Saturação',
          min: -1,
          max: 1,
          divisions: 200,
          toMatrix: ColorFilterAddons.saturation,
        ),
        TuneAdjustmentItem(
          id: 'exposure',
          icon: Icons.exposure_outlined,
          label: 'Exposição',
          min: -1,
          max: 1,
          divisions: 200,
          toMatrix: ColorFilterAddons.exposure,
        ),
        TuneAdjustmentItem(
          id: 'temperature',
          icon: Icons.thermostat_outlined,
          label: 'Temperatura',
          min: -0.5,
          max: 0.5,
          divisions: 200,
          labelMultiplier: 200,
          toMatrix: (value) {
            final warm = value > 0 ? 1.0 : 1.0 + value;
            final cool = value < 0 ? 1.0 : 1.0 - value;
            return ColorFilterAddons.rgbScale(warm, 1, cool);
          },
        ),
      ],
    ),
    cropRotateEditor: const CropRotateEditorConfigs(
      enabled: true,
      showAspectRatioButton: true,
      style: CropRotateEditorStyle(
        appBarBackground: AppColors.backgroundDarkSecondary,
        appBarColor: AppColors.textLight,
        background: AppColors.backgroundDark,
      ),
    ),
    filterEditor: FilterEditorConfigs(
      enabled: true,
      filterList: filterList,
      style: const FilterEditorStyle(
        appBarBackground: AppColors.backgroundDarkSecondary,
        appBarColor: AppColors.textLight,
        background: AppColors.backgroundDark,
      ),
      icons: const FilterEditorIcons(
        bottomNavBar: Icons.filter_vintage_outlined,
      ),
    ),
  );
}
