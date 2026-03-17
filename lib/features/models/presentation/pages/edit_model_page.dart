import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/image_resize_utils.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../subscription/presentation/providers/plan_limits_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/upload_area.dart';

class EditModelPage extends ConsumerStatefulWidget {
  const EditModelPage({super.key});

  @override
  ConsumerState<EditModelPage> createState() => _EditModelPageState();
}

class _EditModelPageState extends ConsumerState<EditModelPage> {
  String? _selectedImagePath;
  bool _isLoading = false;

  static const int _creditsRequired = 7;

  Future<void> _handleGenerate() async {
    if (_selectedImagePath == null || _isLoading) return;

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final modeloId = args?['modeloId'] as String?;

    if (modeloId == null || modeloId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modelo inválido. Volte e tente novamente.')),
      );
      return;
    }

    final balance = ref.read(creditsUsageProvider).valueOrNull?.balance ?? 0;
    if (balance < _creditsRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Créditos insuficientes. Recarregue para continuar.')),
      );
      Navigator.of(context).pushNamed('/credits-shop');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Faça login para continuar.')),
        );
        return;
      }

      final result = await resizeAndCompressForEdit(
        inputPath: _selectedImagePath!,
        maxMegapixels: 1.5,
      );
      final storagePath = '${user.id}/inputs/${const Uuid().v4()}.jpg';
      await Supabase.instance.client.storage
          .from(AppConfig.editInputsBucket)
          .upload(storagePath, result.file, fileOptions: const FileOptions(upsert: false));
      try {
        await result.file.delete();
      } catch (_) {}

      final dio = DioClient();
      final response = await dio.instance.post<Map<String, dynamic>>(
        '/functions/v1/editar-imagem-modelo',
        data: {
          'modelo_id': modeloId,
          'storage_path': storagePath,
          'width': result.width,
          'height': result.height,
        },
      );

      if (!mounted) return;

      final data = response.data;
      String? taskId;
      String? editId;
      if (data != null) {
        if (data['task_id'] is String) {
          final raw = data['task_id'] as String;
          if (raw.isNotEmpty) taskId = raw;
        }
        if (data['edit_id'] is String) {
          final raw = data['edit_id'] as String;
          if (raw.isNotEmpty) editId = raw;
        }
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

      ref.invalidate(creditsUsageProvider);
      ref.invalidate(planLimitsProvider);
      Navigator.of(context).pushNamed(
        '/processing',
        arguments: <String, dynamic>{
          'taskId': taskId,
          'editId': editId,
          'beforePath': _selectedImagePath,
          'before': null,
          'after': null,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 402) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Créditos insuficientes. Recarregue para continuar.')),
          );
          Navigator.of(context).pushNamed('/credits-shop');
        } else if (statusCode == 404) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Modelo não encontrado. Volte e tente novamente.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro ao comunicar com o servidor. Verifique sua conexão e tente novamente.'),
            ),
          );
        }
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
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final modeloNome = args?['modeloNome'] as String? ?? 'Editar com modelo';
    final categoriaNome = args?['categoriaNome'] as String?;
    final modeloDescricao = args?['modeloDescricao'] as String?;
    final modeloPromptPadrao = args?['modeloPromptPadrao'] as String?;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  if (categoriaNome != null && categoriaNome.isNotEmpty) ...[
                    Text(
                      categoriaNome,
                      style: AppTextStyles.headingMedium.copyWith(
                        color: isDark ? AppColors.textLight : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 180,
                            height: 180,
                            child: Lottie.asset(
                              'assets/animations/cloud_robotics_abstract.json',
                              fit: BoxFit.contain,
                              repeat: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.auto_awesome,
                                  size: 60,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Processando...',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: isDark
                                  ? AppColors.textTertiary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            modeloNome,
                            style: AppTextStyles.headingSmall.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.textLight : AppColors.textPrimary,
                            ),
                          ),
                          if (modeloDescricao != null && modeloDescricao.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              modeloDescricao,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: isDark
                                    ? AppColors.textTertiary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Selecione uma imagem para aplicar o modelo',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: isDark
                                  ? AppColors.textTertiary
                                  : AppColors.textSecondary,
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
                          if (modeloPromptPadrao != null &&
                              modeloPromptPadrao.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Prompt que será aplicado',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: isDark
                                    ? AppColors.textTertiary
                                    : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              modeloPromptPadrao,
                              style: AppTextStyles.caption.copyWith(
                                color: (isDark
                                        ? AppColors.textTertiary
                                        : AppColors.textSecondary)
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
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
                  final hasEnoughCredits = isLoadingCredits || balance >= _creditsRequired;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          if (!hasEnoughCredits && !_isLoading) {
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
                          absorbing: !hasEnoughCredits,
                          child: AppButton(
                            text: 'Gerar',
                            onPressed: hasEnoughCredits ? _handleGenerate : null,
                            icon: Icons.auto_fix_high,
                            width: double.infinity,
                            isLoading: _isLoading,
                          ),
                        ),
                      ),
                      if (!isLoadingCredits && balance < _creditsRequired) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Você precisa de $_creditsRequired créditos. Toque no botão para comprar.',
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
