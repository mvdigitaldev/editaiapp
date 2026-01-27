import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/progress_indicator.dart';
import '../../../../core/config/app_config.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart'
    as auth_providers;
import '../widgets/profile_bottom_nav.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    'Perfil',
                    style: AppTextStyles.headingMedium.copyWith(
                      color:
                          isDark ? AppColors.textLight : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      // TODO: Navigate to settings
                    },
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Profile Card
                    AppCard(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary.withOpacity(0.2),
                                    width: 2,
                                  ),
                                  image: user?.avatarUrl != null
                                      ? DecorationImage(
                                          image: NetworkImage(user!.avatarUrl!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: user?.avatarUrl == null
                                    ? const Icon(Icons.person, size: 40)
                                    : const SizedBox.shrink(),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.backgroundDark
                                          : Colors.white,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      user?.displayName ?? 'Usuário',
                                      style:
                                          AppTextStyles.headingSmall.copyWith(
                                        color: isDark
                                            ? AppColors.textLight
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.primary.withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(9999),
                                      ),
                                      child: Text(
                                        (user?.subscriptionTier ?? 'free')
                                            .toUpperCase(),
                                        style:
                                            AppTextStyles.labelSmall.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user?.email ?? '',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: isDark
                                        ? AppColors.textTertiary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Credits Usage
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
                              Text(
                                'Renova em 15 Out',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: isDark
                                      ? AppColors.textTertiary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Créditos de IA',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: isDark
                                      ? AppColors.textLight
                                      : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '64/100',
                                style: AppTextStyles.headingSmall.copyWith(
                                  color: isDark
                                      ? AppColors.textLight
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          AppProgressIndicator(progress: 0.64),
                          const SizedBox(height: 12),
                          Text(
                            'Você ainda tem 36 créditos premium este mês. Use para remoção de fundo e IA Generativa.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textTertiary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context)
                                    .pushNamed('/credits-shop');
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
                    // Account Section
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          'CONTA',
                          style: AppTextStyles.overline.copyWith(
                            color: isDark
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _ProfileOption(
                            icon: Icons.person,
                            label: 'Meus Dados',
                            onTap: () {
                              // TODO: Navigate to user data
                            },
                          ),
                          Divider(
                            height: 1,
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.border,
                          ),
                          _ProfileOption(
                            icon: Icons.receipt_long,
                            label: 'Histórico de Pagamentos',
                            onTap: () {
                              // TODO: Navigate to payment history
                            },
                          ),
                          Divider(
                            height: 1,
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.border,
                          ),
                          _ProfileOption(
                            icon: Icons.card_giftcard,
                            label: 'Indique e Ganhe',
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'NOVO',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.textLight,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 8,
                                ),
                              ),
                            ),
                            onTap: () {
                              Navigator.of(context).pushNamed('/affiliate');
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Promotional Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundDark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ganhe 10 créditos grátis',
                            style: AppTextStyles.headingSmall.copyWith(
                              color: AppColors.textLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Convide amigos para o Editai e ambos ganham créditos ao realizar a primeira edição.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textLight.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pushNamed('/affiliate');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: Text(
                              'Copiar link de convite',
                              style: AppTextStyles.labelMedium.copyWith(
                                color: AppColors.textLight,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Support Section
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          'SUPORTE',
                          style: AppTextStyles.overline.copyWith(
                            color: isDark
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _ProfileOption(
                            icon: Icons.help_outline,
                            label: 'Central de Ajuda',
                            trailing: const Icon(
                              Icons.open_in_new,
                              size: 20,
                              color: AppColors.textSecondary,
                            ),
                            onTap: () {
                              // TODO: Open help center
                            },
                          ),
                          Divider(
                            height: 1,
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.border,
                          ),
                          _ProfileOption(
                            icon: Icons.gavel,
                            label: 'Termos e Privacidade',
                            onTap: () {
                              // TODO: Navigate to terms
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Logout Button
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () async {
                          final signOut =
                              ref.read(auth_providers.signOutProvider);
                          final result = await signOut();
                          result.fold(
                            (failure) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erro ao sair'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            },
                            (_) {
                              ref
                                  .read(authStateProvider.notifier)
                                  .setUser(null);
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/login',
                                (route) => false,
                              );
                            },
                          );
                        },
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: Text(
                          'Sair da conta',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // App Version
                    Text(
                      'Editai Mobile v${AppConfig.appVersion} (Build 4482)',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 100), // Space for bottom nav
                  ],
                ),
              ),
            ),
            // Bottom Navigation
            ProfileBottomNav(
              currentIndex: 4,
              onTap: (index) {
                // TODO: Handle navigation
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ProfileOption({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              icon,
              color: AppColors.primary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isDark ? AppColors.textLight : AppColors.textPrimary,
                  fontWeight: label == 'Indique e Ganhe'
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Icon(
                Icons.chevron_right,
                color:
                    isDark ? AppColors.textTertiary : AppColors.textSecondary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
