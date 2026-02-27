import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/upload_area.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';

class EditImagePage extends ConsumerStatefulWidget {
  const EditImagePage({super.key});

  @override
  ConsumerState<EditImagePage> createState() => _EditImagePageState();
}

class _EditImagePageState extends ConsumerState<EditImagePage> {
  String? _selectedImagePath;
  final _promptController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleGenerate() async {
    final prompt = _promptController.text.trim();
    if (_selectedImagePath == null || prompt.isEmpty || _isLoading) return;

    final creditsAsync = ref.read(creditsUsageProvider);
    final balance = creditsAsync.valueOrNull?.balance ?? 0;
    if (balance < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Créditos insuficientes. Recarregue para continuar.')),
      );
      Navigator.of(context).pushNamed('/credits-shop');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final bytes = await File(_selectedImagePath!).readAsBytes();
      final imageBase64 = base64Encode(bytes);
      // Usar DioClient: envia apikey + JWT (mesma autenticação que texto para imagem)
      final dio = DioClient();
      final response = await dio.instance.post<Map<String, dynamic>>(
        '/functions/v1/editar-imagem-flux',
        data: {
          'user_prompt': prompt,
          'image_base64': imageBase64,
        },
      );

      if (!mounted) return;

      final data = response.data;
      String? taskId;
      if (data != null && data['task_id'] is String) {
        final raw = data['task_id'] as String;
        if (raw.isNotEmpty) taskId = raw;
      }

      if (taskId == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível iniciar a edição. Tente novamente.'),
          ),
        );
        return;
      }

      Navigator.of(context).pushNamed(
        '/processing',
        arguments: <String, dynamic>{
          'taskId': taskId,
          'beforePath': _selectedImagePath,
          'before': null,
          'after': null,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (e is DioException && e.response?.statusCode == 402) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Créditos insuficientes. Recarregue para continuar.')),
        );
        Navigator.of(context).pushNamed('/credits-shop');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao comunicar com o servidor. Verifique sua conexão e tente novamente.'),
          ),
        );
      }
    }
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
                    'Editar imagem',
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
                    UploadArea(
                      imagePath: _selectedImagePath,
                      onImageSelected: (File file) {
                        setState(() => _selectedImagePath = file.path);
                      },
                      title: 'Selecione uma imagem',
                      subtitle: 'Toque para carregar',
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Descreva a edição',
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
                          hintText: 'Ex: Deixe a iluminação mais quente',
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
              child: Consumer(
                builder: (context, ref, _) {
                  final creditsAsync = ref.watch(creditsUsageProvider);
                  final balance = creditsAsync.valueOrNull?.balance ?? 0;
                  final isLoadingCredits = creditsAsync.isLoading;
                  final hasEnoughCredits = isLoadingCredits || balance >= 7;
                  return AppButton(
                    text: 'Gerar',
                    onPressed: hasEnoughCredits ? _handleGenerate : null,
                    icon: Icons.auto_awesome,
                    width: double.infinity,
                    isLoading: _isLoading,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
