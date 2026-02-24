import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:editaiapp/features/subscription/presentation/providers/credits_usage_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final creditsUsageAsync = ref.watch(creditsUsageProvider);

    return SafeArea(
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Painel',
                    style: AppTextStyles.headingLarge.copyWith(
                      color: isDark
                          ? AppColors.textLight
                          : AppColors.textPrimary,
                    ),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: Icon(
                      Icons.person,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Bem-vindo, ${user?.displayName ?? 'criador(a)'}',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              AppCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.bolt,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Uso de Créditos',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: isDark
                                    ? AppColors.textLight
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    creditsUsageAsync.when(
                      loading: () => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      error: (error, _) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Não foi possível carregar o uso de créditos.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: isDark
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      data: (usage) {
                        final used = usage.used;
                        final total = usage.total;
                        final progress = usage.progress;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Créditos usados',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: isDark
                                        ? AppColors.textTertiary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                                Text(
                                  total > 0 ? '$used/$total' : '0/0',
                                  style: AppTextStyles.headingSmall.copyWith(
                                    color: isDark
                                        ? AppColors.textLight
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 8,
                                backgroundColor: isDark
                                    ? AppColors.surfaceDarkSecondary
                                    : AppColors.border,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              total > 0
                                  ? 'Você já usou $used créditos do total de $total disponíveis na sua conta.'
                                  : 'Você ainda não usou créditos na sua conta.',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: isDark
                                    ? AppColors.textTertiary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pushNamed('/credits-shop');
                        },
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'Recarregar Créditos',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Histórico de créditos',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textLight
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Em breve você verá aqui todas as entradas e saídas de créditos da sua conta.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

