import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../core/widgets/share_button.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class AffiliatePage extends ConsumerStatefulWidget {
  const AffiliatePage({super.key});

  @override
  ConsumerState<AffiliatePage> createState() => _AffiliatePageState();
}

class _AffiliatePageState extends ConsumerState<AffiliatePage> {
  final String _referralLink = 'editai.app/ref/UX24_MARCOS';
  int _currentNavIndex = 2;

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _referralLink));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copiado!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareViaWhatsApp() async {
    final message = 'Confira o Editai! $_referralLink';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _shareViaTelegram() async {
    final message = 'Confira o Editai! $_referralLink';
    final uri = Uri.parse('https://t.me/share/url?url=$_referralLink&text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _shareGeneric() {
    Share.share('Confira o Editai! $_referralLink');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

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
                    'Indique e ganhe',
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
                  children: [
                    // Visual Card
                    Container(
                      width: double.infinity,
                      height: 220,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.2),
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Decorative circles
                          Positioned(
                            top: 20,
                            left: 40,
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 40,
                            right: 60,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary.withOpacity(0.2),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 30,
                            left: 80,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary.withOpacity(0.3),
                              ),
                            ),
                          ),
                          // Content
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withOpacity(0.3),
                                        blurRadius: 20,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.group_add,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Cresça com a Editai',
                                  style: AppTextStyles.headingSmall.copyWith(
                                    color: isDark
                                        ? AppColors.textLight
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Title
                    Text(
                      'Indique e ganhe créditos',
                      style: AppTextStyles.headingLarge.copyWith(
                        color: isDark ? AppColors.textLight : AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Compartilhe seu link exclusivo. Para cada amigo que assinar, você ganha ',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: isDark
                              ? AppColors.textTertiary
                              : AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Referral Link
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? AppColors.borderDark : AppColors.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SEU LINK DE INDICAÇÃO',
                            style: AppTextStyles.overline.copyWith(
                              color: isDark
                                  ? AppColors.textTertiary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.backgroundDark
                                        : AppColors.backgroundLight,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.borderDark
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    _referralLink,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: isDark
                                          ? AppColors.textLight
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _copyLink,
                                icon: const Icon(Icons.content_copy, size: 18),
                                label: const Text('Copiar'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Stats
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            icon: Icons.person_add,
                            label: 'AMIGOS',
                            value: '12',
                            subtitle: '3 ativos este mês',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatCard(
                            icon: Icons.bolt,
                            label: 'CRÉDITOS',
                            value: '120',
                            subtitle: 'Disponíveis p/ uso',
                            subtitleColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Share Section
                    Text(
                      'Compartilhar via',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ShareButton(
                          icon: Icons.chat,
                          label: 'WhatsApp',
                          iconColor: const Color(0xFF25D366),
                          onTap: _shareViaWhatsApp,
                        ),
                        ShareButton(
                          icon: Icons.photo_camera,
                          label: 'Stories',
                          iconColor: const Color(0xFFE1306C),
                          onTap: _shareGeneric,
                        ),
                        ShareButton(
                          icon: Icons.send,
                          label: 'Telegram',
                          iconColor: const Color(0xFF0088cc),
                          onTap: _shareViaTelegram,
                        ),
                        ShareButton(
                          icon: Icons.more_horiz,
                          label: 'Mais',
                          onTap: _shareGeneric,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Details Link
                    TextButton(
                      onPressed: () {
                        // TODO: Navigate to referral details
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Ver detalhes das indicações',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Terms
                    Text(
                      'Sujeito aos Termos e Condições do programa de afiliados Editai.',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 100), // Space for bottom nav
                  ],
                ),
              ),
            ),
            // Bottom Navigation
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SimpleNavItem(
                    icon: Icons.home,
                    isSelected: false,
                    onTap: () => Navigator.of(context).pushNamed('/home'),
                  ),
                  _SimpleNavItem(
                    icon: Icons.auto_fix_high,
                    isSelected: false,
                    onTap: () {},
                  ),
                  _SimpleNavItem(
                    icon: Icons.share,
                    isSelected: true,
                    onTap: () {},
                  ),
                  _SimpleNavItem(
                    icon: Icons.person,
                    isSelected: false,
                    onTap: () => Navigator.of(context).pushNamed('/profile'),
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

class _SimpleNavItem extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SimpleNavItem({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Icon(
        icon,
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
        size: 24,
      ),
    );
  }
}
