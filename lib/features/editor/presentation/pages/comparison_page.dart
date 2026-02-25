import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/comparison_slider.dart';

class ComparisonPage extends StatefulWidget {
  final String? beforeImagePath;
  final String? afterImagePath;

  const ComparisonPage({
    super.key,
    this.beforeImagePath,
    this.afterImagePath,
  });

  @override
  State<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends State<ComparisonPage> {
  double _filterIntensity = 0.5;

  void _handleDownload() {
    // TODO: Download image
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Imagem baixada com sucesso!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showComparison = widget.beforeImagePath != null &&
        widget.afterImagePath != null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    showComparison ? 'Comparação' : 'Resultado',
                    style: AppTextStyles.headingMedium.copyWith(
                      color: isDark ? AppColors.textLight : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Concluir',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (showComparison) ...[
                      Text(
                        'Deslize para comparar',
                        style: AppTextStyles.headingLarge.copyWith(
                          color: isDark ? AppColors.textLight : AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Visualizando melhorias de IA',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(
                          minHeight: 400,
                          maxHeight: 600,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ComparisonSlider(
                            beforeImagePath: widget.beforeImagePath,
                            afterImagePath: widget.afterImagePath,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.surfaceDark
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.border,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Intensidade do Filtro',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: isDark
                                        ? AppColors.textLight
                                        : AppColors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '${(_filterIntensity * 100).toInt()}%',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Slider(
                              value: _filterIntensity,
                              onChanged: (value) {
                                setState(() {
                                  _filterIntensity = value;
                                });
                              },
                              activeColor: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Resultado',
                        style: AppTextStyles.headingLarge.copyWith(
                          color: isDark ? AppColors.textLight : AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sua criação está pronta',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(
                          minHeight: 400,
                          maxHeight: 600,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: widget.afterImagePath != null
                              ? Image.file(
                                  File(widget.afterImagePath!),
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                )
                              : Container(
                                  color: isDark
                                      ? AppColors.surfaceDark
                                      : AppColors.surfaceLight,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.image,
                                          size: 64,
                                          color: isDark
                                              ? AppColors.textTertiary
                                              : AppColors.textSecondary,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Imagem gerada',
                                          style: AppTextStyles.bodyMedium.copyWith(
                                            color: isDark
                                                ? AppColors.textTertiary
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            // Footer - apenas botão Baixar
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.backgroundDark
                    : AppColors.backgroundLight,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.borderDark : AppColors.border,
                  ),
                ),
              ),
              child: AppButton(
                text: 'Baixar imagem',
                onPressed: _handleDownload,
                icon: Icons.download,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
