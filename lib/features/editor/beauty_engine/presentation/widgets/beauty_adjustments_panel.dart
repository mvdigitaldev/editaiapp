import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../body_reshape/models/warp_plan.dart';
import '../../filters/body/body_filter_pipeline.dart';
import '../../filters/body/body_warp_chain.dart';
import '../../filters/face/face_filter_pipeline.dart';
import '../../filters/color/color_filter_pipeline.dart';
import '../../filters/face/skin_filter_pipeline.dart';
import '../../tools/tool_gate_decision.dart';
import '../../l10n/beauty_engine_labels.dart';
import '../../l10n/body_reshape_labels.dart';
import 'beauty_accessible_slider.dart';
import 'beauty_tool_icon.dart';

/// Categoria de ajuste manual no retoque beauty.
enum BeautyAdjustmentCategory {
  proporcao,
  rosto,
  sobrancelha,
  nariz,
  olhos,
  boca,
  corpo,
  pernas,
  pele,
  cor,
}

/// Abas do Ajustar corpo (`bodyOnly`).
const _bodyCategories = {
  BeautyAdjustmentCategory.corpo,
  BeautyAdjustmentCategory.pernas,
};

/// Definição de uma categoria com ícone e parâmetros associados.
class BeautyAdjustmentCategoryDef {
  const BeautyAdjustmentCategoryDef({
    required this.category,
    required this.icon,
    required this.label,
    required this.parameterKeys,
  });

  final BeautyAdjustmentCategory category;
  final IconData icon;
  final String label;
  final List<String> parameterKeys;
}

/// Barra de ajustes manuais — padrão similar ao tune editor do manual editor.
class BeautyAdjustmentsPanel extends StatefulWidget {
  const BeautyAdjustmentsPanel({
    super.key,
    required this.params,
    required this.enabled,
    required this.linkEyes,
    required this.onParamChanged,
    required this.onLinkEyesChanged,
    this.bodyWarpPlan,
    this.bodyOnly = false,
    this.labMode = false,
    this.gatePlan,
    this.backgroundLockAllowed = false,
    this.onBackgroundLockLocked,
  });

  final Map<String, double> params;

  /// Plano pago activo: a trava de fundo do corpo pode ser ligada.
  final bool backgroundLockAllowed;

  /// Toque na trava sem plano pago.
  final VoidCallback? onBackgroundLockLocked;
  final bool enabled;
  final bool linkEyes;
  final void Function(String key, double value) onParamChanged;
  final ValueChanged<bool> onLinkEyesChanged;
  final bool bodyOnly;
  final bool labMode;
  final ToolGatePlan? gatePlan;

  /// Último plano V2 — usado para hints de oclusão/confiança (Sprint 12).
  final WarpPlan? bodyWarpPlan;

  static const categories = <BeautyAdjustmentCategoryDef>[
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.proporcao,
      icon: Icons.zoom_out_map_outlined,
      label: BeautyEngineLabels.sectionProportion,
      parameterKeys: FaceFilterPipeline.proportionParameterKeys,
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.rosto,
      icon: Icons.face_outlined,
      label: BeautyEngineLabels.sectionFace,
      parameterKeys: FaceFilterPipeline.faceWarpParameterKeys,
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.sobrancelha,
      icon: Icons.visibility_outlined,
      label: BeautyEngineLabels.sectionSobrancelha,
      parameterKeys: FaceFilterPipeline.eyebrowParameterKeys,
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.olhos,
      icon: Icons.remove_red_eye_outlined,
      label: BeautyEngineLabels.sectionOlhos,
      parameterKeys: FaceFilterPipeline.eyeParameterKeys,
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.nariz,
      icon: Icons.face_retouching_natural_outlined,
      label: BeautyEngineLabels.sectionNariz,
      parameterKeys: FaceFilterPipeline.noseParameterKeys,
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.boca,
      icon: Icons.sentiment_satisfied_alt_outlined,
      label: BeautyEngineLabels.sectionLabios,
      parameterKeys: FaceFilterPipeline.lipParameterKeys,
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.corpo,
      icon: Icons.accessibility_new_outlined,
      label: BeautyEngineLabels.sectionBodySlim,
      parameterKeys: BodyWarpChain.slimParameterKeys,
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.pernas,
      icon: Icons.directions_walk_outlined,
      label: BeautyEngineLabels.sectionBodyLegs,
      parameterKeys: BodyWarpChain.legParameterKeys,
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.pele,
      icon: Icons.blur_on_outlined,
      label: BeautyEngineLabels.sectionSkin,
      parameterKeys: SkinFilterPipeline.skinParameterKeys,
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.cor,
      icon: Icons.palette_outlined,
      label: BeautyEngineLabels.sectionColor,
      parameterKeys: ColorFilterPipeline.colorParameterKeys,
    ),
  ];

  /// Inicializa mapa de parâmetros com zeros para todas as keys conhecidas.
  static Map<String, double> initialParams({bool linkEyes = true}) {
    final params = <String, double>{
      for (final key in FaceFilterPipeline.proportionParameterKeys) key: 0,
      for (final key in FaceFilterPipeline.eyebrowParameterKeys) key: 0,
      for (final key in FaceFilterPipeline.eyeParameterKeys) key: 0,
      for (final key in FaceFilterPipeline.noseParameterKeys) key: 0,
      for (final key in FaceFilterPipeline.lipParameterKeys) key: 0,
      for (final key in FaceFilterPipeline.faceWarpParameterKeys) key: 0,
      for (final key in BodyFilterPipeline.bodyWarpParameterKeys) key: 0,
      for (final key in BodyWarpChain.parameterKeys) key: 0,
      for (final key in SkinFilterPipeline.skinParameterKeys) key: 0,
      for (final key in ColorFilterPipeline.colorParameterKeys) key: 0,
      'link_eyes': linkEyes ? 1 : 0,
      'cheekbone_left': 0,
      'cheekbone_right': 0,
      'cheekbone_side': 0,
      'v_chin_left': 0,
      'v_chin_right': 0,
      'v_chin_side': 0,
      'v_shape_left': 0,
      'v_shape_right': 0,
      'v_shape_side': 0,
      'jaw_angle_left': 0,
      'jaw_angle_right': 0,
      'jaw_angle_side': 0,
      'eyebrow_height_left': 0,
      'eyebrow_height_right': 0,
      'eyebrow_height_side': 0,
      'eyebrow_width_left': 0,
      'eyebrow_width_right': 0,
      'eyebrow_width_side': 0,
      'eyebrow_end_left': 0,
      'eyebrow_end_right': 0,
      'eyebrow_end_side': 0,
      'eye_size_left': 0,
      'eye_size_right': 0,
      'eye_size_side': 0,
      'eye_height_left': 0,
      'eye_height_right': 0,
      'eye_height_side': 0,
      'eye_width_left': 0,
      'eye_width_right': 0,
      'eye_width_side': 0,
      'eye_length_left': 0,
      'eye_length_right': 0,
      'eye_length_side': 0,
      'eye_distance_left': 0,
      'eye_distance_right': 0,
      'eye_distance_side': 0,
      'nose_ala_left': 0,
      'nose_ala_right': 0,
      'nose_ala_side': 0,
      'lip_plump_upper': 0,
      'lip_plump_lower': 0,
      'lip_plump_side': 0,
    };
    return params;
  }

  @override
  State<BeautyAdjustmentsPanel> createState() => _BeautyAdjustmentsPanelState();
}

class _BeautyAdjustmentsPanelState extends State<BeautyAdjustmentsPanel> {
  late BeautyAdjustmentCategory _category;
  String? _selectedKey;

  List<BeautyAdjustmentCategoryDef> get _visibleCategories {
    if (widget.bodyOnly) {
      return BeautyAdjustmentsPanel.categories
          .where((def) => _bodyCategories.contains(def.category))
          .toList(growable: false);
    }
    // Retoque facial — corpo fica em menu/rota separada (`bodyOnly`).
    return BeautyAdjustmentsPanel.categories
        .where((def) => !_bodyCategories.contains(def.category))
        .map(_resolveCategoryDef)
        .toList(growable: false);
  }

  BeautyAdjustmentCategoryDef _resolveCategoryDef(
    BeautyAdjustmentCategoryDef def,
  ) {
    if (def.category != BeautyAdjustmentCategory.pele || !widget.labMode) {
      return def;
    }
    return BeautyAdjustmentCategoryDef(
      category: def.category,
      icon: def.icon,
      label: def.label,
      parameterKeys: SkinFilterPipeline.uiParameterKeys(labMode: true),
    );
  }

  BeautyAdjustmentCategoryDef get _activeCategoryDef =>
      _visibleCategories.firstWhere(
        (def) => def.category == _category,
      );

  @override
  void initState() {
    super.initState();
    _category = widget.bodyOnly
        ? BeautyAdjustmentCategory.corpo
        : BeautyAdjustmentCategory.rosto;
  }

  String get _activeParamKey {
    final keys = _activeCategoryDef.parameterKeys;
    if (keys.isEmpty) {
      return '';
    }
    if (_selectedKey != null && keys.contains(_selectedKey)) {
      return _selectedKey!;
    }
    return keys.first;
  }

  bool get _usesToolIcons =>
      _activeCategoryDef.parameterKeys.any(BeautyToolIcons.hasGlyph);

  static const _sideWarpKeys = {
    'cheekbone',
    'v_chin',
    'v_shape',
    'jaw_angle',
    'eyebrow_height',
    'eyebrow_width',
    'eyebrow_end',
    'eye_size',
    'eye_height',
    'eye_width',
    'eye_length',
    'eye_distance',
    'nose_ala',
  };

  static const _lipBandKeys = {
    'lip_plump',
  };

  bool _isChanged(String key) {
    bool nonzero(String k) => (widget.params[k] ?? 0).abs() > 1e-6;
    if (nonzero(key)) {
      return true;
    }
    if (_sideWarpKeys.contains(key)) {
      return nonzero('${key}_left') || nonzero('${key}_right');
    }
    if (_lipBandKeys.contains(key)) {
      return nonzero('${key}_upper') || nonzero('${key}_lower');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeKey = _activeParamKey;
    final isSideWarp = _sideWarpKeys.contains(activeKey);
    final isLipBand = _lipBandKeys.contains(activeKey);
    final activeValue = isSideWarp
        ? _sideSliderValue(activeKey)
        : isLipBand
            ? _lipBandSliderValue(activeKey)
            : (widget.params[activeKey] ?? 0);
    final isBody = _bodyCategories.contains(_category);
    final sliderRange = _sliderRangeForKey(activeKey);
    final gate = widget.gatePlan?.decisionFor(activeKey);
    final paramEnabled = widget.enabled && (gate == null || !gate.isDisabled);
    final gateHint = BeautyEngineLabels.gateHint(gate?.hintKey);
    final limitationHint = isBody
        ? BodyReshapeLabels.limitationHint(
            parameterKey: activeKey,
            plan: widget.bodyWarpPlan,
          )
        : null;
    final limitHint =
        isBody ? BodyReshapeLabels.controlLimitHint(activeKey) : null;
    final hintText = limitationHint ?? limitHint ?? gateHint;

    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            isDark ? AppColors.backgroundDarkSecondary : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.border,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (activeKey.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    BodyReshapeLabels.emptyToolsHint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: BeautyAccessibleSlider(
                  label: BeautyEngineLabels.parameterLabel(activeKey),
                  value: activeValue,
                  min: sliderRange.min,
                  max: sliderRange.max,
                  divisions: sliderRange.divisions,
                  bipolar: sliderRange.bipolar,
                  enabled: paramEnabled,
                  trailing: isSideWarp
                      ? _sideMenu(activeKey, paramEnabled)
                      : isLipBand
                          ? _lipBandMenu(activeKey, paramEnabled)
                          : null,
                  onChanged: paramEnabled
                      ? (value) => isSideWarp
                          ? _onSideSliderChanged(activeKey, value)
                          : isLipBand
                              ? _onLipBandSliderChanged(activeKey, value)
                              : widget.onParamChanged(activeKey, value)
                      : null,
                ),
              ),
            if (activeKey.isNotEmpty && hintText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hintText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: limitationHint != null
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            if (isBody && activeKey.isNotEmpty)
              _BackgroundLockRow(
                value: widget.backgroundLockAllowed &&
                    BodyWarpChain.backgroundLockRequested(widget.params),
                allowed: widget.backgroundLockAllowed,
                enabled: widget.enabled,
                onChanged: (on) => widget.onParamChanged(
                  BodyWarpChain.backgroundLockKey,
                  on ? 1 : 0,
                ),
                onLocked: widget.onBackgroundLockLocked,
              ),
            if (activeKey.isNotEmpty)
              SizedBox(
              height: _usesToolIcons ? 78 : 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _activeCategoryDef.parameterKeys.length,
                separatorBuilder: (_, __) =>
                    SizedBox(width: _usesToolIcons ? 2 : 6),
                itemBuilder: (context, index) {
                  final key = _activeCategoryDef.parameterKeys[index];
                  final selected = key == activeKey;
                  final disabled =
                      widget.gatePlan?.decisionFor(key).isDisabled ?? false;
                  if (disabled) {
                    return const SizedBox.shrink();
                  }
                  if (BeautyToolIcons.hasGlyph(key)) {
                    return _ToolNavItem(
                      toolKey: key,
                      label: BeautyEngineLabels.parameterLabel(key),
                      selected: selected,
                      enabled: widget.enabled,
                      changed: _isChanged(key),
                      onTap: () => setState(() => _selectedKey = key),
                    );
                  }
                  return ChoiceChip(
                    label: Text(
                      BeautyEngineLabels.parameterLabel(key),
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? Colors.white : null,
                      ),
                    ),
                    selected: selected,
                    onSelected: widget.enabled
                        ? (_) => setState(() => _selectedKey = key)
                        : null,
                    selectedColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            SizedBox(
              height: 72,
              child: Row(
                children: [
                  for (final def in _visibleCategories)
                    Expanded(
                      child: _CategoryNavItem(
                        icon: def.icon,
                        label: def.label,
                        selected: _category == def.category,
                        enabled: widget.enabled,
                        onTap: () {
                          setState(() {
                            _category = def.category;
                            _selectedKey = null;
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 0 = Geral, 1 = esquerda da foto, 2 = direita da foto (convenção Meitu).
  int _sideFor(String key) => (widget.params['${key}_side'] ?? 0).round();

  double _sideSliderValue(String key) {
    switch (_sideFor(key)) {
      case 1:
        return widget.params['${key}_left'] ?? widget.params[key] ?? 0;
      case 2:
        return widget.params['${key}_right'] ?? widget.params[key] ?? 0;
      default:
        return widget.params[key] ?? 0;
    }
  }

  void _onSideSliderChanged(String key, double value) {
    switch (_sideFor(key)) {
      case 1:
        widget.onParamChanged('${key}_left', value);
        return;
      case 2:
        widget.onParamChanged('${key}_right', value);
        return;
      default:
        widget.onParamChanged(key, value);
        widget.onParamChanged('${key}_left', value);
        widget.onParamChanged('${key}_right', value);
    }
  }

  /// 0 = Geral, 1 = apenas superior, 2 = apenas inferior.
  int _lipBandFor(String key) => (widget.params['${key}_side'] ?? 0).round();

  double _lipBandSliderValue(String key) {
    switch (_lipBandFor(key)) {
      case 1:
        return widget.params['${key}_upper'] ?? widget.params[key] ?? 0;
      case 2:
        return widget.params['${key}_lower'] ?? widget.params[key] ?? 0;
      default:
        return widget.params[key] ?? 0;
    }
  }

  void _onLipBandSliderChanged(String key, double value) {
    switch (_lipBandFor(key)) {
      case 1:
        widget.onParamChanged('${key}_upper', value);
        return;
      case 2:
        widget.onParamChanged('${key}_lower', value);
        return;
      default:
        widget.onParamChanged(key, value);
        widget.onParamChanged('${key}_upper', value);
        widget.onParamChanged('${key}_lower', value);
    }
  }

  Widget _lipBandMenu(String key, bool enabled) {
    const items = <({int side, String label})>[
      (side: 0, label: BeautyEngineLabels.lipBandBoth),
      (side: 1, label: BeautyEngineLabels.lipBandUpper),
      (side: 2, label: BeautyEngineLabels.lipBandLower),
    ];
    final current = items.firstWhere(
      (item) => item.side == _lipBandFor(key),
      orElse: () => items.first,
    );
    return PopupMenuButton<int>(
      enabled: enabled,
      tooltip: current.label,
      onSelected: (side) =>
          widget.onParamChanged('${key}_side', side.toDouble()),
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<int>(
            value: item.side,
            child: Text(item.label),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).disabledColor,
              ),
            ),
            Icon(
              Icons.arrow_drop_up,
              size: 18,
              color: enabled
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).disabledColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideMenu(String key, bool enabled) {
    const items = <({int side, String label})>[
      (side: 0, label: BeautyEngineLabels.cheekboneSideBoth),
      (side: 1, label: BeautyEngineLabels.cheekboneSideLeft),
      (side: 2, label: BeautyEngineLabels.cheekboneSideRight),
    ];
    final current = items.firstWhere(
      (item) => item.side == _sideFor(key),
      orElse: () => items.first,
    );
    return PopupMenuButton<int>(
      enabled: enabled,
      tooltip: current.label,
      onSelected: (side) =>
          widget.onParamChanged('${key}_side', side.toDouble()),
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<int>(
            value: item.side,
            child: Text(item.label),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).disabledColor,
              ),
            ),
            Icon(
              Icons.arrow_drop_up,
              size: 18,
              color: enabled
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).disabledColor,
            ),
          ],
        ),
      ),
    );
  }

  _SliderRange _sliderRangeForKey(String key) {
    if (key == 'cheekbone' ||
        key == 'chin' ||
        key == 'v_chin' ||
        key == 'v_shape' ||
        key == 'jaw_angle' ||
        key == 'hairline' ||
        key == 'head' ||
        key == 'eyebrow_height' ||
        key == 'eyebrow_width' ||
        key == 'eyebrow_end' ||
        key == 'eye_size' ||
        key == 'eye_height' ||
        key == 'eye_width' ||
        key == 'eye_length' ||
        key == 'eye_distance' ||
        key == 'nose_size' ||
        key == 'nose_lift' ||
        key == 'nose_ala' ||
        key == 'nose_bridge' ||
        key == 'lip_size' ||
        key == 'lip_width' ||
        key == 'lip_height' ||
        key == 'lip_angle' ||
        key == 'lip_plump' ||
        key == 'lip_smile' ||
        key == BodyWarpChain.waistKey ||
        key == BodyWarpChain.legsKey) {
      return const _SliderRange(min: -1, max: 1, bipolar: true);
    }
    if (key == 'temperature') {
      return const _SliderRange(min: -0.5, max: 0.5, divisions: 200);
    }
    if (ColorFilterPipeline.isColorKey(key)) {
      return const _SliderRange(min: -1, max: 1, divisions: 200);
    }
    return const _SliderRange();
  }
}

class _SliderRange {
  const _SliderRange({
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.bipolar = false,
  });

  final double min;
  final double max;
  final int? divisions;
  final bool bipolar;
}

class _ToolNavItem extends StatelessWidget {
  const _ToolNavItem({
    required this.toolKey,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.changed,
    required this.onTap,
  });

  final String toolKey;
  final String label;
  final bool selected;
  final bool enabled;
  final bool changed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    if (!enabled) {
      color = theme.colorScheme.onSurface.withValues(alpha: 0.3);
    } else if (selected) {
      color = AppColors.primary;
    } else {
      color = theme.colorScheme.onSurface.withValues(alpha: 0.75);
    }

    const labelHeight = 23.0; // 2 linhas a 10px / height 1.15
    return SizedBox(
      width: 72,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            BeautyToolIcon(
              key: Key('beauty-tool-icon-$toolKey'),
              toolKey: toolKey,
              color: color,
              size: 26,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: labelHeight,
              child: Align(
                alignment: Alignment.topCenter,
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: 4,
              height: 4,
              child: changed
                  ? DecoratedBox(
                      key: Key('beauty-tool-dot-$toolKey'),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : color,
                        shape: BoxShape.circle,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryNavItem extends StatelessWidget {
  const _CategoryNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? AppColors.primary
        : (enabled
            ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
            : theme.disabledColor);

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// «Travar fundo» do corpo. Sem plano pago o switch fica desligado e o toque
/// abre o aviso de planos.
class _BackgroundLockRow extends StatelessWidget {
  const _BackgroundLockRow({
    required this.value,
    required this.allowed,
    required this.enabled,
    required this.onChanged,
    required this.onLocked,
  });

  final bool value;
  final bool allowed;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onLocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Icon(
            allowed ? Icons.lock_outline_rounded : Icons.lock_rounded,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Text(
            BodyReshapeLabels.backgroundLock,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              BodyReshapeLabels.backgroundLockBadge,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          Switch(
            key: const ValueKey('body_bg_lock_switch'),
            value: value,
            onChanged: !enabled
                ? null
                : (on) {
                    if (!allowed) {
                      onLocked?.call();
                      return;
                    }
                    onChanged(on);
                  },
          ),
        ],
      ),
    );
  }
}
