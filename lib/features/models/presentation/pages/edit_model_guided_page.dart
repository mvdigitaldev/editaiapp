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
import '../../../../core/utils/pending_credit_reservation.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../subscription/presentation/providers/plan_limits_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/upload_area.dart';

/// Edição com modelo em categoria [guided]: análise IA → sugestões → texto livre → geração.
class EditModelGuidedPage extends ConsumerStatefulWidget {
  const EditModelGuidedPage({super.key});

  @override
  ConsumerState<EditModelGuidedPage> createState() =>
      _EditModelGuidedPageState();
}

class _EditModelGuidedPageState extends ConsumerState<EditModelGuidedPage> {
  String? _selectedImagePath;
  String? _storagePath;
  int _width = 1024;
  int _height = 1024;

  final Set<String> _selectedSuggestions = {};
  final TextEditingController _notesController = TextEditingController();
  List<String> _suggestions = [];
  bool _analyzing = false;
  bool _isLoading = false;

  static const int _creditsRequired = 7;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _onImageSelected(File file) {
    setState(() {
      _selectedImagePath = file.path;
      _storagePath = null;
      _suggestions = [];
      _selectedSuggestions.clear();
    });
  }

  Future<void> _analyzeImage() async {
    if (_selectedImagePath == null || _analyzing) return;

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final modeloId = args?['modeloId'] as String?;

    if (modeloId == null || modeloId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modelo inválido. Volte e tente novamente.')),
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faça login para continuar.')),
      );
      return;
    }

    final accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessão inválida. Saia e entre de novo no app.'),
        ),
      );
      return;
    }

    setState(() => _analyzing = true);

    try {
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

      final dio = DioClient().instance;
      final response = await dio.post<Map<String, dynamic>>(
        '/functions/v1/modelo-sugerir-melhorias',
        data: {
          'modelo_id': modeloId,
          'storage_path': storagePath,
          'width': result.width,
          'height': result.height,
          'access_token': accessToken,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (!mounted) return;

      final list = response.data?['suggestions'];
      if (list is! List || list.length < 5) {
        setState(() => _analyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível obter sugestões. Tente novamente.'),
          ),
        );
        return;
      }

      final strings = list.map((e) => '$e'.trim()).where((s) => s.isNotEmpty).toList();
      setState(() {
        _analyzing = false;
        _storagePath = storagePath;
        _width = result.width;
        _height = result.height;
        _suggestions = strings;
        _selectedSuggestions.clear();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _analyzing = false);
      final code = e.response?.statusCode;
      if (code == 401) {
        final err = e.response?.data;
        final msg = err is Map && err['error'] is String
            ? err['error'] as String
            : 'Sessão inválida ou expirada. Entre novamente.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      } else if (code == 422) {
        final msg = e.response?.data is Map
            ? '${e.response?.data['error'] ?? 'Requisição inválida'}'
            : 'Requisição inválida';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao analisar a imagem. Verifique a conexão e tente de novo.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _analyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao analisar a imagem. Tente novamente.'),
        ),
      );
    }
  }

  Future<void> _handleGenerate() async {
    if (_storagePath == null || _isLoading) return;

    final notes = _notesController.text.trim();
    if (_selectedSuggestions.isEmpty && notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione sugestões ou descreva o que deseja alterar.'),
        ),
      );
      return;
    }

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

      final accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sessão inválida. Saia e entre de novo no app.'),
          ),
        );
        return;
      }

      final dio = DioClient();
      final response = await dio.instance.post<Map<String, dynamic>>(
        '/functions/v1/editar-imagem-modelo',
        data: {
          'modelo_id': modeloId,
          'storage_path': _storagePath,
          'width': _width,
          'height': _height,
          'selected_improvements': _selectedSuggestions.toList(),
          'user_notes': notes.isEmpty ? null : notes,
          'access_token': accessToken,
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
        await tryReleasePendingReservationForEdit(editId);
        if (!mounted) return;
        ref.invalidate(creditsUsageProvider);
        ref.invalidate(planLimitsProvider);
        setState(() => _isLoading = false);
        final msg = data != null && data['error'] is String && (data['error'] as String).isNotEmpty
            ? data['error'] as String
            : 'Não foi possível iniciar a edição. Tente novamente.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
        await tryReleasePendingReservationForEdit(editIdFromDioResponse(e));
        if (!mounted) return;
        ref.invalidate(creditsUsageProvider);
        ref.invalidate(planLimitsProvider);
        final statusCode = e.response?.statusCode;
        final errMsg = e.response?.data is Map && (e.response!.data as Map)['error'] != null
            ? '${(e.response!.data as Map)['error']}'
            : null;
        if (statusCode == 402) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Créditos insuficientes. Recarregue para continuar.')),
          );
          Navigator.of(context).pushNamed('/credits-shop');
        } else if (statusCode == 404) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Modelo não encontrado. Volte e tente novamente.')),
          );
        } else if (statusCode == 401) {
          final err = e.response?.data;
          final msg = err is Map && err['error'] is String
              ? err['error'] as String
              : 'Sessão inválida ou expirada. Entre novamente.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        } else if (statusCode == 422) {
          final msg = e.response?.data is Map
              ? '${e.response?.data['error'] ?? 'Verifique os dados e tente de novo.'}'
              : 'Verifique os dados e tente de novo.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        } else if (statusCode == 502) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errMsg ??
                    'Serviço de edição temporariamente indisponível. Tente de novo em instantes.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errMsg ??
                    'Erro ao comunicar com o servidor. Verifique sua conexão e tente novamente.',
              ),
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

    final canGenerate = _storagePath != null &&
        (_selectedSuggestions.isNotEmpty || _notesController.text.trim().isNotEmpty);

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
                    Expanded(
                      child: Text(
                        categoriaNome,
                        style: AppTextStyles.headingMedium.copyWith(
                          color: isDark ? AppColors.textLight : AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
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
                                  color: AppColors.primary.withValues(alpha: 0.1),
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
                            'Objetivo base do modelo',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: isDark
                                  ? AppColors.textTertiary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (modeloPromptPadrao != null &&
                                    modeloPromptPadrao.trim().isNotEmpty)
                                ? modeloPromptPadrao
                                : '—',
                            style: AppTextStyles.caption.copyWith(
                              color: (isDark
                                      ? AppColors.textTertiary
                                      : AppColors.textSecondary)
                                  .withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '1. Selecione a foto',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.textLight : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          UploadArea(
                            imagePath: _selectedImagePath,
                            onImageSelected: _onImageSelected,
                            title: 'Enviar imagem',
                            subtitle: 'Toque para escolher',
                          ),
                          const SizedBox(height: 12),
                          AppButton(
                            text: _analyzing ? 'Analisando…' : 'Analisar imagem',
                            onPressed: (_selectedImagePath == null || _analyzing)
                                ? null
                                : _analyzeImage,
                            icon: Icons.psychology_outlined,
                            width: double.infinity,
                            isLoading: _analyzing,
                          ),
                          if (_suggestions.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(
                              '2. Escolha as melhorias (uma ou mais)',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.textLight : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final w = constraints.maxWidth;
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _suggestions.map((s) {
                                    final selected = _selectedSuggestions.contains(s);
                                    return SizedBox(
                                      width: w,
                                      child: FilterChip(
                                        label: DefaultTextStyle.merge(
                                          maxLines: null,
                                          overflow: TextOverflow.clip,
                                          softWrap: true,
                                          child: Text(
                                            s,
                                            softWrap: true,
                                            maxLines: 12,
                                          ),
                                        ),
                                        selected: selected,
                                        onSelected: (_) {
                                          setState(() {
                                            if (selected) {
                                              _selectedSuggestions.remove(s);
                                            } else {
                                              _selectedSuggestions.add(s);
                                            }
                                          });
                                        },
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '3. Mais detalhes (opcional)',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.textLight : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _notesController,
                              maxLines: 4,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Ex.: deixar o pão mais dourado, menos sombra…',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignLabelWithHint: true,
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
                            onPressed: (hasEnoughCredits && canGenerate && !_analyzing)
                                ? _handleGenerate
                                : null,
                            icon: Icons.auto_fix_high,
                            width: double.infinity,
                            isLoading: _isLoading,
                          ),
                        ),
                      ),
                      if (!isLoadingCredits && balance < _creditsRequired) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Você precisa de $_creditsRequired créditos. Toque no campo acima para comprar.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ] else if (_storagePath == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Analise a imagem para liberar sugestões e a geração.',
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
