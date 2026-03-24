import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/postgrest_user_message.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/categoria_model.dart';
import '../providers/modelos_provider.dart';

Future<void> _confirmDeleteCategoria(
  BuildContext context,
  WidgetRef ref,
  CategoriaModel categoria,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir categoria?'),
      content: Text(
        '«${categoria.nome}» será removida. Se ainda existirem modelos vinculados, a operação falhará.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(modelosDataSourceProvider).deleteCategoria(categoria.id);
    ref.invalidate(categoriasProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Categoria removida')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(postgrestUserMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// Página inicial de Modelos: exibe categorias. Ao tocar, navega para modelos da categoria.
class ModelsPage extends ConsumerWidget {
  const ModelsPage({super.key});

  static const double _cardHeight = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categoriasAsync = ref.watch(categoriasProvider);
    final isAdmin = ref.watch(authStateProvider).user?.isAdmin ?? false;

    return SafeArea(
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        floatingActionButton: isAdmin
            ? FloatingActionButton.extended(
                onPressed: () {
                  Navigator.of(context)
                      .pushNamed('/admin/categoria/form')
                      .then((saved) {
                    if (saved == true) ref.invalidate(categoriasProvider);
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Nova categoria'),
              )
            : null,
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
                      'Escolha uma categoria e use um modelo pronto',
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
            categoriasAsync.when(
              data: (categorias) {
                if (categorias.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Nenhuma categoria disponível no momento.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: isDark
                              ? AppColors.textTertiary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final categoria = categorias[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CategoriaCard(
                            categoria: categoria,
                            isDark: isDark,
                            isAdmin: isAdmin,
                            onTap: () {
                              Navigator.of(context).pushNamed(
                                '/models-by-category',
                                arguments: <String, dynamic>{
                                  'categoriaId': categoria.id,
                                  'categoriaNome': categoria.nome,
                                  'categoria': categoria,
                                },
                              );
                            },
                            onAdminEdit: () {
                              Navigator.of(context)
                                  .pushNamed(
                                    '/admin/categoria/form',
                                    arguments: <String, dynamic>{
                                      'categoria': categoria,
                                    },
                                  )
                                  .then((saved) {
                                if (saved == true) {
                                  ref.invalidate(categoriasProvider);
                                }
                              });
                            },
                            onAdminDelete: () =>
                                _confirmDeleteCategoria(context, ref, categoria),
                          ),
                        );
                      },
                      childCount: categorias.length,
                    ),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Erro ao carregar categorias. Tente novamente.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
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

class _CategoriaCard extends StatelessWidget {
  final CategoriaModel categoria;
  final bool isDark;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback onAdminEdit;
  final VoidCallback onAdminDelete;

  const _CategoriaCard({
    required this.categoria,
    required this.isDark,
    required this.isAdmin,
    required this.onTap,
    required this.onAdminEdit,
    required this.onAdminDelete,
  });

  @override
  Widget build(BuildContext context) {
    final surface =
        isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final themeBg =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final url = categoria.coverImageUrl;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: ModelsPage._cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.border,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null)
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => ColoredBox(color: surface),
                  errorWidget: (_, __, ___) => ColoredBox(color: surface),
                )
              else
                ColoredBox(color: surface),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0.0, 0.3, 1.0],
                    colors: [
                      themeBg,
                      themeBg,
                      themeBg.withValues(alpha: 0.50),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (isAdmin) ...[
                      Material(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.more_vert,
                              size: 20,
                              color: Colors.white,
                            ),
                            onSelected: (v) {
                              if (v == 'edit') onAdminEdit();
                              if (v == 'delete') onAdminDelete();
                            },
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Editar'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Excluir'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        categoria.nome,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.textLight
                              : AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
            ],
          ),
        ),
      ),
    );
  }
}
