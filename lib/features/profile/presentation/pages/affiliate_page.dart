import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../core/widgets/share_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/app_settings_datasource.dart';
import '../../data/datasources/referrals_datasource.dart';
import '../../data/models/referral_models.dart';

final _appSettingsProvider = Provider<AppSettingsDataSource>((ref) {
  return AppSettingsDataSourceImpl(Supabase.instance.client);
});

final _referralsDataSourceProvider = Provider<ReferralsDataSource>((ref) {
  return ReferralsDataSourceImpl(Supabase.instance.client);
});

class AffiliatePage extends ConsumerStatefulWidget {
  const AffiliatePage({super.key});

  @override
  ConsumerState<AffiliatePage> createState() => _AffiliatePageState();
}

class _AffiliatePageState extends ConsumerState<AffiliatePage> {
  String? _referralLink;
  ReferralSummary _summary = ReferralSummary.empty;
  bool _isLoadingSummary = false;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final authState = ref.read(authStateProvider);
    final user = authState.user;
    if (user == null) return;

    setState(() {
      _isLoadingSummary = true;
      _summaryError = null;
    });

    try {
      final settings = ref.read(_appSettingsProvider);
      final referralsDs = ref.read(_referralsDataSourceProvider);

      final results = await Future.wait([
        settings.getValue('referral_url'),
        referralsDs.getSummary(user.id),
      ]);

      final baseUrl = (results[0] as String?) ?? '';
      final summary = results[1] as ReferralSummary;

      final referralCode = user.referralCode;
      final builtLink = (baseUrl.isNotEmpty && referralCode != null)
          ? '$baseUrl$referralCode'
          : null;

      if (!mounted) return;
      setState(() {
        _referralLink = builtLink;
        _summary = summary;
        _isLoadingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = e.toString();
        _isLoadingSummary = false;
      });
    }
  }

  void _copyLink() {
    if (_referralLink == null) return;
    Clipboard.setData(ClipboardData(text: _referralLink!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copiado!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareViaWhatsApp() async {
    if (_referralLink == null) return;
    final message = 'Confira o Editai! $_referralLink';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _shareViaFacebook() {
    if (_referralLink == null) return;
    Share.share('Confira o Editai! $_referralLink');
  }

  void _shareViaInstagram() {
    if (_referralLink == null) return;
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
                          IntrinsicHeight(
                            child: Row(
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
                                      _referralLink ?? 'Link de indicação indisponível',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: isDark
                                            ? AppColors.textLight
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 96,
                                  child: SizedBox.expand(
                                    child: ElevatedButton.icon(
                                      onPressed: _referralLink == null ? null : _copyLink,
                                      icon: const Icon(Icons.content_copy, size: 18),
                                      label: const Text('Copiar'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                            value: _isLoadingSummary
                                ? '...'
                                : _summary.friendsCount.toString(),
                            subtitle: _summaryError != null
                                ? 'Erro ao carregar'
                                : 'Total indicados',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatCard(
                            icon: Icons.bolt,
                            label: 'CRÉDITOS',
                            value: _isLoadingSummary
                                ? '...'
                                : _summary.totalRewardCredits.toString(),
                            subtitle: _summaryError != null
                                ? 'Erro ao carregar'
                                : 'Ganhos com indicações',
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
                          icon: Icons.facebook,
                          label: 'Facebook',
                          iconColor: const Color(0xFF1877F2),
                          onTap: _shareViaFacebook,
                        ),
                        ShareButton(
                          icon: Icons.photo_camera,
                          label: 'Instagram',
                          iconColor: const Color(0xFFE1306C),
                          onTap: _shareViaInstagram,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Details Link
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed('/referral-details');
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
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
