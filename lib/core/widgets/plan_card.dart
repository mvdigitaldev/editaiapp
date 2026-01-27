import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class PlanCard extends StatelessWidget {
  final String tier;
  final String name;
  final String price;
  final List<String> features;
  final bool isHighlighted;
  final String? badge;
  final VoidCallback? onTap;

  const PlanCard({
    super.key,
    required this.tier,
    required this.name,
    required this.price,
    required this.features,
    this.isHighlighted = false,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isHighlighted
              ? (isDark ? AppColors.surfaceDark : AppColors.surfaceLight)
              : (isDark ? AppColors.surfaceDark.withOpacity(0.5) : AppColors.surfaceLight.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted
                ? AppColors.primary
                : (isDark ? AppColors.borderDark : AppColors.border),
            width: isHighlighted ? 2 : 1,
          ),
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.1),
                    blurRadius: 20,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            if (badge != null)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: Text(
                    badge!,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tier,
                  style: AppTextStyles.overline.copyWith(
                    color: isHighlighted
                        ? AppColors.primary
                        : (isDark ? AppColors.textTertiary : AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: AppTextStyles.headingSmall.copyWith(
                          color: isDark ? AppColors.textLight : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          price,
                          style: AppTextStyles.headingMedium.copyWith(
                            color: isDark ? AppColors.textLight : AppColors.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '/mês',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(
                  color: isDark ? AppColors.borderDark : AppColors.border,
                ),
                const SizedBox(height: 16),
                ...features.map((feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              feature,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: isDark ? AppColors.textLight : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
