import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/upload_area.dart';

class RemoveBackgroundPage extends ConsumerStatefulWidget {
  const RemoveBackgroundPage({super.key});

  @override
  ConsumerState<RemoveBackgroundPage> createState() => _RemoveBackgroundPageState();
}

class _RemoveBackgroundPageState extends ConsumerState<RemoveBackgroundPage> {
  String? _selectedImagePath;
  bool _isLoading = false;

  Future<void> _handleRemove() async {
    if (_selectedImagePath == null || _isLoading) return;

    final balance = ref.read(creditsUsageProvider).valueOrNull?.balance ?? 0;
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
      final dio = DioClient();
      final response = await dio.instance.post<Map<String, dynamic>>(
        '/functions/v1/remover-fundo-flux',
        data: {
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
            content: Text('Não foi possível iniciar a remoção do fundo. Tente novamente.'),
          ),
        );
        return;
      }

      ref.invalidate(creditsUsageProvider);
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
              child: Consumer(
                builder: (context, ref, _) {
                  final creditsAsync = ref.watch(creditsUsageProvider);
                  final balance = creditsAsync.valueOrNull?.balance ?? 0;
                  final isLoadingCredits = creditsAsync.isLoading;
                  final hasEnough = isLoadingCredits || balance >= 7;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (!hasEnough && !_isLoading) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Créditos insuficientes. Compre mais para continuar.'),
                              ),
                            );
                            Navigator.of(context).pushNamed('/credits-shop');
                          }
                        },
                        behavior: HitTestBehavior.opaque,
                        child: AbsorbPointer(
                          absorbing: !hasEnough,
                          child: AppButton(
                            text: 'Remover fundo',
                            onPressed: hasEnough ? _handleRemove : null,
                            icon: Icons.wallpaper,
                            width: double.infinity,
                            isLoading: _isLoading,
                          ),
                        ),
                      ),
                      if (!isLoadingCredits && balance < 7) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Você precisa de 7 créditos. Toque no botão para comprar.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
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
