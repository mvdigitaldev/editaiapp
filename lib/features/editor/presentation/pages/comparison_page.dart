import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/ad_banner_widget.dart';
import '../../../../core/widgets/comparison_slider.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/utils/image_save_utils.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../gallery/presentation/providers/gallery_provider.dart';
import '../../../subscription/presentation/providers/credits_usage_provider.dart';
import '../../../subscription/presentation/providers/plan_limits_provider.dart';

/// Mesmo padrão visual que [EditDetailPage] (`AspectRatio` + slider ou `CachedNetworkImage` com `cover`), sem `maxHeight` no comparador — isso encolhia fotos verticais e deslocava o bloco para a esquerda.
class ComparisonPage extends ConsumerStatefulWidget {
  final String? editId;
  final String? beforeImagePath;
  final String? afterImagePath;
  final String? afterImageUrl;

  const ComparisonPage({
    super.key,
    this.editId,
    this.beforeImagePath,
    this.afterImagePath,
    this.afterImageUrl,
  });

  @override
  ConsumerState<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends ConsumerState<ComparisonPage> {
  bool _isDownloading = false;
  bool _isLoadingEdit = false;
  String? _originalImageUrl;
  String? _afterImageUrl;
  String? _operationType;
  int? _width;
  int? _height;

  @override
  void initState() {
    super.initState();
    if (widget.editId != null && widget.editId!.isNotEmpty) {
      _isLoadingEdit = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowInterstitial();
      if (widget.editId != null && widget.editId!.isNotEmpty) {
        _fetchEdit();
      }
    });
  }

  Future<void> _fetchEdit() async {
    if (widget.editId == null) return;
    setState(() => _isLoadingEdit = true);
    try {
      final res = await Supabase.instance.client
          .from('edits')
          .select('original_image_url, image_url, operation_type, width, height')
          .eq('id', widget.editId!)
          .maybeSingle();
      if (mounted && res != null) {
        setState(() {
          _originalImageUrl = res['original_image_url'] as String?;
          _afterImageUrl = res['image_url'] as String?;
          _operationType = res['operation_type'] as String?;
          _width = res['width'] as int?;
          _height = res['height'] as int?;
          _isLoadingEdit = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingEdit = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingEdit = false);
    }
  }

  void _maybeShowInterstitial() {
    if (kIsWeb) return;
    final user = ref.read(authStateProvider).user;
    if (user?.subscriptionTier.toLowerCase() != 'free') return;
    ref.read(adServiceProvider).loadAndShowInterstitial();
  }

  void _goBackToHome() {
    ref.invalidate(recentEditsProvider);
    ref.invalidate(creditsUsageProvider);
    ref.invalidate(planLimitsProvider);
    ref.invalidate(currentMonthUsageTotalProvider);
    Navigator.of(context).popUntil((route) =>
        route.settings.name == '/' || route.settings.name == '/home' || route.isFirst);
  }

  String? get _effectiveAfterUrl =>
      _afterImageUrl ?? widget.afterImageUrl;

  static const _noComparisonTypes = ['text_to_image', 'multi_image'];

  bool get _hasBeforeAndAfter {
    if (_operationType != null &&
        _noComparisonTypes.contains(_operationType)) {
      return false;
    }
    final before = _originalImageUrl ?? widget.beforeImagePath;
    final after = _effectiveAfterUrl ?? widget.afterImagePath;
    return before != null && after != null;
  }

  double get _aspectRatio {
    if (_width != null && _height != null && _width! > 0 && _height! > 0) {
      return _width! / _height!;
    }
    return 1;
  }

  Widget _buildImageArea(bool isDark) {
    if (widget.editId != null &&
        widget.editId!.isNotEmpty &&
        _isLoadingEdit) {
      return SizedBox(
        height: 280,
        child: ColoredBox(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_hasBeforeAndAfter) {
      return AspectRatio(
        aspectRatio: _aspectRatio,
        child: ComparisonSlider(
          beforeImageUrl: _originalImageUrl,
          beforeImagePath:
              _originalImageUrl != null ? null : widget.beforeImagePath,
          afterImageUrl: _effectiveAfterUrl,
          afterImagePath:
              _effectiveAfterUrl != null ? null : widget.afterImagePath,
        ),
      );
    }

    final afterUrl = _effectiveAfterUrl;
    if (afterUrl != null) {
      return AspectRatio(
        aspectRatio: _aspectRatio,
        child: CachedNetworkImage(
          imageUrl: afterUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          placeholder: (_, __) => Container(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, __, ___) => Container(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            child: const Center(child: Icon(Icons.error_outline)),
          ),
        ),
      );
    }

    if (widget.afterImagePath != null) {
      return AspectRatio(
        aspectRatio: _aspectRatio,
        child: Image.file(
          File(widget.afterImagePath!),
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: ColoredBox(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image,
                size: 64,
                color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'Imagem gerada',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleDownload() async {
    if (_isDownloading) return;

    final afterUrl = _effectiveAfterUrl;
    if (afterUrl != null) {
      setState(() => _isDownloading = true);
      final success = await saveRemoteImageToGallery(afterUrl);
      if (!mounted) return;
      setState(() => _isDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Imagem salva na galeria com sucesso!'
                : 'Não foi possível salvar a imagem. Verifique as permissões e tente novamente.',
          ),
        ),
      );
      return;
    }

    final path = widget.afterImagePath ?? widget.beforeImagePath;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma imagem disponível para salvar.'),
        ),
      );
      return;
    }

    setState(() => _isDownloading = true);
    final success = await saveLocalImageToGallery(path);
    if (!mounted) return;
    setState(() => _isDownloading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Imagem salva na galeria com sucesso!'
              : 'Não foi possível salvar a imagem. Verifique as permissões e tente novamente.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: _goBackToHome,
                  ),
                  const Spacer(),
                  Text(
                    'Resultado',
                    style: AppTextStyles.headingMedium.copyWith(
                      color: isDark ? AppColors.textLight : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _goBackToHome,
                    child: Text(
                      'Concluir',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Sua criação está pronta',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildImageArea(isDark),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.backgroundDark
                    : AppColors.backgroundLight,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.borderDark : AppColors.border,
                  ),
                ),
              ),
              child: AppButton(
                text: 'Baixar imagem',
                onPressed: _handleDownload,
                icon: Icons.download,
                isLoading: _isDownloading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
