import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/image_save_utils.dart';
import '../../../../core/widgets/app_card.dart';
import '../../data/models/edit_detail_model.dart';
import '../providers/gallery_provider.dart';

class EditDetailPage extends ConsumerStatefulWidget {
  final String editId;

  const EditDetailPage({super.key, required this.editId});

  @override
  ConsumerState<EditDetailPage> createState() => _EditDetailPageState();
}

class _EditDetailPageState extends ConsumerState<EditDetailPage> {
  EditDetailModel? _edit;
  bool _isLoading = true;
  bool _isDownloading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.editId.isEmpty) {
      setState(() {
        _error = 'Edição não encontrada';
        _isLoading = false;
      });
      return;
    }
    _loadEdit();
  }

  Future<void> _loadEdit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ds = ref.read(editsGalleryDataSourceProvider);
      final edit = await ds.getEditById(widget.editId);
      if (!mounted) return;
      setState(() {
        _edit = edit;
        _isLoading = false;
        if (edit == null) _error = 'Edição não encontrada';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadImage() async {
    final url = _edit?.imageUrl;
    if (url == null || url.isEmpty) return;
    setState(() => _isDownloading = true);
    try {
      final ok = await saveRemoteImageToGallery(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Imagem salva na galeria' : 'Não foi possível salvar a imagem',
          ),
          backgroundColor: ok ? null : Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.of(context).pop(),
                    color: isDark ? AppColors.textLight : AppColors.textPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Detalhe da edição',
                      style: AppTextStyles.headingSmall.copyWith(
                        color: isDark
                            ? AppColors.textLight
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (_edit?.imageUrl != null && _edit!.imageUrl!.isNotEmpty)
                    IconButton(
                      icon: _isDownloading
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isDark
                                    ? AppColors.textLight
                                    : AppColors.textPrimary,
                              ),
                            )
                          : const Icon(Icons.download_rounded),
                      onPressed: _isDownloading ? null : _downloadImage,
                      color: isDark ? AppColors.textLight : AppColors.textPrimary,
                      tooltip: 'Salvar na galeria',
                    ),
                ],
              ),
            ),
            Expanded(
              child: _buildBody(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
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
              'Carregando...',
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                _edit == null && _error == 'Edição não encontrada'
                    ? 'Edição não encontrada'
                    : 'Não foi possível carregar os detalhes.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: widget.editId.isEmpty ? null : _loadEdit,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final edit = _edit!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildImageSection(edit, isDark),
          const SizedBox(height: 20),
          _buildPromptCard(edit, isDark),
          const SizedBox(height: 12),
          _buildCategoryCard(edit, isDark),
          const SizedBox(height: 12),
          _buildStatusCard(edit, isDark),
          const SizedBox(height: 12),
          _buildUsageCard(edit, isDark),
          const SizedBox(height: 12),
          _buildMetadataCard(edit, isDark),
        ],
      ),
    );
  }

  Widget _buildImageSection(EditDetailModel edit, bool isDark) {
    final url = edit.imageUrl;
    return AppCard(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: url != null && url.isNotEmpty
            ? AspectRatio(
                aspectRatio: 1,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => _imagePlaceholder(isDark),
                ),
              )
            : _imagePlaceholder(isDark),
      ),
    );
  }

  Widget _imagePlaceholder(bool isDark) {
    return Container(
      height: 200,
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              'Imagem não disponível',
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptCard(EditDetailModel edit, bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prompt',
            style: AppTextStyles.labelMedium.copyWith(
              color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            edit.promptDisplay,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Prompt original',
            style: AppTextStyles.labelMedium.copyWith(
              color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            edit.promptTextOriginal ?? '—',
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(EditDetailModel edit, bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow('Categoria', edit.editCategoryLabel, isDark),
          const SizedBox(height: 8),
          _detailRow('Objetivo', edit.editGoalLabel, isDark),
          const SizedBox(height: 8),
          _detailRow('Estilo desejado', edit.desiredStyleLabel, isDark),
        ],
      ),
    );
  }

  Widget _buildStatusCard(EditDetailModel edit, bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow('Status', edit.statusLabel, isDark),
          const SizedBox(height: 8),
          _detailRow(
            'Tipo de operação',
            edit.operationTypeLabel,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildUsageCard(EditDetailModel edit, bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow('Créditos usados', '${edit.creditsUsed}', isDark),
          const SizedBox(height: 8),
          _detailRow('Criado em', edit.formattedCreatedAt, isDark),
        ],
      ),
    );
  }

  Widget _buildMetadataCard(EditDetailModel edit, bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow('Dimensões', edit.dimensionsText, isDark),
          const SizedBox(height: 8),
          _detailRow('Tipo MIME', edit.mimeType ?? '—', isDark),
          const SizedBox(height: 8),
          _detailRow(
            'Tempo de processamento (IA)',
            edit.processingTimeText,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDark ? AppColors.textLight : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
