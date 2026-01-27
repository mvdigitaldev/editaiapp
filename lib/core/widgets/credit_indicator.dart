import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class CreditIndicator extends StatelessWidget {
  final int credits;
  final Color? backgroundColor;
  final Color? textColor;

  const CreditIndicator({
    super.key,
    required this.credits,
    this.backgroundColor,
    this.textColor,
  });

  Color _getBackgroundColor() {
    if (backgroundColor != null) return backgroundColor!;
    if (credits <= 3) return AppColors.error.withOpacity(0.1);
    if (credits <= 10) return AppColors.warning.withOpacity(0.1);
    return AppColors.primary.withOpacity(0.1);
  }

  Color _getTextColor() {
    if (textColor != null) return textColor!;
    if (credits <= 3) return AppColors.error;
    if (credits <= 10) return AppColors.warning;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? _getBackgroundColor(),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(
          color: _getTextColor().withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bolt,
            size: 16,
            color: _getTextColor(),
          ),
          const SizedBox(width: 6),
          Text(
            '$credits CRÉDITOS',
            style: AppTextStyles.labelSmall.copyWith(
              color: _getTextColor(),
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
