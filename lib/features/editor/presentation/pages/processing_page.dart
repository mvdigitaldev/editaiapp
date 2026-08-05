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
          onPressed: _goBackToHome,
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
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => SizedBox(
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
              ),
              const SizedBox(height: 32),
              Text(
                _hasError
                    ? 'Não foi possível concluir'
                    : 'Aguarde um momento',
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
                        'Não foi possível concluir esta edição.')
                    : 'Sua foto fica pronta em alguns segundos. Você pode sair e continuar usando o app.',
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
              if (!_hasError) ...[
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
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
                  _isLongRunning
                      ? 'Ainda processando… está demorando um pouco mais'
                      : 'Processando...',
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
              if (_hasError) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _openEditDetail,
                    child: const Text('Ver detalhes da edição'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _goBackToHome,
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
                        _hasError ? 'Voltar' : 'Continuar no app',
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
