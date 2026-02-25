import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';

class TextToImagePage extends StatefulWidget {
  const TextToImagePage({super.key});

  @override
  State<TextToImagePage> createState() => _TextToImagePageState();
}

class _TextToImagePageState extends State<TextToImagePage> {
  final _promptController = TextEditingController();

  void _handleGenerate() {
    if (_promptController.text.trim().isEmpty) return;
    Navigator.of(context).pushNamed(
      '/processing',
      arguments: <String, String?>{
        'before': null,
        'after': null,
      },
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    'Texto para imagem',
                    style: AppTextStyles.headingMedium.copyWith(
                      color: isDark ? AppColors.textLight : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Descreva a imagem que deseja criar',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? AppColors.borderDark : AppColors.border,
                        ),
                      ),
                      child: TextField(
                        controller: _promptController,
                        maxLines: 6,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: isDark ? AppColors.textLight : AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ex: Um gato astronauta em Marte, estilo cartoon',
                          hintStyle: AppTextStyles.bodyLarge.copyWith(
                            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.borderDark : AppColors.border,
                  ),
                ),
              ),
              child: AppButton(
                text: 'Gerar',
                onPressed: _handleGenerate,
                icon: Icons.auto_awesome,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
