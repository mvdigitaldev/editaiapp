import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/image_save_utils.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../gallery/presentation/providers/gallery_provider.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';

class ComparisonPage extends ConsumerStatefulWidget {
  final String? beforeImagePath;
  final String? afterImagePath;
  final String? afterImageUrl;

  const ComparisonPage({
    super.key,
    this.beforeImagePath,
    this.afterImagePath,
    this.afterImageUrl,
  });

  @override
  ConsumerState<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends ConsumerState<ComparisonPage> {
  bool _isDownloading = false;

  /// Volta para a Home, removendo as telas de input da pilha (inputs ficam resetados na próxima abertura).
  void _goBackToHome() {
    ref.invalidate(recentEditsProvider);
    ref.invalidate(creditsUsageProvider);
    ref.invalidate(currentMonthUsageTotalProvider);
    Navigator.of(context).popUntil((route) =>
        route.settings.name == '/' || route.settings.name == '/home' || route.isFirst);
  }

  Future<void> _handleDownload() async {
    if (_isDownloading) return;

    if (widget.afterImageUrl != null) {
      setState(() => _isDownloading = true);
      final success = await saveRemoteImageToGallery(widget.afterImageUrl!);
      if (!mounted) return;
      setState(() => _isDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Imagem salva na galeria com sucesso!'
                : 'Não foi possível salvar a imagem. Verifique as permissões e tente novamente.',
          ),
        ),
      );
      return;
    }

    final path = widget.afterImagePath ?? widget.beforeImagePath;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma imagem disponível para salvar.'),
        ),
      );
      return;
    }

    setState(() => _isDownloading = true);
    final success = await saveLocalImageToGallery(path);
    if (!mounted) return;
    setState(() => _isDownloading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Imagem salva na galeria com sucesso!'
              : 'Não foi possível salvar a imagem. Verifique as permissões e tente novamente.',
        ),
      ),
    );
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
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: _goBackToHome,
                  ),
                  const Spacer(),
                  Text(
                    'Resultado',
                    style: AppTextStyles.headingMedium.copyWith(
                      color: isDark ? AppColors.textLight : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _goBackToHome,
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
            // Conteúdo: apenas a imagem resultado
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
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
                        child: widget.afterImageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: widget.afterImageUrl!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                placeholder: (_, __) => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: isDark
                                      ? AppColors.surfaceDark
                                      : AppColors.surfaceLight,
                                  child: const Center(
                                    child: Icon(Icons.error_outline),
                                  ),
                                ),
                              )
                            : widget.afterImagePath != null
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
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            // Rodapé: botão Baixar
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
                isLoading: _isDownloading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
