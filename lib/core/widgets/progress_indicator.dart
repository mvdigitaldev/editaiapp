import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppProgressIndicator extends StatelessWidget {
  final double progress;
  final String? label;

  const AppProgressIndicator({
    super.key,
    required this.progress,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9999),
            color: isDark ? AppColors.borderDark : AppColors.border,
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9999),
                color: AppColors.primary,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
