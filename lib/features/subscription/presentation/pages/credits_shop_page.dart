import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/credit_indicator.dart';
import '../../../../core/widgets/credit_pack_card.dart';
import '../../../../core/widgets/app_card.dart';

class CreditsShopPage extends StatelessWidget {
  const CreditsShopPage({super.key});

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
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    'Extra Credits',
                    style: AppTextStyles.headingMedium.copyWith(
                      color: isDark ? AppColors.textLight : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // Balance Badge
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storage,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Balance: 12 Credits',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
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
                      constraints: const BoxConstraints(maxHeight: 240),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primary.withOpacity(0.05),
                            AppColors.primary.withOpacity(0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.1),
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Animated circles
                          Container(
                            width: 128,
                            height: 128,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.2),
                                width: 2,
                              ),
                            ),
                          ),
                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.1),
                              ),
                            ),
                          ),
                          // Icon
                          Icon(
                            Icons.generating_tokens,
                            size: 120,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Title
                    Text(
                      'Fuel your creativity',
                      style: AppTextStyles.headingLarge.copyWith(
                        color: isDark ? AppColors.textLight : AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose a pack to unlock premium AI tools',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    // Credit Packs
                    CreditPackCard(
                      icon: Icons.token,
                      name: 'Starter Pack',
                      credits: 10,
                      price: '\$2.99',
                      onTap: () {
                        // TODO: Purchase starter pack
                      },
                    ),
                    const SizedBox(height: 16),
                    CreditPackCard(
                      icon: Icons.toll,
                      name: 'Pro Pack',
                      credits: 50,
                      price: '\$9.99',
                      isPopular: true,
                      onTap: () {
                        // TODO: Purchase pro pack
                      },
                    ),
                    const SizedBox(height: 16),
                    CreditPackCard(
                      icon: Icons.layers,
                      name: 'Studio Pack',
                      credits: 150,
                      price: '\$24.99',
                      hasSavings: true,
                      onTap: () {
                        // TODO: Purchase studio pack
                      },
                    ),
                    const SizedBox(height: 32),
                    // Info Card
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
                              '1 Credit = 1 AI Enhancement. Use them for Face Swap, Upscaling, Background Removal, and Style Transfer. Credits never expire.',
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
                    // Restore Purchases
                    TextButton(
                      onPressed: () {
                        // TODO: Restore purchases
                      },
                      child: Text(
                        'Restore Purchases',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Terms & Privacy
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            // TODO: Terms
                          },
                          child: Text(
                            'TERMS',
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
                            // TODO: Privacy
                          },
                          child: Text(
                            'PRIVACY',
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
