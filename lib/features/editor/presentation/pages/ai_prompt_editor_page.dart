import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_bottom_nav.dart';

class AIPromptEditorPage extends StatefulWidget {
  final String? imagePath;

  const AIPromptEditorPage({
    super.key,
    this.imagePath,
  });

  @override
  State<AIPromptEditorPage> createState() => _AIPromptEditorPageState();
}

class _AIPromptEditorPageState extends State<AIPromptEditorPage> {
  final _promptController = TextEditingController();
  int _currentNavIndex = 0;

  final List<Map<String, dynamic>> _suggestions = [
    {'icon': Icons.auto_fix_high, 'label': 'Remover Fundo', 'color': AppColors.primary},
    {'icon': Icons.wb_sunny, 'label': 'Iluminação Quente', 'color': Colors.orange},
    {'icon': Icons.flare, 'label': 'Estilo Cyberpunk', 'color': Colors.purple},
  ];

  void _handleSuggestionTap(String label) {
    _promptController.text = label;
  }

  void _handleGenerate() {
    if (_promptController.text.trim().isEmpty) return;

    // Navigate to processing page
    Navigator.of(context).pushNamed('/processing');
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
            // Header
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
                    'AI Editor',
                    style: AppTextStyles.headingMedium.copyWith(
                      color: isDark ? AppColors.textLight : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.undo),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.redo),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Image preview
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (widget.imagePath != null)
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(
                            maxHeight: 500,
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
                            child: Image.file(
                              File(widget.imagePath!),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Suggestions
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            'SUGESTÕES',
                            style: AppTextStyles.overline.copyWith(
                              color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _suggestions.map((suggestion) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                onTap: () => _handleSuggestionTap(suggestion['label'] as String),
                                borderRadius: BorderRadius.circular(9999),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.surfaceDark
                                        : AppColors.surfaceLight,
                                    borderRadius: BorderRadius.circular(9999),
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.borderDark
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        suggestion['icon'] as IconData,
                                        size: 18,
                                        color: suggestion['color'] as Color,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        suggestion['label'] as String,
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: isDark
                                              ? AppColors.textLight
                                              : AppColors.textPrimary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Prompt input
                      Container(
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
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PROMPT DE EDIÇÃO',
                                    style: AppTextStyles.overline.copyWith(
                                      color: isDark
                                          ? AppColors.textTertiary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _promptController,
                                    maxLines: 4,
                                    style: AppTextStyles.bodyLarge.copyWith(
                                      color: isDark
                                          ? AppColors.textLight
                                          : AppColors.textPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          'Descreva sua edição... (ex: Deixe a iluminação mais quente e remova o fundo)',
                                      hintStyle: AppTextStyles.bodyLarge.copyWith(
                                        color: isDark
                                            ? AppColors.textTertiary
                                            : AppColors.textSecondary,
                                      ),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: isDark ? AppColors.borderDark : AppColors.border,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'AI v4.2 Pro',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: isDark
                                          ? AppColors.textTertiary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.mic,
                                          color: isDark
                                              ? AppColors.textTertiary
                                              : AppColors.textSecondary,
                                        ),
                                        onPressed: () {},
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.attachment,
                                          color: isDark
                                              ? AppColors.textTertiary
                                              : AppColors.textSecondary,
                                        ),
                                        onPressed: () {},
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 100), // Space for bottom nav
                    ],
                  ),
                ),
              ),
            ),
            // Bottom section
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
              child: Column(
                children: [
                  AppButton(
                    text: 'Gerar Edição',
                    onPressed: _handleGenerate,
                    icon: Icons.auto_awesome,
                  ),
                  const SizedBox(height: 16),
                  AppBottomNav(
                    currentIndex: _currentNavIndex,
                    onTap: (index) {
                      setState(() {
                        _currentNavIndex = index;
                      });
                    },
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
