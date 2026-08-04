import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../gallery/presentation/providers/gallery_provider.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../subscription/presentation/providers/plan_limits_provider.dart';

class ProcessingPage extends ConsumerStatefulWidget {
  const ProcessingPage({super.key});

  @override
  ConsumerState<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends ConsumerState<ProcessingPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _hasError = false;
  bool _hasTimeout = false;
  bool _hasFinished = false;
  String? _errorMessage;
  RealtimeChannel? _channel;
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  String? _beforePathFromArgs;
  String? _editId;
  String? _taskId;

  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 70),
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _progressController.animateTo(0.88, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initProcessing();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_hasError && !_hasFinished) {
      _recheckStatus();
    }
  }

  Future<void> _initProcessing() async {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _taskId = args != null ? args['taskId'] as String? : null;
    _editId = args != null ? args['editId'] as String? : null;
    _beforePathFromArgs = args != null ? args['beforePath'] as String? : null;

    if (_editId != null && _editId!.isNotEmpty) {
      await _startEditProcessing(_editId!);
      _scheduleProcessingTimeout();
    } else if (_taskId != null && _taskId!.isNotEmpty) {
      await _startFluxProcessing(_taskId!);
      _scheduleProcessingTimeout();
    } else {
      await _simulateProcessing(args);
    }
  }

  void _scheduleProcessingTimeout() {
    if (_hasFinished) return;
    final hasRealJob = (_editId != null && _editId!.isNotEmpty) ||
        (_taskId != null && _taskId!.isNotEmpty);
    if (!hasRealJob) return;
    _cancelTimeoutTimer();
    _timeoutTimer = Timer(const Duration(seconds: 80), () {
      unawaited(_onProcessingTimeout());
    });
  }

  void _cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  Future<String?> _resolveEditIdForRelease() async {
    if (_editId != null && _editId!.isNotEmpty) return _editId;
    final taskId = _taskId;
    if (taskId == null || taskId.isEmpty) return null;
    try {
      final res = await Supabase.instance.client
          .from('flux_tasks')
          .select('edit_id')
          .eq('task_id', taskId)
          .maybeSingle();
      final id = res?['edit_id'];
      return id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onProcessingTimeout() async {
    if (!mounted || _hasFinished || _hasError) return;

    _cleanupChannel();
    _progressController.stop();

    await _recheckStatus();
    if (!mounted || _hasFinished) return;

    final effectiveEditId = await _resolveEditIdForRelease();
    if (effectiveEditId != null) {
      try {
        await Supabase.instance.client.rpc(
          'user_release_pending_reservation_for_edit',
          params: <String, dynamic>{
            'p_edit_id': effectiveEditId,
            'p_reason': 'client_processing_timeout',
          },
        );
      } catch (e, st) {
        debugPrint('[ProcessingPage] Falha ao liberar reserva: $e\n$st');
      }
    }

    ref.invalidate(creditsUsageProvider);
    ref.invalidate(planLimitsProvider);

    if (!mounted || _hasFinished) return;
    setState(() {
      _hasError = true;
      _hasTimeout = true;
      _errorMessage =
          'A operação demorou mais do que o esperado. Tente novamente mais tarde.';
    });
  }

  void _startPolling() {
    _cancelPolling();
    _recheckStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _hasError || _hasFinished) return;
      _recheckStatus();
    });
  }

  void _cancelPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _recheckStatus() async {
    if (!mounted || _hasError || _hasFinished) return;

    if (_editId != null && _editId!.isNotEmpty) {
      try {
        final res = await Supabase.instance.client
            .from('edits')
            .select()
            .eq('id', _editId!)
            .maybeSingle();

        if (res != null) {
          _handleEditRecord(Map<String, dynamic>.from(res as Map));
        }
      } catch (_) {}
    } else if (_taskId != null && _taskId!.isNotEmpty) {
      try {
        final res = await Supabase.instance.client
            .from('flux_tasks')
            .select()
            .eq('task_id', _taskId!)
            .maybeSingle();

        if (res != null) {
          _handleTaskRecord(Map<String, dynamic>.from(res as Map));
        }
      } catch (_) {}
    }
  }

  Future<void> _startEditProcessing(String editId) async {
    final supabase = Supabase.instance.client;

    _channel = supabase.channel('edit-$editId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'edits',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: editId,
        ),
        callback: (payload) {
          _handleEditRecord(payload.newRecord);
        },
      )
      ..subscribe();

    _startPolling();

    try {
      final res = await supabase
          .from('edits')
          .select()
          .eq('id', editId)
          .maybeSingle();

      if (res != null) {
        _handleEditRecord(Map<String, dynamic>.from(res as Map));
      }
    } catch (_) {}
  }

  void _handleEditRecord(Map<String, dynamic> record) {
    if (!mounted) return;
    final status = record['status'] as String?;
    if (status == null) return;

    if (status == 'completed') {
      final imageUrl = record['image_url'] as String?;
      _hasFinished = true;
      _cleanupChannel();
      ref.invalidate(recentEditsProvider);
      ref.invalidate(planLimitsProvider);
      if (_beforePathFromArgs != null) {
        Navigator.of(context).pushReplacementNamed(
          '/comparison',
          arguments: <String, dynamic>{
            'editId': record['id'],
            'before': _beforePathFromArgs,
            'after': null,
            'afterUrl': imageUrl,
          },
        );
      } else {
        Navigator.of(context).pushReplacementNamed(
          '/text-to-image-result',
          arguments: imageUrl,
        );
      }
    } else if (status == 'failed') {
      _progressController.stop();
      setState(() {
        _hasError = true;
        _errorMessage = 'Ocorreu um erro ao gerar a imagem.';
      });
      _cleanupChannel();
    }
  }

  Future<void> _startFluxProcessing(String taskId) async {
    final supabase = Supabase.instance.client;

    _channel = supabase.channel('flux-task-$taskId')
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
          _handleTaskRecord(payload.newRecord);
        },
      )
      ..subscribe();

    _startPolling();

    try {
      final res = await supabase
          .from('flux_tasks')
          .select()
          .eq('task_id', taskId)
          .maybeSingle();

      if (res != null) {
        _handleTaskRecord(Map<String, dynamic>.from(res as Map));
      }
    } catch (_) {}
  }

  void _handleTaskRecord(Map<String, dynamic> record) {
    if (!mounted) return;
    final status = record['status'] as String?;
    if (status == null) return;

    if (status == 'ready') {
      final imageUrl = record['image_url'] as String?;
      _hasFinished = true;
      _cleanupChannel();
      ref.invalidate(recentEditsProvider);
      ref.invalidate(planLimitsProvider);
      if (_beforePathFromArgs != null) {
        Navigator.of(context).pushReplacementNamed(
          '/comparison',
          arguments: <String, dynamic>{
            'editId': record['edit_id'],
            'before': _beforePathFromArgs,
            'after': null,
            'afterUrl': imageUrl,
          },
        );
      } else {
        Navigator.of(context).pushReplacementNamed(
          '/text-to-image-result',
          arguments: imageUrl,
        );
      }
    } else if (status == 'error') {
      final message = record['error_message'] as String? ??
          'Ocorreu um erro ao gerar a imagem.';
      _progressController.stop();
      setState(() {
        _hasError = true;
        _errorMessage = message;
      });
      _cleanupChannel();
    }
  }

  Future<void> _simulateProcessing(Map<String, dynamic>? args) async {
    for (var i = 0; i <= 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }

    if (!mounted) return;
    ref.invalidate(recentEditsProvider);
    ref.invalidate(planLimitsProvider);
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
    _cancelTimeoutTimer();
    _cancelPolling();
    if (_channel != null) {
      _channel!.unsubscribe();
      _channel = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressController.dispose();
    _cleanupChannel();
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _progressController.value;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: isDark ? AppColors.textLight : AppColors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Text(
          'Estamos editando sua foto',
          style: AppTextStyles.labelLarge.copyWith(
            color: isDark ? AppColors.textLight : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Image.asset(
                'assets/illustrations/processing_illustration.png',
                height: 220,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 64,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              Text(
                _hasError ? 'Não foi possível concluir' : 'Aguarde um momento',
                style: AppTextStyles.headingMedium.copyWith(
                  color: isDark ? AppColors.textLight : AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                _hasError
                    ? (_errorMessage ??
                        'Ocorreu um erro ao processar sua edição. Tente novamente.')
                    : 'Sua foto fica pronta em alguns segundos.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: _hasError
                      ? AppColors.error
                      : (isDark
                          ? AppColors.textTertiary
                          : AppColors.textSecondary),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (!_hasError) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.05, 1.0),
                    minHeight: 10,
                    backgroundColor: isDark
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : const Color(0xFFE8F0FE),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Processando...',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Sua foto está segura.',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: isDark
                              ? AppColors.textLight
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _hasError
                      ? (_hasTimeout
                          ? _goHome
                          : () => Navigator.of(context).pop())
                      : _goHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Spacer(),
                      Text(
                        _hasError
                            ? (_hasTimeout ? 'Ir para o início' : 'Voltar')
                            : 'Continuar no app',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
