import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class ProcessingPage extends StatefulWidget {
  const ProcessingPage({super.key});

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage> {
  double _progress = 0.0;
  bool _hasError = false;
  String? _errorMessage;
  RealtimeChannel? _channel;
  String? _beforePathFromArgs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initProcessing();
    });
  }

  Future<void> _initProcessing() async {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final String? taskId = args != null ? args['taskId'] as String? : null;
    _beforePathFromArgs = args != null ? args['beforePath'] as String? : null;

    if (taskId == null || taskId.isEmpty) {
      // Modo legacy: simulação local
      await _simulateProcessing(args);
    } else {
      // Modo Flux: Supabase Realtime + fallback
      await _startFluxProcessing(taskId);
    }
  }

  Future<void> _startFluxProcessing(String taskId) async {
    final supabase = Supabase.instance.client;

    _channel = supabase
        .channel('flux-task-$taskId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'flux_tasks',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'task_id',
          value: taskId,
        ),
        callback: (payload) {
          final record = payload.newRecord;
          if (record is Map<String, dynamic>) {
            _handleTaskRecord(record);
          }
        },
      )
      ..subscribe();

    // Fallback obrigatório após inscrição
    try {
      final res = await supabase
          .from('flux_tasks')
          .select()
          .eq('task_id', taskId)
          .maybeSingle();

      if (res != null && res is Map<String, dynamic>) {
        _handleTaskRecord(res);
      }
    } catch (_) {
      // Em caso de erro no fallback, continuamos aguardando via Realtime
    }
  }

  void _handleTaskRecord(Map<String, dynamic> record) {
    if (!mounted) return;
    final status = record['status'] as String?;
    if (status == null) return;

    if (status == 'ready') {
      final imageUrl = record['image_url'] as String?;
      _cleanupChannel();
      if (_beforePathFromArgs != null) {
        // Fluxo editar-imagem: mostrar comparação (antes + resultado por URL)
        Navigator.of(context).pushReplacementNamed(
          '/comparison',
          arguments: <String, dynamic>{
            'before': _beforePathFromArgs,
            'after': null,
            'afterUrl': imageUrl,
          },
        );
      } else {
        // Fluxo texto para imagem
        Navigator.of(context).pushReplacementNamed(
          '/text-to-image-result',
          arguments: imageUrl,
        );
      }
    } else if (status == 'error') {
      final message =
          record['error_message'] as String? ?? 'Ocorreu um erro ao gerar a imagem.';
      setState(() {
        _hasError = true;
        _errorMessage = message;
      });
      _cleanupChannel();
    }
  }

  Future<void> _simulateProcessing(Map<String, dynamic>? args) async {
    // Simulate processing
    for (int i = 0; i <= 100; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      setState(() {
        _progress = i / 100;
      });
    }

    // Navigate to comparison after processing
    if (!mounted) return;
    final before = args != null ? args['before'] as String? : null;
    final after = args != null ? args['after'] as String? : null;
    Navigator.of(context).pushReplacementNamed(
      '/comparison',
      arguments: <String, String?>{
        'before': before,
        'after': after,
      },
    );
  }

  void _cleanupChannel() {
    if (_channel != null) {
      _channel!.unsubscribe();
      _channel = null;
    }
  }

  @override
  void dispose() {
    _cleanupChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated icon
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
                const SizedBox(height: 32),
                // Title
                Text(
                  'Processando sua edição...',
                  style: AppTextStyles.headingLarge.copyWith(
                    color: isDark ? AppColors.textLight : AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (_hasError) ...[
                  Text(
                    _errorMessage ??
                        'Ocorreu um erro ao processar sua edição. Tente novamente.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Voltar',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Nossa IA está trabalhando para criar o melhor resultado',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: isDark
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  // Loading animation
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Cancel button
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Cancelar',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

