import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/plan_card.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  bool _isMonthly = true;

  @override
  Widget build(BuildContext context) {
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
                    const SizedBox(height: 24),
                    // Toggle Monthly/Yearly
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
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isMonthly = true;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _isMonthly
                                      ? (isDark
                                          ? AppColors.surfaceDark
                                          : AppColors.surfaceLight)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: _isMonthly
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
                                    'Mensal',
                                    style: AppTextStyles.labelMedium.copyWith(
                                      color: _isMonthly
                                          ? (isDark
                                              ? AppColors.primary
                                              : AppColors.textPrimary)
                                          : (isDark
                                              ? AppColors.textTertiary
                                              : AppColors.textSecondary),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isMonthly = false;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: !_isMonthly
                                      ? (isDark
                                          ? AppColors.surfaceDark
                                          : AppColors.surfaceLight)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: !_isMonthly
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
                                    'Anual',
                                    style: AppTextStyles.labelMedium.copyWith(
                                      color: !_isMonthly
                                          ? (isDark
                                              ? AppColors.primary
                                              : AppColors.textPrimary)
                                          : (isDark
                                              ? AppColors.textTertiary
                                              : AppColors.textSecondary),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Plans
                    PlanCard(
                      tier: 'INICIANTE',
                      name: 'Grátis',
                      price: 'R\$ 0',
                      features: const [
                        '5 créditos de IA por mês',
                        'Resolução padrão',
                        'Com marca d\'água',
                      ],
                      onTap: () {
                        // TODO: Handle free plan
                      },
                    ),
                    const SizedBox(height: 16),
                    PlanCard(
                      tier: 'PROFISSIONAL',
                      name: 'Premium',
                      price: _isMonthly ? 'R\$ 59' : 'R\$ 590',
                      isHighlighted: true,
                      badge: 'MELHOR ESCOLHA',
                      features: const [
                        '200 créditos/mês',
                        'Resolução Ultra HD (4K)',
                        'Processamento Prioritário',
                        'Acesso a todas ferramentas IA',
                      ],
                      onTap: () {
                        // TODO: Handle premium subscription
                      },
                    ),
                    const SizedBox(height: 16),
                    PlanCard(
                      tier: 'ENTUSIASTA',
                      name: 'Básico',
                      price: _isMonthly ? 'R\$ 29' : 'R\$ 290',
                      features: const [
                        '50 créditos por mês',
                        'Resolução High Def (2K)',
                        'Sem marca d\'água',
                      ],
                      onTap: () {
                        // TODO: Handle basic subscription
                      },
                    ),
                    const SizedBox(height: 100), // Space for footer
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
                    onPressed: () {
                      // TODO: Handle subscription
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
