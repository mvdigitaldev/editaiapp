import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/credit_pack_card.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/credit_packs_datasource.dart';
import '../../data/models/credit_pack_model.dart';

final _creditPacksDataSourceProvider = Provider<CreditPacksDataSource>((ref) {
  return CreditPacksDataSourceImpl(Supabase.instance.client);
});

final _activeCreditPacksProvider =
    FutureProvider<List<CreditPackModel>>((ref) async {
  final ds = ref.watch(_creditPacksDataSourceProvider);
  return ds.getActivePacks();
});

class CreditsShopPage extends ConsumerWidget {
  const CreditsShopPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).user;
    final packsAsync = ref.watch(_activeCreditPacksProvider);
    final creditsBalance = user?.creditsBalance ?? 0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    'Créditos Extra',
                    style: AppTextStyles.headingMedium.copyWith(
                      color: isDark
                          ? AppColors.textLight
                          : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: packsAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: AppColors.error),
                        const SizedBox(height: 16),
                        Text(
                          'Não foi possível carregar os pacotes.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: isDark
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () =>
                              ref.invalidate(_activeCreditPacksProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (packs) =>
                    _buildContent(context, isDark, packs, creditsBalance),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, bool isDark, List<CreditPackModel> packs,
      int creditsBalance) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildBalanceCard(isDark, creditsBalance),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Escolha um pacote',
              style: AppTextStyles.headingSmall.copyWith(
                color: isDark ? AppColors.textLight : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Desbloqueie ferramentas premium de IA',
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textTertiary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (packs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Nenhum pacote disponível no momento.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                ),
              ),
            )
          else
            ...packs.map((pack) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: CreditPackCard(
                    icon: _iconForPack(pack),
                    name: pack.name,
                    credits: pack.credits,
                    price: pack.formattedPrice,
                    isPopular: pack.isPopular,
                    hasSavings: pack.hasSavings,
                    onTap: () {
                      if (pack.linkPayment != null &&
                          pack.linkPayment!.isNotEmpty) {
                        Navigator.of(context).pushNamed(
                          '/checkout',
                          arguments: pack.linkPayment,
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Link de pagamento não disponível para este pacote.'),
                          ),
                        );
                      }
                    },
                  ),
                )),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Use para remoção de fundo, upscaling, transferência de estilo e muito mais.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    '/legal-document',
                    arguments: 'terms-of-use',
                  );
                },
                child: Text(
                  'TERMOS',
                  style: AppTextStyles.overline.copyWith(
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
                  Navigator.of(context).pushNamed(
                    '/legal-document',
                    arguments: 'privacy-policy',
                  );
                },
                child: Text(
                  'PRIVACIDADE',
                  style: AppTextStyles.overline.copyWith(
                    color: isDark
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(bool isDark, int creditsBalance) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.bolt,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seus créditos',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$creditsBalance',
                      style: AppTextStyles.headingLarge.copyWith(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'disponíveis',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForPack(CreditPackModel pack) {
    if (pack.hasSavings) return Icons.layers;
    if (pack.isPopular) return Icons.toll;
    return Icons.token;
  }
}
