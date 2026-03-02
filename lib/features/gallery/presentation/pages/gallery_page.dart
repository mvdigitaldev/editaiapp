import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_nav.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/models/gallery_edit_model.dart';
import '../../../subscription/presentation/providers/plan_limits_provider.dart';
import '../providers/gallery_provider.dart';

class GalleryPage extends ConsumerStatefulWidget {
  /// Quando true, exibe botão voltar no header (ex.: quando a página é aberta por push).
  final bool showBackButton;
  /// Quando true, exibe a barra inferior (não usar quando a página está dentro da MainShellPage).
  final bool showBottomNav;

  const GalleryPage({
    super.key,
    this.showBackButton = true,
    this.showBottomNav = false,
  });

  @override
  ConsumerState<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends ConsumerState<GalleryPage> {
  static const _pageSize = 20;
  static const _scrollThreshold = 200.0;

  final List<GalleryEditModel> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  late ScrollController _scrollController;

  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (_hasMore && !_isLoadingMore && position.pixels >= position.maxScrollExtent - _scrollThreshold) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _items.clear();
      _hasMore = true;
    });

    try {
      final ds = ref.read(editsGalleryDataSourceProvider);
      final list = await ds.getEditsForGallery(offset: 0, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(list);
        _hasMore = list.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final ds = ref.read(editsGalleryDataSourceProvider);
      final list = await ds.getEditsForGallery(offset: _items.length, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(list);
        _hasMore = list.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar mais: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedIds.clear();
    });
  }

  void _toggleItemSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _handleDelete() async {
    if (_selectedIds.isEmpty || _isDeleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir fotos'),
        content: Text(
          'Excluir ${_selectedIds.length} foto(s)? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      final ds = ref.read(editsDeleteDataSourceProvider);
      final ids = _selectedIds.toList();
      await ds.deleteEdits(ids);

      if (!mounted) return;

      ref.invalidate(planLimitsProvider);
      ref.invalidate(recentEditsProvider);

      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
        _isDeleting = false;
      });

      _loadFirst();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ids.length} foto(s) excluída(s)'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao excluir: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final planLimitsAsync = ref.watch(planLimitsProvider);

    final subtitleText = planLimitsAsync.when(
      data: (limits) => '${limits.storedPhotosCount} foto${limits.storedPhotosCount != 1 ? 's' : ''} · Arraste para atualizar',
      loading: () => 'Arraste para atualizar',
      error: (_, __) => 'Arraste para atualizar',
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Esquerda: voltar + Galeria + subtítulo
                  Expanded(
                    child: Row(
                      children: [
                        if (widget.showBackButton)
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Galeria',
                                style: AppTextStyles.headingMedium.copyWith(
                                  color: isDark ? AppColors.textLight : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitleText,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Direita: Selecionar/Concluir
                  if (_items.isNotEmpty)
                    TextButton(
                      onPressed: _toggleSelectionMode,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _isSelectionMode ? 'Concluir' : 'Selecionar',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildBody(isDark)),
            if (_isSelectionMode && _selectedIds.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? AppColors.borderDark : AppColors.border,
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: AppButton(
                    text: 'Excluir ${_selectedIds.length}',
                    onPressed: _isDeleting ? null : _handleDelete,
                    icon: Icons.delete_outline,
                    width: double.infinity,
                    isLoading: _isDeleting,
                  ),
                ),
              ),
            if (widget.showBottomNav)
              AppBottomNav(
                currentIndex: 1,
                onTap: (_) {},
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Carregando fotos...',
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null && _items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirst,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 200,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text(
                      'Não foi possível carregar a galeria.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _loadFirst,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirst,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 200,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 64,
                    color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma foto na galeria',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Puxe para baixo para ver novas edições',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: GridView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
          childAspectRatio: 1,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            );
          }

          final item = _items[index];
          final url = item.imageUrl;
          if (url == null || url.isEmpty) {
            return const SizedBox.shrink();
          }

          final isSelected = _selectedIds.contains(item.id);

          return InkWell(
            onTap: () {
              if (_isSelectionMode) {
                _toggleItemSelection(item.id);
              } else {
                Navigator.of(context)
                    .pushNamed('/edit-detail', arguments: item.id)
                    .then((_) {
                  if (mounted) _loadFirst();
                });
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    child: Icon(Icons.broken_image_outlined, color: AppColors.textTertiary),
                  ),
                ),
                if (_isSelectionMode)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? Colors.black54 : Colors.white54),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? AppColors.textLight : AppColors.textPrimary,
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
