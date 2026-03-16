import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/widgets/typewriter_with_delete_text.dart';
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Seu estúdio de ',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: TypewriterWithDeleteText(
                                phrases: const [
                                  'edição com IA',
                                  'criação com IA',
                                  'transformação com IA',
                                  'produção com IA',
                                  'inovação com IA',
                                ],
                                textStyle: AppTextStyles.bodyMedium.copyWith(
                                  color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                                ),
                                typingSpeed: const Duration(milliseconds: 100),
                                deletingSpeed: const Duration(milliseconds: 80),
                                pauseAfterTyping: const Duration(milliseconds: 1500),
                                pauseAfterDeleting: const Duration(milliseconds: 500),
                                cursor: '|',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 4 opções principais (cards horizontais)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        _HeroActionCard(
                          index: 1,
                          icon: Icons.edit,
                          title: 'Editar imagem',
                          description:
                              'Ajuste cores, iluminação e detalhes com IA.',
                          onTap: () =>
                              Navigator.of(context).pushNamed('/edit-image'),
                        ),
                        const SizedBox(height: 12),
                        _HeroActionCard(
                          index: 0,
                          icon: Icons.text_fields,
                          title: 'Texto para imagem',
                          description:
                              'Gere imagens originais a partir de descrições.',
                          onTap: () =>
                              Navigator.of(context).pushNamed('/text-to-image'),
                        ),
                        const SizedBox(height: 12),
                        _HeroActionCard(
                          index: 2,
                          icon: Icons.collections,
                          title: 'Unir fotos',
                          description:
                              'Combine vários elementos em uma cena única.',
                          onTap: () => Navigator.of(context)
                              .pushNamed('/create-composition'),
                        ),
                        const SizedBox(height: 12),
                        _HeroActionCard(
                          index: 3,
                          icon: Icons.wallpaper,
                          title: 'Remover fundo',
                          description:
                              'Remova o fundo em segundos, com precisão.',
                          onTap: () => Navigator.of(context)
                              .pushNamed('/remove-background'),
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.18),
                      AppColors.primary.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color:
                            isDark ? AppColors.textLight : AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Toque para começar',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color:
                    isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroActionCard extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _HeroActionCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.22),
                        AppColors.primary.withOpacity(0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 26,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.headingSmall.copyWith(
                          color: isDark
                              ? AppColors.textLight
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textTertiary
                              : AppColors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color:
                      isDark ? AppColors.textTertiary : AppColors.textSecondary,
                ),
              ],
            ),
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
