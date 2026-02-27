import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class AspectRatioSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const AspectRatioSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const options = <_AspectOption>[
      _AspectOption(label: '1:1', aspectRatio: 1 / 1),
      _AspectOption(label: '16:9', aspectRatio: 16 / 9),
      _AspectOption(label: '9:16', aspectRatio: 9 / 16),
      _AspectOption(label: '3:4', aspectRatio: 3 / 4),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((option) {
          final isSelected = option.label == selected;
          final borderColor = isSelected
              ? AppColors.primary
              : (isDark ? AppColors.borderDark : AppColors.border);
          final bgColor = isSelected
              ? AppColors.primary.withOpacity(0.08)
              : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight);

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(option.label),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: borderColor,
                    width: isSelected ? 2 : 1,
                  ),
                  color: bgColor,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: option.aspectRatio,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      option.label,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.textLight
                                : AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AspectOption {
  final String label;
  final double aspectRatio;

  const _AspectOption({
    required this.label,
    required this.aspectRatio,
  });
}

