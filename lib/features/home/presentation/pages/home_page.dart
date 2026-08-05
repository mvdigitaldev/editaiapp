import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/enable_plans_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/credit_indicator.dart';
import '../../../../core/widgets/hero_action_card.dart';
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
    ref.watch(enablePlansProvider);

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
                            final enabled =
                                ref.read(enablePlansProvider).valueOrNull ==
                                    true;
                            if (!enabled) return;
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
                  // Logo
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/branding/logo_mark.png',
                            height: 40,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'editaí',
                            style: AppTextStyles.headingMedium.copyWith(
                              color: isDark
                                  ? AppColors.textLight
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Opções principais
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        HeroActionCard(
                          index: 0,
                          icon: Icons.brush_outlined,
                          accentColor: const Color(0xFF3B82F6),
                          backgroundColor: const Color(0xFFEFF6FF),
                          backgroundColorDark: const Color(0xFF1E3A8A),
                          previewAsset: 'assets/home/home_preview_edit.png',
                          title: 'Editar manualmente',
                          description:
                              'Filtros, retoque beauty, presets e recorte — sem IA.',
                          onTap: () => Navigator.of(context)
                              .pushNamed('/manual-editing-hub'),
                        ),
                        const SizedBox(height: 12),
                        HeroActionCard(
                          index: 1,
                          icon: Icons.landscape_rounded,
                          accentColor: const Color(0xFF22C55E),
                          backgroundColor: const Color(0xFFECFDF5),
                          backgroundColorDark: const Color(0xFF14532D),
                          previewAsset: 'assets/home/home_preview_edit.png',
                          title: 'Editar com Inteligência Artificial',
                          description:
                              'Faça montagens, troque o fundo, peça o que quiser…',
                          onTap: () =>
                              Navigator.of(context).pushNamed('/edit-image'),
                        ),
                        const SizedBox(height: 12),
                        HeroActionCard(
                          index: 2,
                          icon: Icons.text_fields_rounded,
                          accentColor: const Color(0xFF8B5CF6),
                          backgroundColor: const Color(0xFFF5F3FF),
                          backgroundColorDark: const Color(0xFF2E1065),
                          previewAsset: 'assets/home/home_preview_text.png',
                          title: 'Imagem à partir de Texto',
                          description: 'Peça o que quer criar do zero.',
                          onTap: () =>
                              Navigator.of(context).pushNamed('/text-to-image'),
                        ),
                        const SizedBox(height: 12),
                        HeroActionCard(
                          index: 3,
                          icon: Icons.layers_rounded,
                          accentColor: const Color(0xFFF59E0B),
                          backgroundColor: const Color(0xFFFFFBEB),
                          backgroundColorDark: const Color(0xFF78350F),
                          previewAsset: 'assets/home/home_preview_compose.png',
                          title: 'Unir várias Fotos',
                          description:
                              'Combine vários elementos em uma única foto.',
                          onTap: () => Navigator.of(context)
                              .pushNamed('/create-composition'),
                        ),
                        const SizedBox(height: 12),
                        HeroActionCard(
                          index: 4,
                          icon: Icons.grid_on_rounded,
                          accentColor: const Color(0xFFEC4899),
                          backgroundColor: const Color(0xFFFDF2F8),
                          backgroundColorDark: const Color(0xFF831843),
                          previewAsset: 'assets/home/home_preview_bg.png',
                          title: 'Remover Fundo',
                          description: 'Remova com precisão.',
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
        return _RecentEditCard(
          edit: edit,
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

class _RecentEditCard extends StatelessWidget {
  final GalleryEditModel edit;
  final VoidCallback onTap;

  const _RecentEditCard({
    required this.edit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = edit.imageUrl;

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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            edit.status == 'failed'
                                ? Icons.error_outline
                                : edit.status == 'processing'
                                    ? Icons.auto_awesome
                                    : Icons.schedule,
                            color: edit.status == 'failed'
                                ? AppColors.error
                                : AppColors.primary,
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              edit.operationTypeLabel,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: isDark
                                    ? AppColors.textLight
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: edit.status == 'failed'
                      ? AppColors.error.withOpacity(0.92)
                      : edit.status == 'completed'
                          ? AppColors.primary.withOpacity(0.92)
                          : AppColors.overlay,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  edit.statusLabel,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
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
