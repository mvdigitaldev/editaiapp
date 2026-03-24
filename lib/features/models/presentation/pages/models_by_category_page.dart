import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/postgrest_user_message.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/categoria_model.dart';
import '../../data/models/modelo_model.dart';
import '../providers/modelos_provider.dart';

Future<void> _confirmDeleteModelo(
  BuildContext context,
  WidgetRef ref,
  ModeloModel modelo,
  String categoriaId,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir modelo?'),
      content: Text('«${modelo.nome}» será removido.'),
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
    await ref.read(modelosDataSourceProvider).deleteModelo(modelo.id);
    ref.invalidate(modelosPorCategoriaProvider(categoriaId));
    ref.invalidate(categoriasProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modelo removido')),
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

/// Página de modelos por categoria. Layout estilo Nano Banana: thumbnail + prompt + botão Editar.
///
/// Tamanho recomendado para thumbnail_url: ~800x450px ou 1200x675px (aspect ratio 16:9)
/// para preencher o espaço do card sem distorção. Com BoxFit.cover, imagens maiores
/// são redimensionadas e recortadas para preencher.
class ModelsByCategoryPage extends ConsumerWidget {
  const ModelsByCategoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final categoriaId = args?['categoriaId'] as String?;
    final categoriaNome = args?['categoriaNome'] as String? ?? 'Modelos';
    final categoriaCtx = args?['categoria'] as CategoriaModel?;
    final isAdmin = ref.watch(authStateProvider).user?.isAdmin ?? false;

    if (categoriaId == null || categoriaId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Erro'),
        ),
        body: const Center(child: Text('Categoria inválida. Volte e tente novamente.')),
      );
    }

    final modelosAsync = ref.watch(modelosPorCategoriaProvider(categoriaId));

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
          color: isDark ? AppColors.textLight : AppColors.textPrimary,
        ),
        title: Text(
          categoriaNome,
          style: AppTextStyles.headingMedium.copyWith(
            color: isDark ? AppColors.textLight : AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          if (isAdmin) ...[
            if (categoriaCtx != null)
              IconButton(
                tooltip: 'Editar categoria',
                icon: const Icon(Icons.edit_note),
                color: isDark ? AppColors.textLight : AppColors.textPrimary,
                onPressed: () {
                  Navigator.of(context)
                      .pushNamed(
                        '/admin/categoria/form',
                        arguments: <String, dynamic>{
                          'categoria': categoriaCtx,
                        },
                      )
                      .then((saved) {
                    if (saved == true) {
                      ref.invalidate(categoriasProvider);
                      ref.invalidate(modelosPorCategoriaProvider(categoriaId));
                    }
                  });
                },
              ),
            IconButton(
              tooltip: 'Novo modelo',
              icon: const Icon(Icons.add),
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
              onPressed: () {
                Navigator.of(context)
                    .pushNamed(
                      '/admin/modelo/form',
                      arguments: <String, dynamic>{
                        'categoriaId': categoriaId,
                        'categoriaNome': categoriaNome,
                      },
                    )
                    .then((saved) {
                  if (saved == true) {
                    ref.invalidate(modelosPorCategoriaProvider(categoriaId));
                    ref.invalidate(categoriasProvider);
                  }
                });
              },
            ),
          ],
        ],
      ),
      body: modelosAsync.when(
        data: (modelos) {
          if (modelos.isEmpty) {
            return Center(
              child: Text(
                'Nenhum modelo nesta categoria.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                ),
              ),
            );
          }
          final viewportWidth = MediaQuery.of(context).size.width;
          final cardHeight = (viewportWidth - 32) * 9 / 16;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final modelo = modelos[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: SizedBox(
                          height: cardHeight,
                          child: _ModeloCard(
                            modelo: modelo,
                            categoriaNome: categoriaNome,
                            isDark: isDark,
                            isAdmin: isAdmin,
                            onAdminEdit: () {
                              Navigator.of(context)
                                  .pushNamed(
                                    '/admin/modelo/form',
                                    arguments: <String, dynamic>{
                                      'categoriaId': categoriaId,
                                      'categoriaNome': categoriaNome,
                                      'modelo': modelo,
                                    },
                                  )
                                  .then((saved) {
                                if (saved == true) {
                                  ref.invalidate(
                                    modelosPorCategoriaProvider(categoriaId),
                                  );
                                  ref.invalidate(categoriasProvider);
                                }
                              });
                            },
                            onAdminDelete: () => _confirmDeleteModelo(
                              context,
                              ref,
                              modelo,
                              categoriaId,
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: modelos.length,
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Erro ao carregar modelos. Tente novamente.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeloCard extends StatelessWidget {
  final ModeloModel modelo;
  final String categoriaNome;
  final bool isDark;
  final bool isAdmin;
  final VoidCallback onAdminEdit;
  final VoidCallback onAdminDelete;

  const _ModeloCard({
    required this.modelo,
    required this.categoriaNome,
    required this.isDark,
    required this.isAdmin,
    required this.onAdminEdit,
    required this.onAdminDelete,
  });

  @override
  Widget build(BuildContext context) {
    final descricao = modelo.descricao ?? modelo.promptPadrao ?? modelo.nome;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () {
            Navigator.of(context).pushNamed(
              '/edit-model',
              arguments: <String, dynamic>{
                'modeloId': modelo.id,
                'modeloNome': modelo.nome,
                'categoriaNome': categoriaNome,
                'modeloDescricao': modelo.descricao,
                'modeloPromptPadrao': modelo.promptPadrao,
              },
            );
          },
          child: Card(
            clipBehavior: Clip.antiAlias,
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark ? AppColors.borderDark : AppColors.border,
                width: 1,
              ),
            ),
            child: _buildThumbnailWithOverlay(descricao),
          ),
        ),
        if (isAdmin)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, size: 22, color: Colors.white),
                onSelected: (v) {
                  if (v == 'edit') onAdminEdit();
                  if (v == 'delete') onAdminDelete();
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'delete', child: Text('Excluir')),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildThumbnailWithOverlay(String descricao) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildThumbnail(),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.75),
                  Colors.black.withValues(alpha: 0.9),
                ],
                stops: const [0.0, 0.4, 0.75, 1.0],
              ),
            ),
            child: Text(
              descricao,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnail() {
    final url = modelo.thumbnailUrl;
    if (url != null && url.trim().isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      child: Center(
        child: Icon(
          Icons.auto_fix_high,
          size: 48,
          color: AppColors.primary.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
