import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../body_reshape/models/warp_plan.dart';
import '../../filters/body/body_filter_pipeline.dart';
import '../../filters/face/face_filter_pipeline.dart';
import '../../filters/face/skin_filter_pipeline.dart';
import '../../l10n/beauty_engine_labels.dart';
import '../../l10n/body_reshape_labels.dart';
import 'beauty_accessible_slider.dart';

/// Categoria de ajuste manual no retoque beauty.
enum BeautyAdjustmentCategory {
  rosto,
  nariz,
  olhos,
  boca,
  corpo,
  pele,
}

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
  });

  final Map<String, double> params;
  final bool enabled;
  final bool linkEyes;
  final void Function(String key, double value) onParamChanged;
  final ValueChanged<bool> onLinkEyesChanged;
  final bool bodyOnly;

  /// Último plano V2 — usado para hints de oclusão/confiança (Sprint 12).
  final WarpPlan? bodyWarpPlan;

  static const categories = <BeautyAdjustmentCategoryDef>[
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.rosto,
      icon: Icons.face_outlined,
      label: BeautyEngineLabels.sectionFace,
      parameterKeys: [
        'face_slim',
        'narrow_face',
        'v_face',
        'jaw',
        'chin',
        'cheekbone',
        'forehead',
        'temple',
        'head_size',
      ],
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.nariz,
      icon: Icons.notes_outlined,
      label: 'Nariz',
      parameterKeys: [
        'nose_slim',
        'nose_length',
        'nose_height',
        'nose_tip',
        'nose_bridge',
      ],
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.olhos,
      icon: Icons.remove_red_eye_outlined,
      label: 'Olhos',
      parameterKeys: [
        'eye_scale',
        'eye_distance',
        'eye_height',
        'eye_rotation',
        'double_eyelid',
      ],
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.boca,
      icon: Icons.sentiment_satisfied_alt_outlined,
      label: 'Boca',
      parameterKeys: [
        'mouth_width',
        'lip_thickness',
        'smile',
      ],
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.corpo,
      icon: Icons.accessibility_new_outlined,
      label: BeautyEngineLabels.sectionBody,
      parameterKeys: BodyFilterPipeline.bodyWarpParameterKeys,
    ),
    BeautyAdjustmentCategoryDef(
      category: BeautyAdjustmentCategory.pele,
      icon: Icons.blur_on_outlined,
      label: BeautyEngineLabels.sectionSkin,
      parameterKeys: SkinFilterPipeline.skinParameterKeys,
    ),
  ];

  /// Inicializa mapa de parâmetros com zeros para todas as keys conhecidas.
  static Map<String, double> initialParams({bool linkEyes = true}) {
    final params = <String, double>{
      for (final key in FaceFilterPipeline.faceWarpParameterKeys) key: 0,
      for (final key in BodyFilterPipeline.bodyWarpParameterKeys) key: 0,
      for (final key in SkinFilterPipeline.skinParameterKeys) key: 0,
      'link_eyes': linkEyes ? 1 : 0,
    };
    return params;
  }

  @override
  State<BeautyAdjustmentsPanel> createState() => _BeautyAdjustmentsPanelState();
}

class _BeautyAdjustmentsPanelState extends State<BeautyAdjustmentsPanel> {
  late BeautyAdjustmentCategory _category;
  String? _selectedKey;

  List<BeautyAdjustmentCategoryDef> get _visibleCategories => widget.bodyOnly
      ? BeautyAdjustmentsPanel.categories
          .where((def) => def.category == BeautyAdjustmentCategory.corpo)
          .toList(growable: false)
      : BeautyAdjustmentsPanel.categories;

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
    if (_selectedKey != null && keys.contains(_selectedKey)) {
      return _selectedKey!;
    }
    return keys.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeKey = _activeParamKey;
    final activeValue = widget.params[activeKey] ?? 0;
    final isBody = _category == BeautyAdjustmentCategory.corpo;
    final limitationHint = isBody
        ? BodyReshapeLabels.limitationHint(
            parameterKey: activeKey,
            plan: widget.bodyWarpPlan,
          )
        : null;
    final limitHint =
        isBody ? BodyReshapeLabels.controlLimitHint(activeKey) : null;
    final hintText = limitationHint ?? limitHint;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: BeautyAccessibleSlider(
                label: BeautyEngineLabels.parameterLabel(activeKey),
                value: activeValue,
                enabled: widget.enabled,
                onChanged: widget.enabled
                    ? (value) => widget.onParamChanged(activeKey, value)
                    : null,
              ),
            ),
            if (hintText != null)
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
            if (_category == BeautyAdjustmentCategory.olhos)
              SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(
                  BeautyEngineLabels.linkEyesTitle,
                  style: theme.textTheme.bodySmall,
                ),
                value: widget.linkEyes,
                onChanged: widget.enabled ? widget.onLinkEyesChanged : null,
              ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _activeCategoryDef.parameterKeys.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final key = _activeCategoryDef.parameterKeys[index];
                  final selected = key == activeKey;
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
