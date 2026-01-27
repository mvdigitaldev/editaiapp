import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/credit_indicator.dart';
import '../../../../core/widgets/upload_area.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentNavIndex = 0;
  String? _selectedImagePath;

  void _handleImageSelected(File image) {
    setState(() {
      _selectedImagePath = image.path;
    });
    // Navigate to pre-evaluation
    Navigator.of(context).pushNamed('/pre-evaluation', arguments: image.path);
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.2),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: user?.avatarUrl != null
                                ? Image.network(
                                    user!.avatarUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.person),
                                  )
                                : const Icon(Icons.person),
                          ),
                        ),
                        const Spacer(),
                        // Credits
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).pushNamed('/credits-shop');
                          },
                          child: CreditIndicator(credits: 10),
                        ),
                      ],
                    ),
                  ),
                  // Title Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Editai',
                          style: AppTextStyles.displayMedium.copyWith(
                            color: isDark ? AppColors.textLight : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Seu estúdio de edição com IA',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Upload Area
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: UploadArea(
                      imagePath: _selectedImagePath,
                      onImageSelected: _handleImageSelected,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Quick Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _QuickActionChip(
                            icon: Icons.auto_fix_high,
                            label: 'Auto-ajuste',
                            onTap: () {},
                          ),
                          const SizedBox(width: 12),
                          _QuickActionChip(
                            icon: Icons.wallpaper,
                            label: 'Remover Fundo',
                            onTap: () {},
                          ),
                          const SizedBox(width: 12),
                          _QuickActionChip(
                            icon: Icons.aspect_ratio,
                            label: 'Upscale',
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Recent Edits
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Edições Recentes',
                          style: AppTextStyles.headingSmall.copyWith(
                            color: isDark ? AppColors.textLight : AppColors.textPrimary,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/gallery');
                          },
                          child: Text(
                            'Ver tudo',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Recent Edits Grid
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1,
                      ),
                      itemCount: 4,
                      itemBuilder: (context, index) {
                        return _RecentEditCard(
                          imageUrl: 'https://picsum.photos/400?random=$index',
                          onTap: () {
                            // TODO: Navigate to edit details
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 100), // Space for bottom nav
                ],
              ),
            ),
            // Bottom Navigation
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AppBottomNav(
                currentIndex: _currentNavIndex,
                onTap: (index) {
                  setState(() {
                    _currentNavIndex = index;
                  });
                  switch (index) {
                    case 0:
                      // Already on home
                      break;
                    case 1:
                      Navigator.of(context).pushNamed('/gallery');
                      break;
                    case 2:
                      // Tools - TODO
                      break;
                    case 3:
                      Navigator.of(context).pushNamed('/profile');
                      break;
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark ? AppColors.textLight : AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentEditCard extends StatelessWidget {
  final String imageUrl;
  final VoidCallback onTap;

  const _RecentEditCard({
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border,
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.border,
                  child: const Icon(Icons.image),
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.overlay,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.edit,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
