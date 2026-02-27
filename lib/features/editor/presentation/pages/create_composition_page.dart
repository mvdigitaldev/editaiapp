import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/aspect_ratio_utils.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/multi_upload_area.dart';
import '../../../../core/widgets/aspect_ratio_selector.dart';

class CreateCompositionPage extends ConsumerStatefulWidget {
  const CreateCompositionPage({super.key});

  @override
  ConsumerState<CreateCompositionPage> createState() => _CreateCompositionPageState();
}

class _CreateCompositionPageState extends ConsumerState<CreateCompositionPage> {
  final List<String> _imagePaths = [];
  final _promptController = TextEditingController();
  String _selectedAspectRatio = '1:1';
  bool _isLoading = false;

  int _getCreditsForImageCount(int n) => 7 + (n - 1) * 3;

  Future<void> _handleCreate() async {
    final prompt = _promptController.text.trim();
    if (_imagePaths.isEmpty || prompt.isEmpty || _isLoading) return;

    final requiredCredits = _getCreditsForImageCount(_imagePaths.length);
    final balance = ref.read(creditsUsageProvider).valueOrNull?.balance ?? 0;
    if (balance < requiredCredits) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Créditos insuficientes. Recarregue para continuar.')),
      );
      Navigator.of(context).pushNamed('/credits-shop');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final images = <String>[];
      for (final path in _imagePaths) {
        final bytes = await File(path).readAsBytes();
        images.add(base64Encode(bytes));
      }

      final size = getFluxSizeForAspect(_selectedAspectRatio);
      final dio = DioClient();
      final response = await dio.instance.post<Map<String, dynamic>>(
        '/functions/v1/editar-multi-imagem-flux',
        data: {
          'user_prompt': prompt,
          'images': images,
          'width': size.width,
          'height': size.height,
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
            content: Text('Não foi possível iniciar a composição. Tente novamente.'),
          ),
        );
        return;
      }

      ref.invalidate(creditsUsageProvider);
      Navigator.of(context).pushNamed(
        '/processing',
        arguments: <String, dynamic>{
          'taskId': taskId,
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
                    const SizedBox(height: 24),
                    Text(
                      'Proporção da imagem',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isDark ? AppColors.textLight : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AspectRatioSelector(
                      selected: _selectedAspectRatio,
                      onChanged: (value) {
                        setState(() {
                          _selectedAspectRatio = value;
                        });
                      },
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
                  final required = _getCreditsForImageCount(_imagePaths.isEmpty ? 1 : _imagePaths.length);
                  final isLoadingCredits = creditsAsync.isLoading;
                  final hasEnough = isLoadingCredits || balance >= required;
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
                            text: 'Criar composição',
                            onPressed: hasEnough ? _handleCreate : null,
                            icon: Icons.auto_awesome,
                            width: double.infinity,
                            isLoading: _isLoading,
                          ),
                        ),
                      ),
                      if (!isLoadingCredits && balance < required) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Você precisa de $required créditos. Toque no botão para comprar.',
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
