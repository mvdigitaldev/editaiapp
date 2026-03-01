import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/credit_indicator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../gallery/data/models/gallery_edit_model.dart';
import '../../../gallery/presentation/providers/gallery_provider.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final creditsUsageAsync = ref.watch(creditsUsageProvider);
    final recentEditsAsync = ref.watch(recentEditsProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(recentEditsProvider);
            await ref.read(recentEditsProvider.future);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                          child: creditsUsageAsync.when(
                            loading: () => const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            ),
                            error: (_, __) => CreditIndicator(
                              credits: user?.creditsBalance ?? 0,
                            ),
                            data: (usage) => CreditIndicator(
                              credits: usage.balance,
                            ),
                          ),
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
                  // 4 opções principais (grid 2x2)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.1,
                      children: [
                        _OptionCard(
                          icon: Icons.text_fields,
                          label: 'Texto para imagem',
                          onTap: () => Navigator.of(context).pushNamed('/text-to-image'),
                        ),
                        _OptionCard(
                          icon: Icons.edit,
                          label: 'Editar imagem',
                          onTap: () => Navigator.of(context).pushNamed('/edit-image'),
                        ),
                        _OptionCard(
                          icon: Icons.collections,
                          label: 'Criar composição',
                          onTap: () => Navigator.of(context).pushNamed('/create-composition'),
                        ),
                        _OptionCard(
                          icon: Icons.wallpaper,
                          label: 'Remover fundo',
                          onTap: () => Navigator.of(context).pushNamed('/remove-background'),
                        ),
                      ],
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
                    child: _buildRecentEditsGrid(context, isDark, recentEditsAsync),
                  ),
              const SizedBox(height: 32),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildRecentEditsGrid(
    BuildContext context,
    bool isDark,
    AsyncValue<List<GalleryEditModel>> recentEditsAsync,
  ) {
    return recentEditsAsync.when(
      loading: () => SizedBox(
        height: 180,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ),
      ),
      error: (_, __) => Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border,
          ),
        ),
        child: Text(
          'Nenhuma edição recente',
          style: AppTextStyles.bodySmall.copyWith(
            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
          ),
        ),
      ),
      data: (recentEdits) {
        if (recentEdits.isEmpty) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border,
          ),
        ),
        child: Text(
          'Nenhuma edição recente',
          style: AppTextStyles.bodySmall.copyWith(
            color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemCount: recentEdits.length,
      itemBuilder: (context, index) {
        final edit = recentEdits[index];
        final url = edit.imageUrl;
        return _RecentEditCard(
          imageUrl: url,
          onTap: () {
            Navigator.of(context).pushNamed(
              '/edit-detail',
              arguments: edit.id,
            );
          },
        );
      },
    );
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: AppColors.primary),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: isDark ? AppColors.textLight : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentEditCard extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback onTap;

  const _RecentEditCard({
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = imageUrl;

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
              child: url != null && url.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: url,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.border,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    )
                  : Container(
                      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      child: const Icon(Icons.image),
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
