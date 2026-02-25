import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/upload_area.dart';

class RemoveBackgroundPage extends StatefulWidget {
  const RemoveBackgroundPage({super.key});

  @override
  State<RemoveBackgroundPage> createState() => _RemoveBackgroundPageState();
}

class _RemoveBackgroundPageState extends State<RemoveBackgroundPage> {
  String? _selectedImagePath;

  void _handleRemove() {
    if (_selectedImagePath == null) return;
    Navigator.of(context).pushNamed(
      '/processing',
      arguments: <String, String?>{
        'before': _selectedImagePath,
        'after': _selectedImagePath,
      },
    );
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
                    'Remover fundo',
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
                      'Selecione uma imagem para remover o fundo',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    UploadArea(
                      imagePath: _selectedImagePath,
                      onImageSelected: (File file) {
                        setState(() => _selectedImagePath = file.path);
                      },
                      title: 'Selecione uma imagem',
                      subtitle: 'Toque para carregar',
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
                text: 'Remover fundo',
                onPressed: _handleRemove,
                icon: Icons.wallpaper,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
