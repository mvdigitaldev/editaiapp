import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';

/// Página de modelos pré-configurados de edição que o usuário pode aplicar.
class ModelsPage extends ConsumerWidget {
  /// Chamado ao selecionar um modelo (ex.: para abrir o editor na shell).
  final VoidCallback? onOpenEditor;

  const ModelsPage({super.key, this.onOpenEditor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Modelos pré-configurados (placeholder; pode vir do backend depois)
    final models = [
      _ModelItem(
        icon: Icons.auto_fix_high,
        title: 'Melhorar cores',
        description: 'Ajuste automático de contraste e saturação',
      ),
      _ModelItem(
        icon: Icons.landscape_outlined,
        title: 'Remover fundo',
        description: 'Deixe apenas o assunto em destaque',
      ),
      _ModelItem(
        icon: Icons.face_retouching_natural,
        title: 'Retoque natural',
        description: 'Suavizar pele mantendo detalhes',
      ),
      _ModelItem(
        icon: Icons.style,
        title: 'Estilo artístico',
        description: 'Transforme em pintura ou ilustração',
      ),
      _ModelItem(
        icon: Icons.wb_sunny_outlined,
        title: 'Ajustar iluminação',
        description: 'Corrigir fotos escuras ou queimadas',
      ),
    ];

    return SafeArea(
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Modelos',
                      style: AppTextStyles.headingLarge.copyWith(
                        color: isDark
                            ? AppColors.textLight
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Use um modelo pronto e edite em um toque',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final model = models[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppCard(
                        padding: const EdgeInsets.all(16),
                        child: InkWell(
                          onTap: () {
                            if (onOpenEditor != null) {
                              onOpenEditor!();
                            } else {
                              Navigator.of(context).pushNamed('/home');
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  model.icon,
                                  color: AppColors.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      model.title,
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? AppColors.textLight
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      model.description,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: isDark
                                            ? AppColors.textTertiary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: isDark
                                    ? AppColors.textTertiary
                                    : AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: models.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _ModelItem {
  final IconData icon;
  final String title;
  final String description;

  _ModelItem({
    required this.icon,
    required this.title,
    required this.description,
  });
}
