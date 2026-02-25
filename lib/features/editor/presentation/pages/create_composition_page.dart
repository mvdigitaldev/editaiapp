import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/multi_upload_area.dart';

class CreateCompositionPage extends StatefulWidget {
  const CreateCompositionPage({super.key});

  @override
  State<CreateCompositionPage> createState() => _CreateCompositionPageState();
}

class _CreateCompositionPageState extends State<CreateCompositionPage> {
  final List<String> _imagePaths = [];
  final _promptController = TextEditingController();

  void _handleCreate() {
    if (_imagePaths.isEmpty || _promptController.text.trim().isEmpty) return;
    Navigator.of(context).pushNamed(
      '/processing',
      arguments: <String, String?>{
        'before': null,
        'after': _imagePaths.isNotEmpty ? _imagePaths.first : null,
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
                    'Criar composição',
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
                    MultiUploadArea(
                      imagePaths: _imagePaths,
                      onChanged: (paths) {
                        setState(() {
                          _imagePaths.clear();
                          _imagePaths.addAll(paths);
                        });
                      },
                      maxCount: 8,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Descreva a composição',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isDark ? AppColors.textLight : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                        maxLines: 4,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: isDark ? AppColors.textLight : AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ex: Montagem criativa com todas as fotos',
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
                text: 'Criar composição',
                onPressed: _handleCreate,
                icon: Icons.auto_awesome,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
