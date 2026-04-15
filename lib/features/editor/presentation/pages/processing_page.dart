import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../gallery/presentation/providers/gallery_provider.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../subscription/presentation/providers/plan_limits_provider.dart';
import '../providers/active_edits_provider.dart';

class ProcessingPage extends ConsumerStatefulWidget {
  const ProcessingPage({super.key});

  @override
  ConsumerState<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends ConsumerState<ProcessingPage>
    with WidgetsBindingObserver {
  bool _hasError = false;
  bool _hasFinished = false;
  bool _isLongRunning = false;
  String? _errorMessage;
  String? _beforePathFromArgs;
  String? _editId;
  Timer? _pollTimer;
  Timer? _longWaitTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initProcessing());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_hasFinished) {
      unawaited(ref.read(activeEditsProvider.notifier).syncNow());
      unawaited(_recheckStatus());
    }
  }

  Future<void> _initProcessing() async {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _beforePathFromArgs = args?['beforePath'] as String?;
    _editId = args?['editId'] as String?;

    if ((_editId == null || _editId!.isEmpty) &&
        args?['taskId'] is String &&
        (args?['taskId'] as String).isNotEmpty) {
      _editId = await _resolveEditIdFromTask(args?['taskId'] as String);
    }

    if (!mounted) return;

    if (_editId == null || _editId!.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Não foi possÃ­vel localizar esta edição.';
      });
      return;
    }

    _scheduleLongWaitNotice();
    _startPolling();
    await _recheckStatus();
  }

  Future<String?> _resolveEditIdFromTask(String taskId) async {
    try {
      final response = await Supabase.instance.client
          .from('flux_tasks')
          .select('edit_id')
          .eq('task_id', taskId)
          .maybeSingle();
      final editId = response?['edit_id'];
      if (editId is String && editId.isNotEmpty) {
        return editId;
      }
    } catch (_) {}
    return null;
  }

  void _scheduleLongWaitNotice() {
    _longWaitTimer?.cancel();
    _longWaitTimer = Timer(const Duration(seconds: 80), () {
      if (!mounted || _hasFinished) return;
      setState(() => _isLongRunning = true);
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _hasFinished) return;
      unawaited(_recheckStatus());
    });
  }

  Future<void> _recheckStatus() async {
    final editId = _editId;
    if (!mounted || _hasFinished || editId == null || editId.isEmpty) {
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('edits')
          .select('id, status')
          .eq('id', editId)
          .maybeSingle();

      if (response == null || !mounted) return;
      final record = Map<String, dynamic>.from(response as Map);
      await _handleEditRecord(record);
    } catch (_) {}
  }

  Future<void> _handleEditRecord(Map<String, dynamic> record) async {
    if (!mounted) return;

    final status = record['status'] as String?;
    if (status == null || status.isEmpty) return;

    if (status == 'completed') {
      _hasFinished = true;
      _cleanupTimers();
      ref.invalidate(recentEditsProvider);
      Navigator.of(context).pushReplacementNamed(
        '/comparison',
        arguments: <String, dynamic>{
          'editId': record['id'],
          if (_beforePathFromArgs != null && _beforePathFromArgs!.isNotEmpty)
            'before': _beforePathFromArgs,
        },
      );
      return;
    }

    if (status == 'failed') {
      _cleanupTimers();
      setState(() {
        _hasError = true;
        _errorMessage =
            'Não foi possÃ­vel concluir esta edição. Você pode acompanhar os detalhes no histÃ³rico.';
      });
    }
  }

  void _cleanupTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _longWaitTimer?.cancel();
    _longWaitTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupTimers();
    super.dispose();
  }

  void _openEditDetail() {
    final editId = _editId;
    if (editId == null || editId.isEmpty) return;
    Navigator.of(context).pushReplacementNamed(
      '/edit-detail',
      arguments: editId,
    );
  }

  /// Volta ao shell principal na aba Galeria, sem repor o formulário de edição.
  void _goBackToHome() {
    ref.invalidate(recentEditsProvider);
    ref.invalidate(creditsUsageProvider);
    ref.invalidate(planLimitsProvider);
    ref.invalidate(currentMonthUsageTotalProvider);
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/home',
      (route) => route.isFirst,
      arguments: AppBottomNav.indexGallery,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: _goBackToHome,
                  ),
                  Expanded(
                    child: Text(
                      'Processamento em andamento',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headingMedium.copyWith(
                        color: isDark
                            ? AppColors.textLight
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: 180,
                height: 180,
                child: Lottie.asset(
                  'assets/animations/cloud_robotics_abstract.json',
                  fit: BoxFit.contain,
                  repeat: true,
                  errorBuilder: (context, error, stackTrace) => Container(
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
                _hasError
                    ? 'Sua edição precisa de atenção'
                    : 'Sua edição continua sendo processada',
                style: AppTextStyles.headingLarge.copyWith(
                  color:
                      isDark ? AppColors.textLight : AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _hasError
                    ? (_errorMessage ??
                        'Não foi possível concluir esta edição.')
                    : 'Você pode sair desta tela e continuar usando o app. Vamos avisar quando ela ficar pronta.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: _hasError
                      ? AppColors.error
                      : (isDark
                          ? AppColors.textTertiary
                          : AppColors.textSecondary),
                ),
                textAlign: TextAlign.center,
              ),
              if (!_hasError) ...[
                const SizedBox(height: 16),
                Text(
                  _isLongRunning
                      ? 'Ela está levando mais tempo que o normal, mas continua rodando no servidor.'
                      : 'Sair da tela Não cancela o job, Não perde a edição e Não afeta seus créditos.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              if (_hasError) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _openEditDetail,
                    child: const Text('Ver detalhes da edição'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _goBackToHome,
                  child: Text(
                    _hasError ? 'Voltar' : 'Voltar e continuar no app',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: isDark
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
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
