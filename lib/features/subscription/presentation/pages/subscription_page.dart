import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/server_date_utils.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/plan_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/plans_datasource.dart';
import '../../data/models/plan_model.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final plansDataSourceProvider = Provider<PlansDataSource>((ref) {
  return PlansDataSourceImpl(ref.watch(supabaseClientProvider));
});

final activePlansProvider = FutureProvider<List<PlanModel>>((ref) async {
  final dataSource = ref.watch(plansDataSourceProvider);
  return dataSource.getActivePlans();
});

class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage> {
  PlanModel? _selectedPlan;
  int _selectedDuration = 1; // 1 = Mensal, 3 = Trimestral, 6 = Semestral

  String _formatDate(DateTime? date) {
    if (date == null) return '--';
    return ServerDateUtils.formatForDisplay(date, pattern: 'dd/MM/yyyy');
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(activePlansProvider);
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final hasPaidPlan = user != null &&
        user.subscriptionTier.toLowerCase() != 'free';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                    'Planos',
                    style: AppTextStyles.headingMedium.copyWith(
                      color: isDark ? AppColors.textLight : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Progress indicator
                    Container(
                      width: 64,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    Text(
                      'Liberte sua\ncriatividade.',
                      style: AppTextStyles.displaySmall.copyWith(
                        color: isDark ? AppColors.textLight : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Escolha o plano que melhor se adapta ao seu fluxo de trabalho profissional.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (hasPaidPlan) ...[
                      const SizedBox(height: 24),
                      _CurrentPlanCard(
                        planName: user.subscriptionTier,
                        startedAt: _formatDate(user.subscriptionStartedAt),
                        expiresAt: _formatDate(user.subscriptionEndsAt),
                        photoExpirationDays: user.photoExpirationDays,
                        creditExpirationDays: user.creditExpirationDays,
                        creditReferral: user.creditReferral,
                        addCredit: user.addCredit,
                        isDark: isDark,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Planos disponíveis para você',
                      style: AppTextStyles.headingSmall.copyWith(
                        color: isDark ? AppColors.textLight : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Escolha o período e o plano que melhor se encaixa no seu ritmo.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    plansAsync.when(
                      data: (plans) {
                        final availableDurations = plans
                            .map((p) => p.durationMonths ?? 1)
                            .where((d) => d > 0)
                            .toSet()
                            .toList()
                          ..sort();

                        final showTabs = availableDurations.length >= 2;
                        final effectiveDuration = showTabs
                            ? (availableDurations.contains(_selectedDuration)
                                ? _selectedDuration
                                : availableDurations.first)
                            : null;

                        final filtered = showTabs
                            ? plans
                                .where(
                                  (p) =>
                                      (p.durationMonths ?? 1) ==
                                      effectiveDuration,
                                )
                                .toList()
                            : plans;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showTabs) ...[
                              Container(
                                height: 48,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.surfaceDark
                                      : AppColors.backgroundLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    for (final duration in availableDurations)
                                      _DurationTab(
                                        label: PlanModel.tabLabelForDuration(
                                            duration),
                                        isSelected:
                                            effectiveDuration == duration,
                                        isDark: isDark,
                                        onTap: () {
                                          setState(() {
                                            _selectedDuration = duration;
                                            _selectedPlan = null;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 24),
                            ],
                            if (filtered.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Center(
                                  child: Text(
                                    'Nenhum plano disponível para este período.',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: isDark
                                          ? AppColors.textTertiary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Column(
                                children: [
                                  for (final plan in filtered) ...[
                                    PlanCard(
                                      tier: plan.durationText.toUpperCase(),
                                      name: plan.name,
                                      price: plan.formattedPrice,
                                      isHighlighted:
                                          _selectedPlan?.id == plan.id,
                                      features: plan.features,
                                      onTap: () {
                                        setState(() {
                                          _selectedPlan = plan;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  const SizedBox(height: 100),
                                ],
                              ),
                          ],
                        );
                      },
                      loading: () => Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                      ),
                      error: (error, _) => Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Não foi possível carregar os planos.',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: isDark
                                    ? AppColors.textTertiary
                                    : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            AppButton(
                              text: 'Tentar novamente',
                              onPressed: () {
                                ref.invalidate(activePlansProvider);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.backgroundDark.withOpacity(0.9)
                    : AppColors.surfaceLight.withOpacity(0.9),
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.borderDark : AppColors.border,
                  ),
                ),
              ),
              child: Column(
                children: [
                  AppButton(
                    text: 'ASSINAR AGORA',
                    onPressed: _selectedPlan == null ? null : () {
                      final plan = _selectedPlan;
                      if (plan == null) return;

                      final link = plan.linkPayment;
                      if (link == null || link.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Este plano não possui link de pagamento configurado.'),
                          ),
                        );
                        return;
                      }

                      Navigator.of(context).pushNamed(
                        '/checkout',
                        arguments: link,
                      );
                    },
                    width: double.infinity,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          // TODO: Restore purchases
                        },
                        child: Text(
                          'Restaurar Compra',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: isDark
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '•',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.textTertiary
                              : AppColors.textSecondary,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // TODO: Terms
                        },
                        child: Text(
                          'Termos de Uso',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: isDark
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _DurationTab({
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? AppColors.surfaceDark : AppColors.surfaceLight)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: isSelected
                    ? (isDark ? AppColors.primary : AppColors.textPrimary)
                    : (isDark ? AppColors.textTertiary : AppColors.textSecondary),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final String planName;
  final String startedAt;
  final String expiresAt;
  final int? photoExpirationDays;
  final int? creditExpirationDays;
  final int? creditReferral;
  final int? addCredit;
  final bool isDark;

  const _CurrentPlanCard({
    required this.planName,
    required this.startedAt,
    required this.expiresAt,
    this.photoExpirationDays,
    this.creditExpirationDays,
    this.creditReferral,
    this.addCredit,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primary.withOpacity(0.08)
            : AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Seu plano atual',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            planName.toUpperCase(),
            style: AppTextStyles.headingSmall.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PlanInfoItem(
                  label: 'Contratado em',
                  value: startedAt,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _PlanInfoItem(
                  label: 'Expira em',
                  value: expiresAt,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          if (photoExpirationDays != null ||
              creditExpirationDays != null ||
              creditReferral != null ||
              addCredit != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.04),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  if (photoExpirationDays != null)
                    _PlanDetailRow(
                      icon: Icons.photo_library_outlined,
                      label: 'Foto expira em',
                      value: '$photoExpirationDays dias',
                      isDark: isDark,
                      showDivider: creditExpirationDays != null ||
                          creditReferral != null,
                    ),
                  if (creditExpirationDays != null)
                    _PlanDetailRow(
                      icon: Icons.schedule_outlined,
                      label: 'Créditos expiram em',
                      value: '$creditExpirationDays dias',
                      isDark: isDark,
                      showDivider: creditReferral != null || addCredit != null,
                    ),
                  if (creditReferral != null)
                    _PlanDetailRow(
                      icon: Icons.card_giftcard_outlined,
                      label: 'Recompensa por indicação',
                      value: creditReferral == 0
                          ? 'Sem bônus'
                          : '$creditReferral créditos',
                      isDark: isDark,
                      showDivider: addCredit != null,
                    ),
                  if (addCredit != null)
                    _PlanDetailRow(
                      icon: Icons.refresh_outlined,
                      label: 'Créditos na renovação',
                      value: addCredit == 0
                          ? 'Nenhum'
                          : '$addCredit créditos',
                      isDark: isDark,
                      showDivider: false,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final bool showDivider;

  const _PlanDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: AppColors.primary.withOpacity(0.9),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                style: AppTextStyles.labelMedium.copyWith(
                  color: isDark ? AppColors.textLight : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
          ),
      ],
    );
  }
}

class _PlanInfoItem extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _PlanInfoItem({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodySmall.copyWith(
            color: isDark ? AppColors.textLight : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

