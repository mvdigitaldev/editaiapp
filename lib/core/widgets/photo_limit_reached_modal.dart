import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_button.dart';

/// Modal exibido quando o limite de fotos do plano foi atingido.
class PhotoLimitReachedModal extends StatelessWidget {
  const PhotoLimitReachedModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const PhotoLimitReachedModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 48,
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
            const SizedBox(height: 16),
            Text(
              'Limite de fotos atingido',
              style: AppTextStyles.headingMedium.copyWith(
                color: isDark ? AppColors.textLight : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Você atingiu o limite máximo de fotos do seu plano. '
              'Exclua algumas fotos antigas da galeria ou faça upgrade do plano para continuar.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'OK',
              onPressed: () => Navigator.of(context).pop(),
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}
