import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/aspect_ratio_utils.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/aspect_ratio_selector.dart';

class TextToImagePage extends StatefulWidget {
  const TextToImagePage({super.key});

  @override
  State<TextToImagePage> createState() => _TextToImagePageState();
}

class _TextToImagePageState extends State<TextToImagePage> {
  final _promptController = TextEditingController();
  String _selectedAspectRatio = '1:1';
  bool _isLoading = false;

  Future<void> _handleGenerate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _isLoading) return;

    final size = getFluxSizeForAspect(_selectedAspectRatio);
    final supabase = Supabase.instance.client;

    setState(() {
      _isLoading = true;
    });

    try {
      // Autenticação: JWT na requisição (mesmo que Editar imagem)
      final session = supabase.auth.currentSession;
      final headers = <String, String>{};
      if (session != null) {
        headers['Authorization'] = 'Bearer ${session.accessToken}';
      }

      final res = await supabase.functions.invoke(
        'gerar-imagem-flux',
        body: {
          'user_prompt': prompt,
          'width': size.width,
          'height': size.height,
        },
        headers: headers.isNotEmpty ? headers : null,
      );

      if (!mounted) return;

      final data = res.data;
      String? taskId;
      if (data is Map) {
        final raw = data['task_id'];
        if (raw is String && raw.isNotEmpty) {
          taskId = raw;
        }
      }

      if (taskId == null) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível iniciar a geração da imagem. Tente novamente.'),
          ),
        );
        return;
      }

      // Navega para a tela de processamento em modo Flux
      Navigator.of(context).pushNamed(
        '/processing',
        arguments: <String, dynamic>{
          'taskId': taskId,
          'before': null,
          'after': null,
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao comunicar com o servidor. Verifique sua conexão e tente novamente.'),
        ),
      );
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
                    'Texto para imagem',
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
                      'Descreva a imagem que deseja criar',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                        maxLines: 6,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: isDark ? AppColors.textLight : AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ex: Um gato astronauta em Marte, estilo cartoon',
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
              child: AppButton(
                text: 'Gerar',
                onPressed: _handleGenerate,
                icon: Icons.auto_awesome,
                isLoading: _isLoading,
                width: double.infinity,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
