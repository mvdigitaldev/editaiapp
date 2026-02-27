import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/image_save_utils.dart';
import '../../../../core/widgets/app_button.dart';

class TextToImageResultPage extends StatefulWidget {
  const TextToImageResultPage({super.key});

  @override
  State<TextToImageResultPage> createState() => _TextToImageResultPageState();
}

class _TextToImageResultPageState extends State<TextToImageResultPage> {
  String? _imageUrl;
  bool _initialized = false;
  bool _isDownloading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _imageUrl = ModalRoute.of(context)?.settings.arguments as String?;
      _initialized = true;
    }
  }

  /// Volta para a Home, removendo as telas de input da pilha (inputs ficam resetados na próxima abertura).
  void _goBackToHome() {
    Navigator.of(context).popUntil((route) =>
        route.settings.name == '/' || route.settings.name == '/home' || route.isFirst);
  }

  Future<void> _handleDownload() async {
    if (_isDownloading || _imageUrl == null) return;

    setState(() {
      _isDownloading = true;
    });

    final success = await saveRemoteImageToGallery(_imageUrl!);

    if (!mounted) return;
    setState(() {
      _isDownloading = false;
    });

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
                    icon: const Icon(Icons.arrow_back_ios_new),
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
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Sua criação está pronta',
                      style: AppTextStyles.headingLarge.copyWith(
                        color: isDark ? AppColors.textLight : AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Toque em baixar para salvar a imagem',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
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
                        child: _imageUrl != null
                            ? Image.network(
                                _imageUrl!,
                                fit: BoxFit.cover,
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
                                        Icons.image_not_supported_outlined,
                                        size: 64,
                                        color: isDark
                                            ? AppColors.textTertiary
                                            : AppColors.textSecondary,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Não foi possível carregar a imagem',
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
                width: double.infinity,
                isLoading: _isDownloading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


